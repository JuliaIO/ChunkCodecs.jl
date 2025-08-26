const bitshufflecompress_docs = """
Blocked bitwise shuffle with compression applied to each block. The element size and compress codec are required
to be able to decode this.

This is HDF5 filter number 32008 when `cd_values[4]` is set for compression.

`cd_values[4]` with value `2` or `BSHUF_H5_COMPRESS_LZ4` corresponds to `LZ4BlockCodec` from `ChunkCodecLibLz4`.

`cd_values[4]` with value `3` or `BSHUF_H5_COMPRESS_ZSTD` corresponds to `ZstdCodec` from `ChunkCodecLibZstd`.

The element size can be at most `fld(typemax(Int32), 8)`.
"""

"""
    struct BShufLZCodec{C<:Codec} <: Codec
    BShufLZCodec(element_size::Integer, compress::Codec)

$bitshufflecompress_docs

"""
struct BShufLZCodec{C<:Codec} <: Codec
    element_size::Int64
    compress::C
    function BShufLZCodec{C}(element_size::Integer, compress::Codec) where C<:Codec
        check_in_range(Int64(1):fld(typemax(Int32), 8); element_size)
        new{C}(Int64(element_size), convert(C, compress))
    end
end
BShufLZCodec(element_size::Integer, compress::Codec) = BShufLZCodec{typeof(compress)}(element_size, compress)

decode_options(x::BShufLZCodec) = BShufLZDecodeOptions(;codec=x) # default decode options

"""
    struct BShufLZEncodeOptions <: EncodeOptions
    BShufLZEncodeOptions(; kwargs...)

$bitshufflecompress_docs

# Keyword Arguments

- `codec::BShufLZCodec`
- `options::EncodeOptions`: block encoding options.
- `block_size::Integer=0`: Must be a multiple of 8. zero can be used for an automatic block size. This a number of elements not a number of bytes.
"""
struct BShufLZEncodeOptions{C<:Codec, E<:EncodeOptions} <: EncodeOptions
    codec::BShufLZCodec{C}
    options::E
    block_size::Int64
end
function BShufLZEncodeOptions{C, E}(;
        codec::BShufLZCodec,
        options::EncodeOptions,
        block_size::Integer=Int64(0),
        kwargs...
    ) where {C<:Codec, E<:EncodeOptions}
    if !isequal(options.codec, codec.compress)
        throw(ArgumentError("`codec.compress` must match `options.codec`. Got\n`codec.compress` => $(codec.compress)\n`options.codec` => $(options.codec)"))
    end
    check_in_range(Int64(0):Int64(8):Int64(typemax(Int32)); block_size)
    max_block_size = if iszero(block_size)
        default_block_size(codec.element_size)
    else
        Int64(block_size)
    end
    @assert max_block_size ≤ typemax(Int32)
    @assert codec.element_size ≤ typemax(Int32)
    max_block_bytes = max_block_size * codec.element_size
    check_in_range(Int64(0):Int64(typemax(Int32)); max_block_bytes)
    allowed_block_size = decoded_size_range(options)
    if 8*codec.element_size ∉ allowed_block_size
        throw(ArgumentError("`options` not able to encode 8 elements"))
    end
    if max_block_bytes ∉ allowed_block_size
        throw(ArgumentError("`options` not able to encode the max block size: $(max_block_bytes) bytes"))
    end
    if max_block_size > 16 && 16*codec.element_size ∉ allowed_block_size
        throw(ArgumentError("`options` not able to encode 16 elements"))
    end
    max_compressed_block_bytes = encode_bound(options, max_block_bytes)
    if max_compressed_block_bytes > typemax(Int32)
        throw(ArgumentError("`options` not able to encode max block size in `typemax(Int32)` bytes."))
    end
    BShufLZEncodeOptions{C, E}(codec, options, Int64(block_size))
end
function BShufLZEncodeOptions(;
        codec::BShufLZCodec{C},
        options::E,
        kwargs...
    ) where {C<:Codec, E<:EncodeOptions}
    BShufLZEncodeOptions{C, E}(; codec, options, kwargs...)
end

is_thread_safe(e::BShufLZEncodeOptions) = is_thread_safe(e.options)

is_lossless(e::BShufLZEncodeOptions) = is_lossless(e.options)

function decoded_size_range(e::BShufLZEncodeOptions)
    Int64(0):e.codec.element_size:typemax(Int64)-1
end

