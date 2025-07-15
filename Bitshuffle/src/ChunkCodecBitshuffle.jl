# Code ported from the libbitshuffle C library <https://github.com/kiyo-masui/bitshuffle>
# There is a copy of the C library's license at the end of this file.
module ChunkCodecBitshuffle

# constants
const MIN_RECOMMEND_BLOCK = Int64(128)
const BLOCKED_MULT = Int64(8)
const TARGET_BLOCK_SIZE_B = Int64(8192)

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
# The most significant bit of x is the upper left corner of the matrix
function trans_bit_8x8(x::UInt64)::UInt64
    t = (x ⊻ (x >> 7)) & 0x00AA00AA00AA00AA
    x = x ⊻ t ⊻ (t << 7)
    t = (x ⊻ (x >> 14)) & 0x0000CCCC0000CCCC
    x = x ⊻ t ⊻ (t << 14)
    t = (x ⊻ (x >> 28)) & 0x00000000F0F0F0F0
    x ⊻ t ⊻ (t << 28)
end

# # Transpose 8x8 bit array along the diagonal from upper right to lower left
# # The most significant bit of x is the upper left corner of the matrix
# function trans_bit_8x8_be(x::UInt64)::UInt64
#     t = (x ⊻ (x >> 9)) & 0x0055005500550055
#     x = x ⊻ t ⊻ (t << 9)
#     t = (x ⊻ (x >> 18)) & 0x0000333300003333
#     x = x ⊻ t ⊻ (t << 18)
#     t = (x ⊻ (x >> 36)) & 0x000000000F0F0F0F
#     x ⊻ t ⊻ (t << 36)
# end

function bitshuffle(in::AbstractVector{UInt8}, out::AbstractVector{UInt8}, elem_size::Int64, block_size::Int64)::Nothing
    in_nbytes::Int64 = length(in)
    out_nbytes::Int64 = length(out)
    @assert in_nbytes == out_nbytes
    @assert in_nbytes ≥ 0
    @assert iszero(mod(in_nbytes, elem_size))
    @assert block_size > 0
    @assert elem_size > 0
    @assert iszero(mod(block_size, BLOCKED_MULT))
    # split input into blocks of block_size elements
    # The last block may be smaller, but still must have a size that is a multiple of BLOCKED_MULT (8)
    # The leftover 0 to 7 elements are copied at the end if needed.
    size = fld(in_nbytes, elem_size)
    size_left = size
    while size_left ≥ BLOCKED_MULT
        if size_left < block_size
            block_size = fld(size_left, BLOCKED_MULT) * BLOCKED_MULT
        end
        offset = (size-size_left)*elem_size
        trans_bit_elem!(out, offset, in, offset, block_size, elem_size)
        size_left -= block_size
    end
    offset = (size-size_left)*elem_size
    for i in 0:(size_left*elem_size-1)
        out[begin + offset + i] = in[begin + offset + i]
    end
    nothing
end

# Do the bit transpose on a block of `block_size` elements, with
# each element having `elem_size` bytes.
# `block_size` must be a multiple of 8
function trans_bit_elem!(out, out_offset::Int64, in, in_offset::Int64, block_size::Int64, elem_size::Int64)
    # check preconditions
    @assert block_size > 0
    @assert elem_size > 0
    @assert iszero(mod(block_size, 8))
    nbytes, f = Checked.mul_with_overflow(block_size, elem_size)
    @assert !f
    checkbounds(out, firstindex(out) + out_offset)
    checkbounds(in, firstindex(in) + in_offset)
    checkbounds(out, firstindex(out) + out_offset + nbytes - 1)
    checkbounds(in, firstindex(in) + in_offset + nbytes - 1)
    # This is not the fastest way to do this, and differs significantly from
    # what is done in the C library.
    M = fld(block_size, 8)
    for elem_group in 0:M-1
        for byte_in_elem in 0:elem_size-1
            # load the 8 bytes into an UInt64
            x = htol(reinterpret(UInt64, ntuple(8) do i
                in[begin + in_offset + (elem_group*8+i-1)*elem_size + byte_in_elem]
            end))
            # transpose the bits in x
            x = trans_bit_8x8(x)
            # now write back to the correct spots in out
            for i in 1:8
                out[begin + out_offset + (byte_in_elem*8+i-1)*M + elem_group] = (x >> (64-i*8)) % UInt8
            end
        end
    end
end


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