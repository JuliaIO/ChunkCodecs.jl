"""
    BloscDecodingError(code)

Error for data that cannot be decoded.
"""
struct BloscDecodingError <: DecodingError
    code::Cint
end

function Base.showerror(io::IO, err::BloscDecodingError)
    print(io, "BloscDecodingError: blosc compressed buffer cannot be decoded, error code: ")
    print(io, err.code)
    nothing
end

"""
    struct BloscDecodeOptions <: DecodeOptions
    BloscDecodeOptions(; kwargs...)

Blosc decompression using c-blosc library: https://github.com/Blosc/c-blosc

# Keyword Arguments

- `codec::BloscCodec=BloscCodec()`
"""
struct BloscDecodeOptions <: DecodeOptions
    codec::BloscCodec
end
function BloscDecodeOptions(;
        codec::BloscCodec=BloscCodec(),
        kwargs...
    )
    BloscDecodeOptions(codec)
end

function try_find_decoded_size(::BloscDecodeOptions, src::AbstractVector{UInt8})::MaybeSize
    check_contiguous(src)
    nbytes = Ref(Csize_t(0))
    ret = ccall((:blosc_cbuffer_validate, libblosc), Cint,
        (Ptr{Cvoid}, Csize_t, Ref{Csize_t}),
        src, length(src), nbytes
    )
    if iszero(ret) && nbytes[] ≤ typemax(Int64)
        # success, it is safe to decompress
        Int64(nbytes[])
    else
        # it is not safe to decompress. throw an error
        throw(BloscDecodingError(ret))
    end
end

function try_decode!(d::BloscDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::MaybeSize
    check_contiguous(dst)
    check_contiguous(src)
    # This makes sure it is safe to decompress.
    nbytes::Int64 = try_find_decoded_size(d, src)
    dst_size::Int64 = length(dst)
    if nbytes > dst_size
        nothing
    else
        numinternalthreads = 1
        sz = ccall((:blosc_decompress_ctx, libblosc), Cint,
            (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t, Cint),
            src, dst, dst_size, numinternalthreads
        )
        if sz == nbytes
            nbytes
        else
            throw(BloscDecodingError(sz))
        end
    end
end