function encode_bound(e::BShufLZEncodeOptions, src_size::Int64)::Int64
    elem_size = e.codec.element_size
    max_block_size = if iszero(e.block_size)
        default_block_size(elem_size)
    else
        e.block_size
    end
    max_block_bytes = max_block_size * elem_size
    max_compressed_block_bytes = encode_bound(e.options, max_block_bytes) + 4
    n_max_blocks = fld(src_size, max_block_bytes)
    partial_block_bytes = fld(mod(src_size, max_block_bytes), 8*elem_size)*8*elem_size
    max_compressed_partial_block_bytes = encode_bound(e.options, partial_block_bytes) + 4
    bound::Int64 = 12 # HDF5 LZ4 style header
    bound = clamp(widemul(max_compressed_block_bytes, n_max_blocks) + widen(bound), Int64)
    if !iszero(partial_block_bytes)
        bound = clamp(widen(max_compressed_partial_block_bytes) + widen(bound), Int64)
    end
    leftover_bytes = src_size - partial_block_bytes - max_block_bytes*n_max_blocks
    bound = clamp(widen(leftover_bytes) + widen(bound), Int64)
    bound
end

function try_encode!(e::BShufLZEncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::MaybeSize
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)
    if dst_size < 12
        return NOT_SIZE
    end
    elem_size = e.codec.element_size
    # This get used to write to the header
    block_size = if iszero(e.block_size)
        default_block_size(elem_size)
    else
        e.block_size
    end
    src_left::Int64 = src_size
    dst_left::Int64 = dst_size
    @assert iszero(mod(block_size, BLOCKED_MULT))
    # Write header
    store_int64_BE!(dst, Int64(0), src_size)
    @assert !signbit(block_size*elem_size)
    store_int32_BE!(dst, Int64(8), Int32(block_size*elem_size))
    dst_left -= 12
    if iszero(src_size)
        return Int64(12)
    end
    # allocate temp buffer for bitshuffle output
    max_block_size = min(block_size, fld(src_size, BLOCKED_MULT*elem_size) * BLOCKED_MULT)
    tmp_buf_bshuf = Vector{UInt8}(undef, max_block_size*elem_size)
    # split input into blocks of block_size elements and apply the transform.
    # The last block may be smaller, but still must have a size that is a multiple of BLOCKED_MULT (8)
    # The leftover bytes are copied at the end if needed.
    while src_left ≥ BLOCKED_MULT*elem_size
        if dst_left < 4
            return NOT_SIZE # no space for block header
        end
        if src_left < block_size*elem_size
            block_size = fld(src_left, BLOCKED_MULT*elem_size) * BLOCKED_MULT
        end
        src_offset = src_size - src_left
        trans_bit_elem!(tmp_buf_bshuf, Int64(0), src, src_offset, elem_size, block_size)
        maybe_compressed_nbytes = try_encode!(
            e.options,
            @view(dst[end-dst_left+1+4:end]),
            @view(tmp_buf_bshuf[begin:begin+elem_size*block_size-1])
        )::MaybeSize
        if !is_size(maybe_compressed_nbytes)
            return NOT_SIZE # no space for compressed block
        end
        compressed_nbytes = Int64(maybe_compressed_nbytes)
        store_int32_BE!(dst, dst_size - dst_left, Int32(compressed_nbytes))
        src_left -= block_size*elem_size
        dst_left -= 4 + compressed_nbytes
        @assert dst_left ∈ 0:dst_size
        @assert src_left ∈ 0:src_size
    end
    if src_left > dst_left
        return NOT_SIZE # no space for leftover bytes
    end
    src_offset = src_size - src_left
    dst_offset = dst_size - dst_left
    # here we copy all leftover bytes, not just full elements
    # This is in case https://github.com/kiyo-masui/bitshuffle/issues/3 gets fixed.
    for i in 0:src_left-1
        dst[begin + dst_offset + i] = src[begin + src_offset + i]
    end
    dst_left -= src_left
    @assert dst_left ∈ 0:dst_size
    return Int64(dst_size - dst_left)
end

"""
    struct BShufLZDecodeOptions <: DecodeOptions
    BShufLZDecodeOptions(; kwargs...)

$bitshufflecompress_docs

# Keyword Arguments

- `codec::BShufLZCodec`
- `options::DecodeOptions= decode_options(codec.compress)`: block decoding options.
"""
struct BShufLZDecodeOptions{C<:Codec, D<:DecodeOptions} <: DecodeOptions
    codec::BShufLZCodec{C}
    options::D
