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
- `compressor::AbstractString="lz4"`: The string representing the type of compressor to use.

  For example, "blosclz", "lz4", "lz4hc", "zlib", or "zstd".
  Use `is_compressor_valid` to check if a compressor is supported.
"""
struct BloscEncodeOptions <: EncodeOptions
    codec::BloscCodec
    clevel::Int32
    doshuffle::Int32
    typesize::Int64
    compressor::String
end
function BloscEncodeOptions(;
        codec::BloscCodec=BloscCodec(),
        clevel::Integer=5,
        doshuffle::Integer=1,
        typesize::Integer=1,
        compressor::AbstractString="lz4",
        kwargs...
    )
    _clevel = Int32(clamp(clevel, 0, 9))
    check_in_range(0:2; doshuffle)
    _typesize = if typesize ∈ 2:BLOSC_MAX_TYPESIZE
        Int64(typesize)
    else
        Int64(1)
    end
    is_compressor_valid(compressor) || throw(ArgumentError("is_compressor_valid(compressor) must hold. Got\ncompressor => $(repr(compressor))"))
    BloscEncodeOptions(
        codec,
        _clevel,
        doshuffle,
        _typesize,
        compressor,
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

    blocksize = 0 # automatic blocksize
    numinternalthreads = 1
    sz = ccall((:blosc_compress_ctx, libblosc), Cint,
        (Cint, Cint, Csize_t, Csize_t, Ptr{Cvoid}, Ptr{Cvoid}, Csize_t, Cstring, Csize_t, Cint),
        e.clevel, e.doshuffle, e.typesize, src_size, src, dst, dst_size, e.compressor, blocksize, numinternalthreads
    )
    if sz == 0
        nothing
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
