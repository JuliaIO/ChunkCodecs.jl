# Code ported from the libbitshuffle C library <https://github.com/kiyo-masui/bitshuffle>
# There is a copy of the C library's license at the end of this file.
module ChunkCodecBitshuffle

using ChunkCodecCore:
    Codec,
    EncodeOptions,
    DecodeOptions,
    check_in_range,
    check_contiguous,
    DecodingError
import ChunkCodecCore:
    decode_options,
    try_decode!,
    try_encode!,
    encode_bound,
    try_find_decoded_size,
    decoded_size_range,
    is_thread_safe,
    is_lossless

export BShufDecodingError,
    BShufCodec,
    BShufEncodeOptions,
    BShufDecodeOptions,
    BShufZCodec,
    BShufZEncodeOptions,
    BShufZDecodeOptions

# reexport ChunkCodecCore
using ChunkCodecCore: ChunkCodecCore, encode, decode
export ChunkCodecCore, encode, decode

# constants
const MIN_RECOMMEND_BLOCK = Int64(128)
const BLOCKED_MULT = Int64(8)
const TARGET_BLOCK_SIZE_B = Int64(8192)

"""
    BShufDecodingError(msg)

Error for data that cannot be decoded.
"""
struct BShufDecodingError <: DecodingError
    msg::String
end

function Base.showerror(io::IO, err::BShufDecodingError)
    print(io, "BShufDecodingError: ")
    print(io, err.msg)
    nothing
end

function store_int32_BE!(dst, offset, val::Int32)
    for i in 0:3
        dst[begin+offset+i] = (val>>>(3*8 - i*8))%UInt8
    end
end
function store_int64_BE!(dst, offset, val::Int64)
    for i in 0:7
        dst[begin+offset+i] = (val>>>(7*8 - i*8))%UInt8
    end
end
function load_int32_BE(src, offset)::Int32
    val = Int32(0)
    for i in 0:3
        val |= Int32(src[begin+offset+i])<<(3*8 - i*8)
    end
    val
end
function load_int64_BE(src, offset)::Int64
    val = Int64(0)
    for i in 0:7
        val |= Int64(src[begin+offset+i])<<(7*8 - i*8)
    end
    val
end

"""
    default_block_size(elem_size::Int64)::Int64

Return the block size used by the blocked routines (any routine
taking a *block_size* argument) when the block_size is not provided
(zero is passed).

The results of this routine are guaranteed to be stable such that
shuffled/compressed data can always be decompressed.
"""
function default_block_size(elem_size::Int64)::Int64
    block_size = fld(TARGET_BLOCK_SIZE_B, elem_size)
    # Ensure it is a required multiple.
    block_size = fld(block_size, BLOCKED_MULT) * BLOCKED_MULT
    max(block_size, MIN_RECOMMEND_BLOCK)
end

# Transpose 8x8 bit array packed into `x`
# The least significant bit of x is the upper left corner of the matrix
# This is hierarchically transposing 2 by 2 block matrixes
# by swapping the corners (a ⊻ b) .⊻ [a, b] == [b, a].
function trans_bit_8x8(x::UInt64)::UInt64
    t = (x ⊻ (x >> 7)) & 0x00AA00AA00AA00AA
    x = x ⊻ t ⊻ (t << 7)
    t = (x ⊻ (x >> 14)) & 0x0000CCCC0000CCCC
    x = x ⊻ t ⊻ (t << 14)
    t = (x ⊻ (x >> 28)) & 0x00000000F0F0F0F0
    x ⊻ t ⊻ (t << 28)
end

function apply_blocks!(block_fun!, in::AbstractVector{UInt8}, out::AbstractVector{UInt8}, elem_size::Int64, _block_size::Int64)::Nothing
    block_size = if iszero(_block_size)
        default_block_size(elem_size)
    else
        _block_size
    end
    in_nbytes::Int64 = length(in)
    @assert in_nbytes ≤ length(out)
    @assert in_nbytes ≥ 0
    @assert block_size > 0
    @assert elem_size > 0
    @assert iszero(mod(block_size, BLOCKED_MULT))
    # split input into blocks of block_size elements and apply `block_fun!` transform.
    # The last block may be smaller, but still must have a size that is a multiple of BLOCKED_MULT (8)
    # The leftover bytes are copied at the end if needed.
    size = fld(in_nbytes, elem_size)
    size_left = size
    while size_left ≥ BLOCKED_MULT
        if size_left < block_size
            block_size = fld(size_left, BLOCKED_MULT) * BLOCKED_MULT
        end
        offset = (size-size_left)*elem_size
        block_fun!(out, offset, in, offset, elem_size, block_size)
        size_left -= block_size
    end
    offset = (size-size_left)*elem_size
    left_over_bytes = in_nbytes - offset
    # here we copy all leftover bytes, not just full elements
    # This is in case https://github.com/kiyo-masui/bitshuffle/issues/3 gets fixed.
    for i in 0:left_over_bytes-1
        out[begin + offset + i] = in[begin + offset + i]
    end
    nothing
end

