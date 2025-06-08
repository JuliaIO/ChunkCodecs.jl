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
"""
struct Blosc2DecodeOptions <: DecodeOptions
    codec::Blosc2Codec
end
Blosc2DecodeOptions(; codec::Blosc2Codec=Blosc2Codec(), kwargs...) = Blosc2DecodeOptions(codec)

function try_find_decoded_size(::Blosc2DecodeOptions, src::AbstractVector{UInt8})::Int64
    check_contiguous(src)

    copy_cframe = false
    schunk = @ccall libblosc2.blosc2_schunk_from_buffer(src::Ptr{UInt8}, length(src)::Int64, copy_cframe::UInt8)::Ptr{Blosc2SChunk}
    if schunk == Ptr{Blosc2Storage}()
        # These are not a valid blosc2-encoded data
        throw(Blosc2DecodingError())
    end
    @ccall libblosc2.blosc2_schunk_avoid_cframe_free(schunk::Ptr{Blosc2SChunk}, true::UInt8)::Cvoid

    total_nbytes = Int64(0)

    nchunks = unsafe_load(schunk).nchunks
    for nchunk in 0:(nchunks - 1)
        cbuffer = Ref{Ptr{UInt8}}()
        needs_free = Ref{UInt8}()
        chunksize = @ccall libblosc2.blosc2_schunk_get_chunk(schunk::Ptr{Blosc2SChunk}, nchunk::Int64, cbuffer::Ref{Ptr{UInt8}},
                                                             needs_free::Ref{UInt8})::Cint
        @assert chunksize > 0
        cbuffer = cbuffer[]
        needs_free = Bool(needs_free[])

        nbytes = Ref{Int32}()
        success = @ccall libblosc2.blosc1_cbuffer_validate(cbuffer::Ptr{Cvoid}, chunksize::Cint, nbytes::Ref{Cint})::Cint
        @assert success == 0
        nbytes = nbytes[]

        total_nbytes += nbytes

        if needs_free
            # We could provide buffer into which to decode instead, reusing that buffer
            Libc.free(cbuffer)
        end
    end

    # TODO: Use this instead of the loop above
    @assert unsafe_load(schunk).nbytes == total_nbytes

    success = @ccall libblosc2.blosc2_schunk_free(schunk::Ptr{Cvoid})::Cint
    @assert success == 0

    return total_nbytes::Int64
end

#TODO: implement `try_resize_decode!`

function try_decode!(d::Blosc2DecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8};
                     kwargs...)::Union{Nothing,Int64}
    check_contiguous(dst)
    check_contiguous(src)

    schunk = @ccall libblosc2.blosc2_schunk_from_buffer(src::Ptr{UInt8}, length(src)::Int64, false::UInt8)::Ptr{Blosc2SChunk}
    @assert schunk != Ptr{Blosc2Storage}()
    @ccall libblosc2.blosc2_schunk_avoid_cframe_free(schunk::Ptr{Blosc2SChunk}, true::UInt8)::Cvoid

    there_was_an_error = false
    total_nbytes = Int64(0)

    nchunks = unsafe_load(schunk).nchunks
    for nchunk in 0:(nchunks - 1)
        cbuffer = Ref{Ptr{UInt8}}()
        needs_free = Ref{UInt8}()
        chunksize = @ccall libblosc2.blosc2_schunk_get_chunk(schunk::Ptr{Blosc2SChunk}, nchunk::Int64, cbuffer::Ref{Ptr{UInt8}},
                                                             needs_free::Ref{UInt8})::Cint
        @assert chunksize > 0
        cbuffer = cbuffer[]
        needs_free = Bool(needs_free[])

        nbytes = Ref{Int32}()
        success = @ccall libblosc2.blosc1_cbuffer_validate(cbuffer::Ptr{Cvoid}, chunksize::Cint, nbytes::Ref{Cint})::Cint
        @assert success == 0
        nbytes = nbytes[]

        if needs_free
            Libc.free(cbuffer)
        end

        # TODO: Use this instead of checking each chunk
        # overall uncompressed size: unsafe_load(schunk).nbytes
        # this chunk uncompressed size: nbytes

        if total_nbytes + nbytes > length(dst)
            there_was_an_error = true
            break
        end

        @assert total_nbytes + nbytes <= length(dst)
        nbytes′ = @ccall libblosc2.blosc2_schunk_decompress_chunk(schunk::Ptr{Blosc2SChunk}, nchunk::Int64,
                                                                  pointer(dst, total_nbytes+1)::Ptr{Cvoid}, nbytes::Int32)::Cint
        @assert nbytes′ >= 0
        @assert nbytes′ == nbytes

        total_nbytes += nbytes
    end

    success = @ccall libblosc2.blosc2_schunk_free(schunk::Ptr{Cvoid})::Cint
    @assert success == 0

    if there_was_an_error
        return nothing
    end

    return total_nbytes::Int64
end
