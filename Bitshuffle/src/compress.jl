const bitshufflecompress_docs = """
Blocked bitwise shuffle with compression applied to each block. The element size and compress codec are required
to be able to decode this.

This is HDF5 filter number 32008 when `cd_values[4]` is set for compression.

`cd_values[4]` with value `2` or `BSHUF_H5_COMPRESS_LZ4` corresponds to `LZ4BlockCodec` from `ChunkCodecLibLz4`.

`cd_values[4]` with value `3` or `BSHUF_H5_COMPRESS_ZSTD` corresponds to `ZstdCodec` from `ChunkCodecLibZstd`.
"""

"""
    struct BitshuffleCompressCodec{C<:Codec} <: Codec
    BitshuffleCompressCodec(element_size::Integer, compress::Codec)

$bitshufflecompress_docs

"""
struct BitshuffleCompressCodec{C<:Codec} <: Codec
    element_size::Int64
    compress::C
    function BitshuffleCompressCodec{C}(element_size::Integer, compress::Codec) where C<:Codec
        check_in_range(Int64(1):fld(typemax(Int32),8); element_size)
        new{C}(Int64(element_size), convert(C, compress))
    end
end
BitshuffleCompressCodec(element_size::Integer, compress::Codec) = BitshuffleCompressCodec{typeof(compress)}(element_size, compress)

decode_options(x::BitshuffleCompressCodec) = BitshuffleCompressOptions(;codec=x) # default decode options

"""
    struct BitshuffleCompressEncodeOptions <: EncodeOptions
    BitshuffleCompressEncodeOptions(; kwargs...)

$bitshufflecompress_docs

# Keyword Arguments

- `codec::BitshuffleCompressCodec`
- `options::EncodeOptions`: block encoding options.
- `block_size::Integer=0`: Must be a multiple of 8. zero can be used for an automatic block size.
"""
struct BitshuffleCompressEncodeOptions{C<:Codec, E<:EncodeOptions} <: EncodeOptions
    codec::BitshuffleCompressCodec{C}
    options::E
    block_size::Int64
end
function BitshuffleCompressEncodeOptions(;
        codec::BitshuffleCompressCodec{C},
        options::E,
        block_size::Integer=Int64(0),
        kwargs...
    ) where {C, E<:EncodeOptions}
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
    BitshuffleCompressEncodeOptions{C, E}(codec, options, Int64(block_size))
end

is_thread_safe(e::BitshuffleCompressEncodeOptions) = is_thread_safe(e.options)

is_lossless(e::BitshuffleCompressEncodeOptions) = is_lossless(e.options)

# TODO relax this is if https://github.com/kiyo-masui/bitshuffle/issues/3 gets fixed.
function decoded_size_range(e::BitshuffleCompressEncodeOptions)
    Int64(0):e.codec.element_size:typemax(Int64)-1
end

function encode_bound(e::BitshuffleCompressEncodeOptions, src_size::Int64)::Int64
    max_block_size = if iszero(e.block_size)
        default_block_size(e.codec.element_size)
    else
        e.block_size
    end
    max_block_bytes = max_block_size * codec.element_size
    max_compressed_block_bytes = encode_bound(options, max_block_bytes) + 4
    n_max_blocks = fld(src_size, max_block_bytes)
    partial_block_bytes = fld(mod(src_size, max_block_bytes), 8*codec.element_size)*8*codec.element_size
    max_compressed_leftover_block_bytes = encode_bound(options, partial_block_bytes) + 4
    bound::Int64 = 12 # HDF5 LZ4 style header
    bound = clamp(widemul(max_compressed_block_bytes, n_max_blocks) + widen(bound), Int64)
    if !iszero(leftover_block_bytes)
        bound = clamp(widen(max_compressed_leftover_block_bytes) + widen(bound), Int64)
    end
    leftover_bytes = src_size - partial_block_bytes - max_block_bytes*n_max_blocks
    bound = clamp(widen(leftover_bytes) + widen(bound), Int64)
    bound
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
function load_int32_BE!(src, offset)::Int32
    val = Int32(0)
    for i in 0:3
        val |= Int32(src[begin+offset+i])<<(3*8 - i*8)
    end
    val
end
function load_int64_BE!(src, offset)::Int64
    val = Int64(0)
    for i in 0:7
        val |= Int64(src[begin+offset+i])<<(7*8 - i*8)
    end
    val
end

function try_encode!(e::BitshuffleCompressEncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)
    if dst_size < 12
        return nothing
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
    store_int64_BE!(dst, 0, src_size)
    @assert !signbit(block_size*elem_size)
    store_int32_BE!(dst, 8, Int32(block_size*elem_size))
    dst_left -= 12
    if iszero(src_size)
        return Int64(12)
    end
    # allocate temp buffer for bitshuffle output
    max_block_size = min(block_size, fld(src_size, BLOCKED_MULT*elem_size) * BLOCKED_MULT)
    tmp_buf_bshuf = Vector{UInt8}(undef, max_block_size)
    # split input into blocks of block_size elements and apply the transform.
    # The last block may be smaller, but still must have a size that is a multiple of BLOCKED_MULT (8)
    # The leftover bytes are copied at the end if needed.
    while src_left ≥ BLOCKED_MULT*elem_size
        if dst_left < 4
            return nothing # no space for block header
        end
        if src_left < block_size*elem_size
            block_size = fld(src_left, BLOCKED_MULT*elem_size) * BLOCKED_MULT
        end
        src_offset = src_size - src_left
        trans_bit_elem!(tmp_buf_bshuf, Int64(0), src, src_offset, elem_size, block_size)
        compressed_nbytes = try_encode!(e.options, @view(dst[end-dst_left+1+4:end]), tmp_buf_bshuf)
        if isnothing(compressed_nbytes)
            return nothing # no space for compressed block
        end
        @assert !signbit(compressed_nbytes)
        store_int32_BE!(dst, dst_size-dst_left, Int32(compressed_nbytes))
        src_left -= block_size*elem_size
        dst_left -= 4+compressed_nbytes
        @assert dst_left ∈ 0:dst_size
        @assert src_left ∈ 0:src_size
    end
    if src_left > dst_left
        return nothing # no space for leftover bytes
    end
    src_offset = src_size - src_left
    dst_offset = dst_size - dst_left
    # here we copy all leftover bytes, not just full elements
    # This is incase https://github.com/kiyo-masui/bitshuffle/issues/3 gets fixed.
    for i in 0:src_left-1
        dst[begin + dst_offset + i] = src[begin + src_offset + i]
    end
    dst_left -= src_left
    @assert dst_left ∈ 0:dst_size
    return Int64(dst_size - dst_left)
end
