"""
    struct Blosc2EncodeOptions <: EncodeOptions
    Blosc2EncodeOptions(; kwargs...)

Blosc2 compression using c-blosc2 library: https://github.com/Blosc2/c-blosc2

# Keyword Arguments

- `codec::Blosc2Codec=Blosc2Codec()`
- `clevel::Integer=5`: The compression level, between 0 (no compression) and 9 (maximum compression)
- `doshuffle::Integer=1`: Whether to use the shuffle filter.

  0 means not applying it, 1 means applying it at a byte level,
  and 2 means at a bit level (slower but may achieve better entropy alignment).
- `typesize::Integer=1`: The element size to use when shuffling.

  For implementation reasons, only `typesize` in `1:$(BLOSC_MAX_TYPESIZE)` will allow the
  shuffle filter to work.  When `typesize` is not in this range, shuffle
  will be silently disabled.
- `compressor::AbstractString="lz4"`: The string representing the type of compressor to use.

  For example, "blosclz", "lz4", "lz4hc", "zlib", or "zstd".
  Use `is_compressor_valid` to check if a compressor is supported.
"""
struct Blosc2EncodeOptions <: EncodeOptions
    codec::Blosc2Codec
    clevel::Int32
    doshuffle::Int32
    typesize::Int64
    chunksize::Int64
    compressor::String
end
function Blosc2EncodeOptions(;
                             codec::Blosc2Codec=Blosc2Codec(),
                             clevel::Integer=5,
                             doshuffle::Integer=1,
                             typesize::Integer=1,
                             chunksize::Integer=Int64(1024)^3, # 1 GByte
                             compressor::AbstractString="lz4",
                             kwargs...)
    _clevel = Int32(clamp(clevel, 0, 9))
    check_in_range(0:2; doshuffle)
    _typesize = if typesize ∈ 2:BLOSC_MAX_TYPESIZE
        Int64(typesize)
    else
        Int64(1)
    end
    _chunksize = Int64(clamp(chunksize, 1024, Int64(1024)^3)) # 1 GByte
    is_compressor_valid(compressor) ||
        throw(ArgumentError("is_compressor_valid(compressor) must hold. Got\ncompressor => $(repr(compressor))"))
    return Blosc2EncodeOptions(codec, _clevel, doshuffle, _typesize, _chunksize, compressor)
end

# The maximum overhead for the schunk
const MAX_SCHUNK_OVERHEAD = 172 # apparently undocumented -- just a guess

# We just punt with the upper bound. typemax(Int64) is a huge number anyway.
decoded_size_range(e::Blosc2EncodeOptions) = Int64(0):Int64(e.typesize):(typemax(Int64) ÷ 2)

function encode_bound(e::Blosc2EncodeOptions, src_size::Int64)::Int64
    return clamp(widen(src_size) + cld(src_size, e.chunksize) * BLOSC2_MAX_OVERHEAD + MAX_SCHUNK_OVERHEAD, Int64)
end

function try_encode!(e::Blosc2EncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8};
                     kwargs...)::Union{Nothing,Int64}
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)

    ccode = compcode(e.compressor)
    @assert ccode >= 0
    numinternalthreads = 1

    # Create a super-chunk container
    cparams = Blosc2CParams()
    @reset cparams.typesize = e.typesize
    @reset cparams.compcode = ccode
    @reset cparams.clevel = e.clevel
    @reset cparams.nthreads = numinternalthreads
    @reset cparams.filters[BLOSC2_MAX_FILTERS] = e.doshuffle
    cparams_obj = [cparams]

    dparams = Blosc2DParams()
    @reset dparams.nthreads = numinternalthreads
    dparams_obj = [dparams]

    io = Blosc2IO()
    io_obj = [io]

    storage = Blosc2Storage()
    @reset storage.cparams = pointer(cparams_obj)
    @reset storage.dparams = pointer(dparams_obj)
    @reset storage.io = pointer(io_obj)
    storage_obj = [storage]

    there_was_an_error = false

    GC.@preserve cparams_obj dparams_obj io_obj storage_obj begin
        schunk = @ccall libblosc2.blosc2_schunk_new(storage_obj::Ptr{Blosc2Storage})::Ptr{Blosc2SChunk}
        @assert schunk != Ptr{Blosc2Storage}()

        # Break input into chunks
        for pos in 1:e.chunksize:src_size
            endpos = min(src_size, pos + e.chunksize - 1)
            srcview = @view src[pos:endpos]
            nbytes = length(srcview)
            nchunks = @ccall libblosc2.blosc2_schunk_append_buffer(schunk::Ptr{Blosc2SChunk}, srcview::Ptr{Cvoid},
                                                                   nbytes::Int32)::Int64
            @assert nchunks >= 0
            @assert nchunks == (pos-1) ÷ e.chunksize + 1
        end

        cframe = Ref{Ptr{UInt8}}()
        needs_free = Ref{UInt8}()   # bool
        compressed_size = @ccall libblosc2.blosc2_schunk_to_buffer(schunk::Ptr{Blosc2SChunk}, cframe::Ref{Ptr{UInt8}},
                                                                   needs_free::Ref{UInt8})::Int64
        @assert compressed_size >= 0
        cframe = cframe[]
        needs_free = Bool(needs_free[])

        if compressed_size <= length(dst)
            # TODO: Encode directly into `dst`
            unsafe_copyto!(pointer(dst), cframe, compressed_size)
        else
            # Insufficient space to stored compressed data.
            # We should detect this earlier, already in the loop above.
            there_was_an_error = true
        end

        success = @ccall libblosc2.blosc2_schunk_free(schunk::Ptr{Blosc2SChunk})::Cint
        @assert success == 0

        if needs_free
            Libc.free(cframe)
        end
    end

    if there_was_an_error
        return nothing
    end

    return compressed_size::Int64
end