# Do the bit transpose on a block of `block_size` elements, with
# each element having `elem_size` bytes.
# `block_size` must be a multiple of 8
function trans_bit_elem!(out, out_offset::Int64, in, in_offset::Int64, elem_size::Int64, block_size::Int64)
    # check preconditions
    @assert block_size > 0
    @assert elem_size > 0
    @assert iszero(mod(block_size, 8))
    nbytes, f = Base.Checked.mul_with_overflow(block_size, elem_size)
    @assert !f
    checkbounds(out, firstindex(out) + out_offset)
    checkbounds(in, firstindex(in) + in_offset)
    checkbounds(out, firstindex(out) + out_offset + nbytes - 1)
    checkbounds(in, firstindex(in) + in_offset + nbytes - 1)
    # TODO try: https://mischasan.wordpress.com/2011/07/24/what-is-sse-good-for-transposing-a-bit-matrix/
    # And other SIMD versions from the C library.
    M = fld(block_size, 8)
    for elem_group in 0:M-1
        for byte_in_elem in 0:elem_size-1
            # load the 8 bytes into an UInt64
            local x::UInt64 = 0
            for i in 0:7
                x |= UInt64(in[begin + in_offset + (elem_group*8+i)*elem_size + byte_in_elem])<<(i*8)
            end
            # transpose the bits in x
            x = trans_bit_8x8(x)
            # now write back to the correct spots in out
            for i in 0:7
                out[begin + out_offset + (byte_in_elem*8+i)*M + elem_group] = (x >> (i*8)) % UInt8
            end
        end
    end
end

function untrans_bit_elem!(out, out_offset::Int64, in, in_offset::Int64, elem_size::Int64, block_size::Int64)
    trans_bit_elem!(out, out_offset, in, in_offset, fld(block_size,8), elem_size*8)
end

const bshuf_docs = """
Blocked bitwise shuffle. The element size and block size are required
to be able to decode the shuffle.

This is using the format used by the functions `bshuf_bitshuffle` and `bshuf_bitunshuffle` from https://www.github.com/kiyo-masui/bitshuffle

This is HDF5 filter number 32008 when `cd_values[4]` is 0 for no compression.
"""

"""
    struct BShufCodec <: Codec
    BShufCodec(element_size::Integer, block_size::Integer)

$bshuf_docs

`block_size` can be zero to use an automatic size. `block_size` must be a multiple of 8.

A `BShufCodec` can be used as an encoder or decoder.
"""
struct BShufCodec <: Codec
    element_size::Int64
    block_size::Int64
    function BShufCodec(element_size::Integer, block_size::Integer)
        check_in_range(Int64(1):typemax(Int64); element_size)
        check_in_range(Int64(0):Int64(8):typemax(Int64); block_size)
        new(Int64(element_size), Int64(block_size))
    end
end

decode_options(x::BShufCodec) = BShufDecodeOptions(;codec=x) # default decode options

# Allow BShufCodec to be used as an encoder
decoded_size_range(e::BShufCodec) = Int64(0):e.element_size:typemax(Int64)-1

encode_bound(::BShufCodec, src_size::Int64)::Int64 = src_size

function try_encode!(e::BShufCodec, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    dst_size::Int64 = length(dst)
    src_size::Int64 = length(src)
    element_size = e.element_size
    block_size = e.block_size
    check_in_range(decoded_size_range(e); src_size)
    if dst_size < src_size
        nothing
    else
        apply_blocks!(trans_bit_elem!, src, dst, element_size, block_size)
        return src_size
    end
end

"""
    struct BShufEncodeOptions <: EncodeOptions
    BShufEncodeOptions(; kwargs...)

$bshuf_docs

# Keyword Arguments

- `codec::BShufCodec`
"""
struct BShufEncodeOptions <: EncodeOptions
    codec::BShufCodec
end
function BShufEncodeOptions(;
        codec::BShufCodec,
        kwargs...
    )
    BShufEncodeOptions(codec)
end

is_thread_safe(::BShufEncodeOptions) = true

decoded_size_range(x::BShufEncodeOptions) = decoded_size_range(x.codec)

encode_bound(x::BShufEncodeOptions, src_size::Int64)::Int64 = encode_bound(x.codec, src_size)

function try_encode!(x::BShufEncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    try_encode!(x.codec, dst, src)
end

"""
    struct BShufDecodeOptions <: DecodeOptions
    BShufDecodeOptions(; kwargs...)

$bshuf_docs

# Keyword Arguments

- `codec::BShufCodec`
"""
struct BShufDecodeOptions <: DecodeOptions
    codec::BShufCodec
end
function BShufDecodeOptions(;
        codec::BShufCodec,
        kwargs...
    )
    BShufDecodeOptions(codec)
end

is_thread_safe(::BShufDecodeOptions) = true

function try_find_decoded_size(::BShufDecodeOptions, src::AbstractVector{UInt8})::Int64
    length(src)
end

function try_decode!(d::BShufDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    dst_size::Int64 = length(dst)
    src_size::Int64 = length(src)
    element_size = d.codec.element_size
    block_size = d.codec.block_size
    # Error if src_size isn't a multiple of element_size to match current HDF5 behavior. Ref: https://github.com/kiyo-masui/bitshuffle/issues/3
    if !iszero(mod(src_size, element_size))
        throw(BShufDecodingError("src_size isn't a multiple of element_size"))
    end
    if dst_size < src_size
        nothing
    else
        apply_blocks!(untrans_bit_elem!, src, dst, element_size, block_size)
        return src_size
    end
end

include("compress.jl")

end # module ChunkCodecBitshuffle

#= License file for C library https://www.github.com/kiyo-masui/bitshuffle
Bitshuffle - Filter for improving compression of typed binary data.

Copyright (c) 2014 Kiyoshi Masui (kiyo@physics.ubc.ca)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
=#
