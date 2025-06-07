"""
    SzipDecodingError(msg)

Error for data that cannot be decoded.
"""
struct SzipDecodingError <: DecodingError
    msg::String
end

function Base.showerror(io::IO, err::SzipDecodingError)
    print(io, "SzipDecodingError: ")
    print(io, err.msg)
    nothing
end

"""
    struct SzipHDF5DecodeOptions <: DecodeOptions
    SzipHDF5DecodeOptions(; kwargs...)

$(sziphdf5_docs)

# Keyword Arguments

- `codec::SzipHDF5Codec`
"""
struct SzipHDF5DecodeOptions <: DecodeOptions
    codec::SzipHDF5Codec
end
function SzipHDF5DecodeOptions(;
        codec::SzipHDF5Codec,
        kwargs...
    )
    SzipHDF5DecodeOptions(codec)
end

function try_find_decoded_size(::SzipHDF5DecodeOptions, src::AbstractVector{UInt8})::Int64
    if length(src) < 4
        throw(SzipDecodingError("unexpected end of input"))
    else
        decoded_size = UInt32(0)
        for i in 0:3
            decoded_size |= UInt32(src[begin+i])<<(i*8)
        end
        Int64(decoded_size)
    end
end

function try_decode!(d::SzipHDF5DecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    decoded_size = try_find_decoded_size(d, src)
    @assert !isnothing(decoded_size)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    if decoded_size > dst_size
        nothing
    else
        cconv_src = Base.cconvert(Ptr{UInt8}, src)
        cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
        sz_param = SZ_com_t(d.codec.options_mask, d.codec.bits_per_pixel, d.codec.pixels_per_block, d.codec.pixels_per_scanline)
        ret = GC.@preserve cconv_src cconv_dst begin
            src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src) + 4
            dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
            sourceLen = src_size - 4
            destLen = Ref(Csize_t(decoded_size))
            @ccall libsz.SZ_BufftoBuffDecompress(
                dst_p::Ptr{UInt8}, # dest
                destLen::Ref{Csize_t}, # destLen
                src_p::Ptr{UInt8}, # source
                sourceLen::Csize_t, # sourceLen
                sz_param::Ref{SZ_com_t}
            )::Cint
        end
        if ret == SZ_OK
            if destLen[] != decoded_size
                throw(SzipDecodingError("saved decoded size is not correct"))
            end
            return Int64(decoded_size)
        elseif ret == SZ_MEM_ERROR
            throw(OutOfMemoryError())
        elseif ret == SZ_PARAM_ERROR
            throw(ArgumentError("invalid szip parameters"))
        else
            throw(SzipDecodingError("unknown szip error code: $(ret)"))
        end
    end
end