end
function BShufLZDecodeOptions{C, D}(;
        codec::BShufLZCodec,
        options::DecodeOptions= decode_options(codec.compress),
        kwargs...
    ) where {C<:Codec, D<:DecodeOptions}
    if !isequal(options.codec, codec.compress)
        throw(ArgumentError("`codec.compress` must match `options.codec`. Got\n`codec.compress` => $(codec.compress)\n`options.codec` => $(options.codec)"))
    end
    BShufLZDecodeOptions{C, D}(codec, options)
end
function BShufLZDecodeOptions(;
        codec::BShufLZCodec{C},
        options::D= decode_options(codec.compress),
        kwargs...
    ) where {C<:Codec, D<:DecodeOptions}
    BShufLZDecodeOptions{C, D}(;codec, options, kwargs...)
end

is_thread_safe(d::BShufLZDecodeOptions) = is_thread_safe(d.options)

function try_find_decoded_size(d::BShufLZDecodeOptions, src::AbstractVector{UInt8})::Int64
    if length(src) < 12
        throw(BShufDecodingError("unexpected end of input"))
    else
        decoded_size = load_int64_BE(src, Int64(0))
        if signbit(decoded_size)
            throw(BShufDecodingError("decoded size is negative"))
        elseif !iszero(mod(decoded_size, d.codec.element_size))
            throw(BShufDecodingError("decoded_size isn't a multiple of element_size"))
        else
            decoded_size
        end
    end
end

function try_decode!(d::BShufLZDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::MaybeSize
    check_contiguous(dst)
    check_contiguous(src)
    decoded_size::Int64 = try_find_decoded_size(d, src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    if decoded_size > dst_size
        return NOT_SIZE
    end
    src_left::Int64 = src_size
    dst_left::Int64 = decoded_size
    dst_offset::Int64 = 0
    elem_size = d.codec.element_size
    @assert src_left ≥ 12 # this is checked by try_find_decoded_size
    read_block_nbytes = load_int32_BE(src, Int64(8))
    src_left -= 12
    if read_block_nbytes < 0
        throw(BShufDecodingError("block size must not be negative"))
    end
    # Try and match C library handling of parsing the block_size
    block_size = fld(read_block_nbytes, elem_size)
    if iszero(block_size)
        block_size = default_block_size(elem_size)
    end
    if !iszero(mod(block_size, BLOCKED_MULT))
        throw(BShufDecodingError("block size must be a multiple of 8"))
    end
    # allocate temp buffer for decoding output
    max_block_size = min(block_size, fld(decoded_size, BLOCKED_MULT*elem_size) * BLOCKED_MULT)
    tmp_buf_decode = Vector{UInt8}(undef, max_block_size*elem_size)
    # split input into blocks of block_size elements and apply the transform.
    # The last block may be smaller, but still must have a size that is a multiple of BLOCKED_MULT (8)
    # The leftover bytes are copied at the end if needed.
    while dst_left ≥ BLOCKED_MULT*elem_size
        if dst_left < block_size*elem_size
            block_size = fld(dst_left, BLOCKED_MULT*elem_size) * BLOCKED_MULT
        end
        if src_left < 4
            throw(BShufDecodingError("unexpected end of input"))
        end
        local c_size = load_int32_BE(src, src_size - src_left)
        src_left -= 4
        if c_size < 0
            throw(BShufDecodingError("block compressed size must not be negative"))
        end
        if src_left < c_size
            throw(BShufDecodingError("unexpected end of input"))
        end
        local ret = try_decode!(
            d.options,
            @view(tmp_buf_decode[begin:begin+block_size*elem_size-1]),
            @view(src[end-src_left+1:end-src_left+c_size])
        )::MaybeSize
        src_left -= c_size
        if ret.val != block_size*elem_size
            throw(BShufDecodingError("saved decoded size is not correct"))
        end
        untrans_bit_elem!(dst, dst_offset, tmp_buf_decode, Int64(0), elem_size, block_size)
        dst_left -= block_size*elem_size
        dst_offset += block_size*elem_size
    end
    # Now try to copy the rest of the leftover bytes
    if src_left < dst_left
        throw(BShufDecodingError("unexpected end of input"))
    elseif src_left > dst_left
        throw(BShufDecodingError("unexpected $(src_left-dst_left) bytes after stream"))
    else
        src_offset = src_size - src_left
        for i in 0:dst_left-1
            dst[begin + dst_offset + i] = src[begin + src_offset + i]
        end
    end
    return decoded_size
end
