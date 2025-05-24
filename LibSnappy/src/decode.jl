"""
    SnappyDecodingError(code)

Error for data that cannot be decoded.
"""
struct SnappyDecodingError <: DecodingError
    code::Cint
end

function Base.showerror(io::IO, err::SnappyDecodingError)
    print(io, "SnappyDecodingError: snappy compressed buffer cannot be decoded, error code: ")
    print(io, err.code)
    nothing
end

"""
    struct SnappyDecodeOptions <: DecodeOptions
    SnappyDecodeOptions(; kwargs...)

Snappy decompression using the snappy C++ library: https://github.com/google/snappy

# Keyword Arguments

- `codec::SnappyCodec=SnappyCodec()`
"""
struct SnappyDecodeOptions <: DecodeOptions
    codec::SnappyCodec
end
function SnappyDecodeOptions(;
        codec::SnappyCodec=SnappyCodec(),
        kwargs...
    )
    SnappyDecodeOptions(codec)
end

function try_find_decoded_size(::SnappyDecodeOptions, src::AbstractVector{UInt8})::Int64
    check_contiguous(src)
    nbytes = Ref(Csize_t(0))
    ret = ccall((:snappy_uncompressed_length, libsnappy), Cint,
        (Ptr{Cvoid}, Csize_t, Ref{Csize_t}),
        src, length(src), nbytes
    )
    if ret == SNAPPY_OK && nbytes[] ≤ typemax(Int64)
        # success, it is safe to decompress
        Int64(nbytes[])
    else
        # it is not safe to decompress. throw an error
        throw(SnappyDecodingError(ret))
    end
end

function try_decode!(d::SnappyDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    dst_size::Int64 = length(dst)
    src_size::Int64 = length(src)
    nbytes = try_find_decoded_size(d, src)
    if dst_size < nbytes
        nothing
    else
        uncompressed_length = Ref(Csize_t(nbytes))
        status = ccall((:snappy_uncompress, libsnappy), Cint,
            (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Ref{Csize_t}),
            src, src_size, dst, uncompressed_length,
        )
        if status == SNAPPY_OK && uncompressed_length[] == nbytes
            nbytes
        else
            throw(SnappyDecodingError(status))
        end
    end
end
