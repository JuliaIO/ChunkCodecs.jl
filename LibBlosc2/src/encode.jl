"""
    struct Blosc2EncodeOptions <: EncodeOptions
    Blosc2EncodeOptions(; kwargs...)

Blosc2 compression using c-blosc2 library: https://github.com/Blosc2/c-blosc2

# Keyword Arguments

- `codec::Blosc2Codec=Blosc2Codec()`
- `doshuffle::Union{Integer,Symbol,AbstractString}=1`: Whether to use the shuffle filter.

  Possible values are
  - `:noshuffle`, `"noshuffle"`, 0: do not shuffle
  - `:shuffle`, `"shuffle"`, 1: shuffle bytes
  - `:bitshuffle`, `"bitshuffle"`, 2: shuffle bits (slower but compresses better)
- `dodelta::Union{Integer,Symbol,AbstractString}=1`: Whether to use the delta filter.

  Possible values are
  - `:nofilter`, `"nofilter"`, 0: no filter
  - `:delta`, `"delta"`, 1: use delta filter
- `typesize::Integer=8`: The element size to use when shuffling.

  `typesize` must be in the range `1:$(BLOSC_MAX_TYPESIZE)`.
- `clevel::Integer=5`: The compression level, between 0 (no compression) and 9 (maximum compression)
- `compressor::AbstractString="blosclz"`: The string representing the type of compressor to use.

  For example, `"blosclz"`, `"lz4"`, `"lz4hc"`, `"zlib"`, or `"zstd"`.
  Use `is_compressor_valid` to check if a compressor is supported.
- `blocksize::Integer=0`: Length of block in bytes (0 for automatic choice)
- `nthreads::Integer=1`: The number of threads to use
- `splitmode::Union{Integer,Symbol,AbstractString}=4: Whether blocks should be split or not

  Possible values are
  - `:always`, `"always"`, 1
  - `:never`, `"never"`, 2
  - `:auto`, `"auto"`, 3
  - `:forward_compat`, `"forward_compat"`, 4: default setting
- `chunksize::Integer=1024^3`: Chunk size for very large inputs
"""
struct Blosc2EncodeOptions <: EncodeOptions
    codec::Blosc2Codec

    doshuffle::Int              # :noshuffle, :shuffle, :bitshuffle
    dodelta::Int                # :nofilter, :delta
    typesize::Int
    clevel::Int
    compressor::String
    blocksize::Int
    nthreads::Int
    splitmode::Int              # :always, :never, :auto, :forward_compat

    chunksize::Int64
end
function Blosc2EncodeOptions(;
                             codec::Blosc2Codec=Blosc2Codec(),
                             doshuffle::Union{Integer,Symbol,AbstractString}=1,
                             dodelta::Union{Integer,Symbol,AbstractString}=0,
                             typesize::Integer=8,
                             clevel::Integer=5,
                             compressor::Union{Symbol,AbstractString}=:blosclz,
                             blocksize::Integer=0,
                             nthreads::Integer=1,
                             splitmode::Union{Integer,Symbol,AbstractString}=4,
                             chunksize::Integer=Int64(1024)^3, # 1 GByte
                             kwargs...)
    _doshuffle = doshuffle
    if _doshuffle isa AbstractString
        _doshuffle = Symbol(lowercase(_doshuffle))
    end
    if _doshuffle isa Symbol
        _doshuffle = get(Dict(:noshuffle => 0,
                              :shuffle => 1,
                              :bitshuffle => 2), _doshuffle, -1)
        _doshuffle >= 0 ||
            throw(ArgumentError("Unknown `doshuffle` value `$(repr(doshuffle))`"))
    end
    _doshuffle::Integer
    check_in_range(0:2; doshuffle=_doshuffle)

    _dodelta = dodelta
    if _dodelta isa AbstractString
        _dodelta = Symbol(lowercase(_dodelta))
    end
    if _dodelta isa Symbol
        _dodelta = get(Dict(:nofilter => 0,
                            :delta => 1), _dodelta, -1)
        _dodelta >= 0 ||
            throw(ArgumentError("Unknown `dodelta` value `$(repr(dodelta))`"))
    end
    _dodelta::Integer
    check_in_range(0:1; dodelta=_dodelta)

    _typesize = typesize
    if _typesize ∉ 1:BLOSC_MAX_TYPESIZE
        _typesize = 8           # use default
    end

    _clevel = clamp(clevel, 0:9)

    _compressor = compressor
    if _compressor isa Symbol
        _compressor = string(_compressor)
    end
    is_compressor_valid(_compressor) ||
        throw(ArgumentError("is_compressor_valid(compressor) must hold. Got\ncompressor => $(repr(compressor))"))

    _blocksize = blocksize
    check_in_range(0:typemax(Int32); blocksize=_blocksize)

    _nthreads=nthreads
    check_in_range(1:typemax(Int32); nthreads=_nthreads)

    _splitmode = splitmode
    if _splitmode isa AbstractString
        _splitmode = Symbol(lowercase(_splitmode))
    end
    if _splitmode isa Symbol
        _splitmode = get(Dict(:always => 1,
                              :never => 2,
                              :auto => 3,
                              :forward_compat => 4), _splitmode, -1)
        _splitmode >= 0 ||
            throw(ArgumentError("Unknown `splitmode` value `$(repr(splitmode))`"))
    end
    _splitmode::Integer
    check_in_range(1:4; splitmode=_splitmode)

    _chunksize = clamp(chunksize, 1024, Int64(1024)^3) # at least 1 kByte, at most 1 GByte

    return Blosc2EncodeOptions(codec,
                               _doshuffle, _dodelta, _typesize, _clevel, _compressor, _blocksize, _nthreads, _splitmode, _chunksize)
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

    blosc2_init()

    ccode = compcode(e.compressor)
    @assert ccode >= 0

    # Create a super-chunk container
    cparams = Blosc2CParams()
    @reset cparams.typesize = e.typesize
    @reset cparams.compcode = ccode
    @reset cparams.clevel = e.clevel
    @reset cparams.nthreads = e.nthreads
    @reset cparams.blocksize = e.blocksize
    @reset cparams.splitmode = e.splitmode
    @reset cparams.filters[BLOSC2_MAX_FILTERS] = e.doshuffle
    if e.dodelta > 0
        @reset cparams.filters[BLOSC2_MAX_FILTERS-1] = e.dodelta
    end
    cparams_obj = [cparams]

    io = Blosc2IO()
    io_obj = [io]

    storage = Blosc2Storage()
    @reset storage.cparams = pointer(cparams_obj)
    @reset storage.io = pointer(io_obj)
    storage_obj = [storage]

    there_was_an_error = false

    GC.@preserve cparams_obj io_obj storage_obj begin
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
            # We should try to encode directly into `dst`. (This may
            # not be possible with the Blosc2 API.)
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
