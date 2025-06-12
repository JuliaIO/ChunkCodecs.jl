"""
    Blosc2DecodingError()

Error for data that cannot be decoded.
"""
struct Blosc2DecodingError <: DecodingError
end

function Base.showerror(io::IO, err::Blosc2DecodingError)
    print(io, "Blosc2DecodingError: blosc2 compressed buffer cannot be decoded")
    return nothing
end

"""
    struct Blosc2DecodeOptions <: DecodeOptions
    Blosc2DecodeOptions(; kwargs...)

Blosc2 decompression using c-blosc2 library: https://github.com/Blosc/c-blosc2

# Keyword Arguments

- `codec::Blosc2Codec=Blosc2Codec()`

# Keyword Arguments

- `codec::Blosc2Codec=Blosc2Codec()`
- `nthreads::Integer=1`: The number of threads to use
"""
struct Blosc2DecodeOptions <: DecodeOptions
    codec::Blosc2Codec

    nthreads::Int
end
function Blosc2DecodeOptions(; codec::Blosc2Codec=Blosc2Codec(),
                             nthreads::Integer=1,
                             kwargs...)
    _nthreads = nthreads
    check_in_range(1:typemax(Int32); nthreads=_nthreads)

    return Blosc2DecodeOptions(codec, _nthreads)
end

function try_find_decoded_size(::Blosc2DecodeOptions, src::AbstractVector{UInt8})::Int64
    check_contiguous(src)

    blosc2_init()

    copy_cframe = false
    schunk = @ccall libblosc2.blosc2_schunk_from_buffer(src::Ptr{UInt8}, length(src)::Int64, copy_cframe::UInt8)::Ptr{Blosc2SChunk}
    if schunk == Ptr{Blosc2Storage}()
        # These are not a valid blosc2-encoded data
        throw(Blosc2DecodingError())
    end
    @ccall libblosc2.blosc2_schunk_avoid_cframe_free(schunk::Ptr{Blosc2SChunk}, true::UInt8)::Cvoid

    total_nbytes = unsafe_load(schunk).nbytes

    success = @ccall libblosc2.blosc2_schunk_free(schunk::Ptr{Cvoid})::Cint
    @assert success == 0

    return total_nbytes::Int64
end

# Note: We should implement `try_resize_decode!`

function try_decode!(d::Blosc2DecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8};
                     kwargs...)::Union{Nothing,Int64}
    check_contiguous(dst)
    check_contiguous(src)

    blosc2_init()

    # I don't think there is a way to specify a decompression context.
    # That means that our `Blosc2DecodeOptions` will be unused.
    # We could try writing to the `dctx` field in the `schunk`.

    copy_cframe = false
    schunk = @ccall libblosc2.blosc2_schunk_from_buffer(src::Ptr{UInt8}, length(src)::Int64, copy_cframe::UInt8)::Ptr{Blosc2SChunk}
    if schunk == Ptr{Blosc2Storage}()
        # These are not a valid blosc2-encoded data
        throw(Blosc2DecodingError())
    end
    @ccall libblosc2.blosc2_schunk_avoid_cframe_free(schunk::Ptr{Blosc2SChunk}, true::UInt8)::Cvoid

    total_nbytes = unsafe_load(schunk).nbytes
    if total_nbytes > length(dst)
        # There is not enough space to decode the data
        success = @ccall libblosc2.blosc2_schunk_free(schunk::Ptr{Cvoid})::Cint
        @assert success == 0

        return nothing
    end

    dst_position = Int64(0)

    nchunks = unsafe_load(schunk).nchunks
    for nchunk in 0:(nchunks - 1)
        nbytes_left = clamp(total_nbytes - dst_position, Int32)
        nbytes = @ccall libblosc2.blosc2_schunk_decompress_chunk(schunk::Ptr{Blosc2SChunk}, nchunk::Int64,
                                                                 pointer(dst, dst_position+1)::Ptr{Cvoid}, nbytes_left::Int32)::Cint
        @assert nbytes > 0

        dst_position += nbytes
    end
    @assert dst_position == total_nbytes

    success = @ccall libblosc2.blosc2_schunk_free(schunk::Ptr{Cvoid})::Cint
    @assert success == 0

    return total_nbytes::Int64
end
