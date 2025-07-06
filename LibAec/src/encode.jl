# Allow SzipHDF5Codec to be used as an encoder

function pixel_byte_size(bits_per_pixel::Int32)::Int64
    if bits_per_pixel ≤ 8
        1
    elseif bits_per_pixel ≤ 16
        2
    elseif bits_per_pixel ≤ 32
        4
    else
        8
    end
end

function decoded_size_range(x::SzipHDF5Codec)
    Int64(0):pixel_byte_size(x.bits_per_pixel):Int64(typemax(UInt32))
end

function encode_bound(x::SzipHDF5Codec, src_size::Int64)::Int64
    if src_size < 0
        return Int64(-1)
    elseif src_size > typemax(UInt32)
        return typemax(Int64)
    end
    blocks_per_scanline = Int64(cld(x.pixels_per_scanline, x.pixels_per_block))
    bits_per_pixel = if x.bits_per_pixel == 32 || x.bits_per_pixel == 64
        Int32(8)
    else
        x.bits_per_pixel
    end
    bytes_per_pixel = pixel_byte_size(bits_per_pixel)
    n_pixels = fld(src_size, bytes_per_pixel)
    n_scanlines = cld(n_pixels, Int64(x.pixels_per_scanline))
    n_blocks = blocks_per_scanline * n_scanlines
    # overhead from https://ccsds.org/Pubs/121x0b3.pdf Table 5-1
    block_overhead = if bits_per_pixel ≤ 8
        3
    elseif bits_per_pixel ≤ 16
        4
    elseif bits_per_pixel ≤ 32
        5
    else
        throw(ArgumentError("invalid bits_per_pixel"))
    end
    max_bits_per_block = Int64(x.pixels_per_block) * bits_per_pixel + block_overhead
    max_output_bits = max_bits_per_block * n_blocks
    return cld(max_output_bits, 8) + 4
end

function try_encode!(e::SzipHDF5Codec, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)
    if dst_size < 4
        return nothing
    end
    cconv_src = Base.cconvert(Ptr{UInt8}, src)
    cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
    sz_param = SZ_com_t(e.options_mask, e.bits_per_pixel, e.pixels_per_block, e.pixels_per_scanline)
    ret = GC.@preserve cconv_src cconv_dst begin
        src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
        dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
        # src_size must fit in an UInt32 because it is in decoded_size_range(e)
        src_size32 = UInt32(src_size)
        for i in 0:3
            unsafe_store!(dst_p+i, (src_size32>>>(i*8))%UInt8)
        end
        if iszero(src_size)
            # Handle the special case of empty input.
            return Int64(4)
        end
        dst_size -= 4
        dst_p += 4
        destLen = Ref(Csize_t(dst_size))
        @ccall libsz.SZ_BufftoBuffCompress(
            dst_p::Ptr{UInt8}, # dest
            destLen::Ref{Csize_t}, # destLen
            src_p::Ptr{UInt8}, # source
            src_size::Csize_t, # sourceLen
            sz_param::Ref{SZ_com_t}
        )::Cint
    end
    if ret == SZ_OK
        @assert destLen[] ≤ dst_size
        Int64(destLen[]) + Int64(4)
    elseif ret == SZ_MEM_ERROR
        throw(OutOfMemoryError())
    elseif ret == SZ_OUTBUFF_FULL
        return nothing
    elseif ret == SZ_PARAM_ERROR
        throw(ArgumentError("invalid szip parameters"))
    else
        error("unknown szip error code: $(ret)")
    end
end

"""
    struct SzipHDF5EncodeOptions <: EncodeOptions
    SzipHDF5EncodeOptions(; kwargs...)

$(sziphdf5_docs)

# Keyword Arguments

- `codec::SzipHDF5Codec`
"""
struct SzipHDF5EncodeOptions <: EncodeOptions
    codec::SzipHDF5Codec
end
function SzipHDF5EncodeOptions(;
        codec::SzipHDF5Codec,
        kwargs...
    )
    SzipHDF5EncodeOptions(
        codec,
    )
end

function ChunkCodecCore.is_lossless(x::SzipHDF5Codec)
    x.bits_per_pixel ∈ (8, 16, 32, 64)
end
ChunkCodecCore.is_lossless(e::SzipHDF5EncodeOptions) = ChunkCodecCore.is_lossless(e.codec)

decoded_size_range(e::SzipHDF5EncodeOptions) = decoded_size_range(e.codec)

encode_bound(e::SzipHDF5EncodeOptions, src_size::Int64)::Int64 = encode_bound(e.codec, src_size)

function try_encode!(e::SzipHDF5EncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    try_encode!(e.codec, dst, src)
end
