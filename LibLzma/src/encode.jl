"""
    struct XZEncodeOptions <: EncodeOptions
    XZEncodeOptions(; kwargs...)

xz compression using the liblzma C library <https://tukaani.org/xz/>

# Keyword Arguments

- `codec::XZCodec=XZCodec()`
- `preset::UInt32=UInt32(6)`: Compression preset to use.

  A preset consist of level
  number and zero or more flags. Usually flags aren't
  used, so preset is simply a number [0, 9] which match
  the options -0 ... -9 of the xz command line tool.
  Additional flags can be set using bitwise-or with
  the preset level number, e.g. `UInt32(6) | LZMA_PRESET_EXTREME`.
- `check::Int32=LZMA_CHECK_CRC64`: Integrity check type to use.

  Available checks are `LZMA_CHECK_NONE`, `LZMA_CHECK_CRC32`, `LZMA_CHECK_CRC64`, and `LZMA_CHECK_SHA256`
"""
struct XZEncodeOptions <: EncodeOptions
    codec::XZCodec
    preset::UInt32
    check::Int32
end

function XZEncodeOptions(;
        codec::XZCodec=XZCodec(),
        preset::UInt32=UInt32(6),
        check::Int32=LZMA_CHECK_CRC64,
        kwargs...
    )
    check_in_range(UInt32(0):LZMA_CHECK_ID_MAX; check)
    XZEncodeOptions(
        codec,
        preset,
        check,
    )
end

function decoded_size_range(::XZEncodeOptions)
    max_size = if sizeof(Csize_t) == 8
        typemax(Int64)-Int64(1)
    elseif sizeof(Csize_t) == 4
        Int64(typemax(Csize_t))
    else
        @assert false "unreachable"
    end
    Int64(0):Int64(1):max_size
end

function encode_bound(::XZEncodeOptions, src_size::Int64)::Int64
    if src_size < 0
        Int64(-1)
    elseif src_size > typemax(Csize_t)
        typemax(Int64)
    else
        res = @ccall liblzma.lzma_stream_buffer_bound(src_size::Csize_t)::Csize_t
        if iszero(res)
            typemax(Int64)
        else
            clamp(res, Int64)
        end
    end
end

function try_encode!(e::XZEncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::MaybeSize
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)
    if iszero(dst_size)
        return NOT_SIZE
    end
    out_pos = Ref(Csize_t(0))
    ret = @ccall liblzma.lzma_easy_buffer_encode(
        e.preset::UInt32, e.check::Cint,
        default_allocator()::Ref{lzma_allocator},
        src::Ptr{UInt8}, src_size::Csize_t,
        dst::Ptr{UInt8}, out_pos::Ref{Csize_t}, dst_size::Csize_t
    )::Cint
    if ret == LZMA_OK
        # Encoding was successful.
        return Int64(out_pos[])
    elseif ret == LZMA_BUF_ERROR
        # Not enough output buffer space.
        return NOT_SIZE
    elseif ret == LZMA_UNSUPPORTED_CHECK
        throw(ArgumentError("Specified integrity check: $(e.check) is not supported"))
    elseif ret == LZMA_OPTIONS_ERROR
        throw(ArgumentError("Specified preset: $(e.preset) is not supported"))
    elseif ret == LZMA_MEM_ERROR
        throw(OutOfMemoryError())
    elseif ret == LZMA_DATA_ERROR
        # This is usually unreachable since the limits are near 2^63 bytes
        throw(ArgumentError("File size limits exceeded"))
    else
        error("Unknown lzma error code: $(ret)")
    end
end
