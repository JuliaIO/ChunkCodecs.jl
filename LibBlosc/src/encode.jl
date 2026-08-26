"""
    struct BloscEncodeOptions <: EncodeOptions
    BloscEncodeOptions(; kwargs...)

Blosc compression using c-blosc library: https://github.com/Blosc/c-blosc

# Keyword Arguments

- `codec::BloscCodec=BloscCodec()`
- `clevel::Integer=5`: The compression level, between 0 (no compression) and 9 (maximum compression)
- `doshuffle::Integer=1`: Whether to use the shuffle filter.

  0 means not applying it, 1 means applying it at a byte level,
  and 2 means at a bit level (slower but may achieve better entropy alignment).
- `typesize::Integer=1`: The element size to use when shuffling.

  For implementation reasons, only `typesize` in `1:$(BLOSC_MAX_TYPESIZE)` will allow the
  shuffle filter to work.  When `typesize` is not in this range, shuffle
  will be silently disabled.
- `compcode::Union{Nothing, Integer}=nothing`: The integer code of the compressor to use.

  The available options are:
  `BLOSC_BLOSCLZ`, `BLOSC_LZ4`, `BLOSC_LZ4HC`, `BLOSC_ZLIB`, `BLOSC_ZSTD`

- `compressor::Union{Nothing, String}=nothing`: The string representing the type of compressor to use.

  For example, "blosclz", "lz4", "lz4hc", "zlib", or "zstd".
  Use `is_compressor_valid` to check if a compressor is supported.

  Setting both `compcode` and `compressor` throws an `ArgumentError`.
  If neither is set, the `BLOSC_LZ4` compressor is used.
"""
struct BloscEncodeOptions <: EncodeOptions
    codec::BloscCodec
    clevel::Int32
    doshuffle::Int32
    typesize::Int64
    compcode::Int32
end
function BloscEncodeOptions(;
        codec::BloscCodec=BloscCodec(),
        clevel::Integer=5,
        doshuffle::Integer=1,
        typesize::Integer=1,
        compcode::Union{Nothing, Integer}=nothing,
        compressor::Union{Nothing, String}=nothing,
        kwargs...
    )
    _clevel = Int32(clamp(clevel, 0, 9))
    check_in_range(0:2; doshuffle)
    _typesize = if typesize ∈ 2:BLOSC_MAX_TYPESIZE
        Int64(typesize)
    else
        Int64(1)
    end
    _compcode = if isnothing(compressor)
        if isnothing(compcode)
            BLOSC_LZ4
        else
            check_in_range((BLOSC_BLOSCLZ, BLOSC_LZ4, BLOSC_LZ4HC, BLOSC_ZLIB, BLOSC_ZSTD); compcode)
            Int32(compcode)
        end
    elseif isnothing(compcode)
        ChunkCodecLibBlosc.compcode(compressor)
    else
        throw(ArgumentError("compcode and compressor cannot both be set. Got\ncompcode => $(compcode)\ncompressor => $(repr(compressor))"))
    end::Int32
    BloscEncodeOptions(
        codec,
        _clevel,
        doshuffle,
        _typesize,
        _compcode,
    )
end

# TODO update this when segfault is fixed upstream.
decoded_size_range(e::BloscEncodeOptions) = Int64(0):Int64(e.typesize):Int64(2)^30

function encode_bound(::BloscEncodeOptions, src_size::Int64)::Int64
    clamp(widen(src_size) + widen(BLOSC_MAX_OVERHEAD), Int64)
end

function try_encode!(e::BloscEncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::MaybeSize
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)

    # Clamp dst_size to avoid overflow bug
    # TODO Remove this when this is fixed upstream
    # https://github.com/Blosc/c-blosc/pull/390
    if dst_size - BLOSC_MAX_OVERHEAD > src_size
        dst_size = src_size + BLOSC_MAX_OVERHEAD
    end

    blocksize = Csize_t(0) # automatic blocksize
    numinternalthreads = Cint(1)
    sz = @ccall libblosc.blosc_compress_ctx(
        e.clevel::Cint,
        e.doshuffle::Cint,
        e.typesize::Csize_t,
        src_size::Csize_t,
        src::Ptr{Cvoid},
        dst::Ptr{Cvoid},
        dst_size::Csize_t,
        compname(e.compcode)::Cstring,
        blocksize::Csize_t,
        numinternalthreads::Cint,
    )::Cint
    if sz == 0
        NOT_SIZE
    elseif sz < 0
        error("Internal Blosc error: $(sz). This
            should never happen.  If you see this, please report it back
            together with the buffer data causing this and compression settings.
            $(e)
        ")
    else
        @assert sz ∈ 0:dst_size
        Int64(sz)
    end
end
