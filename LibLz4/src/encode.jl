"""
    struct LZ4FrameEncodeOptions <: EncodeOptions
    LZ4FrameEncodeOptions(; kwargs...)

lz4 frame compression using liblz4: https://lz4.org/

This is the LZ4 Frame (.lz4) format described in https://github.com/lz4/lz4/blob/v1.10.0/doc/lz4_Frame_format.md

This format is compatible with the `lz4` CLI.

# Keyword Arguments

- `codec::LZ4FrameCodec=LZ4FrameCodec()`
- `compressionLevel::Integer=0`: Compression level, 0: default (fast mode); values > $(LZ4_MAX_CLEVEL) count as $(LZ4_MAX_CLEVEL); values < 0 trigger fast acceleration.
- `blockSizeID::Integer=0`: 0: default (max64KB), 4: max64KB, 5: max256KB, 6: max1MB, 7: max4MB;

  The larger the block size, the (slightly) better the compression ratio,
  though there are diminishing returns.
  Larger blocks also increase memory usage on both compression and decompression sides.
- `blockMode::Bool=false`: false: blockLinked, true: blockIndependent;

  Linked blocks sharply reduce inefficiencies when using small blocks, they compress better.
  However, some LZ4 decoders are only compatible with independent blocks.
- `contentChecksumFlag::Bool=false`: A 32-bits checksum of content is written at end of frame.
- `contentSize::Bool=false`: Save size of uncompressed content ; false == unknown.

  If the content size is zero, it will not be saved, even if this option is true due to a
  limitation in liblz4. Ref: https://github.com/lz4/lz4/issues/775
- `blockChecksumFlag::Bool=false`: each block followed by a checksum of block's compressed data.
- `favorDecSpeed::Bool=false`: if true, parser favors decompression speed vs compression ratio. Only works for high compressionLevel (>= LZ4HC_CLEVEL_OPT_MIN)
"""
struct LZ4FrameEncodeOptions <: EncodeOptions
    codec::LZ4FrameCodec
    compressionLevel::Int32
    blockSizeID::Int32
    blockMode::Bool
    contentChecksumFlag::Bool
    contentSize::Bool
    blockChecksumFlag::Bool
    favorDecSpeed::Bool
end
function LZ4FrameEncodeOptions(;
        codec::LZ4FrameCodec=LZ4FrameCodec(),
        compressionLevel::Integer=0,
        blockSizeID::Integer=0,
        blockMode::Bool=false,
        contentChecksumFlag::Bool=false,
        contentSize::Bool=false,
        blockChecksumFlag::Bool=false,
        favorDecSpeed::Bool=false,
        kwargs...
    )
    blockSizeID ∈ (0, 4, 5, 6, 7) || throw(ArgumentError("blockSizeID: $(blockSizeID) must be in (0, 4, 5, 6, 7)"))
    _clamped_compression_level = clamp(compressionLevel, LZ4_MIN_CLEVEL, LZ4_MAX_CLEVEL)
    LZ4FrameEncodeOptions(codec, _clamped_compression_level, blockSizeID, blockMode, contentChecksumFlag, contentSize, blockChecksumFlag, favorDecSpeed)
end

is_thread_safe(::LZ4FrameEncodeOptions) = true

function _preferences(e::LZ4FrameEncodeOptions)::LZ4F_preferences_t
    LZ4F_preferences_t(
        LZ4F_frameInfo_t(
            LZ4F_blockSizeID_t(e.blockSizeID),
            LZ4F_blockMode_t(e.blockMode),
            LZ4F_contentChecksum_t(e.contentChecksumFlag),
            LZ4F_frame,
            Culonglong(e.contentSize), # https://github.com/lz4/lz4/blob/6cf42afbea04c9ea6a704523aead273715001330/lib/lz4frame.c#L446 auto-correct content size if selected (!=0)
            Cuint(0), # no dictID provided
            LZ4F_blockChecksum_t(e.blockChecksumFlag),
        ),
        e.compressionLevel,
        Cuint(0), # autoFlush, this just gets overwritten anyway at https://github.com/lz4/lz4/blob/6cf42afbea04c9ea6a704523aead273715001330/lib/lz4frame.c#L449
        Cuint(e.favorDecSpeed),
        (Cuint(0), Cuint(0), Cuint(0)), # reserved, must be zero
    )
end

function decoded_size_range(::LZ4FrameEncodeOptions)
    # prevent overflow of encode_bound
    # This should be very conservative
    max_size = if sizeof(Csize_t) == 8
        Int64(2)^47 - Int64(2)
    elseif sizeof(Csize_t) == 4
        Int64(2)^31 - Int64(2)
    else
        @assert false "unreachable"
    end
    Int64(0):Int64(1):max_size
end

function encode_bound(e::LZ4FrameEncodeOptions, src_size::Int64)::Int64
    if src_size < 0
        Int64(-1)
    elseif src_size > last(decoded_size_range(e))
        typemax(Int64)
    else
        LZ4F_compressFrameBound(Csize_t(src_size), _preferences(e))
    end
end

function try_encode!(e::LZ4FrameEncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)
    # LZ4F_compressFrame needs this to hold.
    if dst_size < encode_bound(e, src_size)
        return nothing
    end
    ret = LZ4F_compressFrame(dst, src, _preferences(e))
    if LZ4F_isError(ret)
        error("unexpected LZ4F error: $(LZ4F_getErrorName(ret))")
    else
        Int64(ret)
    end
end

"""
    struct LZ4BlockEncodeOptions <: EncodeOptions
    LZ4BlockEncodeOptions(; kwargs...)

lz4 block compression using liblz4: https://lz4.org/

This is the LZ4 Block format described in https://github.com/lz4/lz4/blob/v1.10.0/doc/lz4_Block_format.md

This format has no framing layer and is NOT compatible with the `lz4` CLI.

There is also a maximum decoded size of about 2 GB for this implementation.

# Keyword Arguments

- `codec::LZ4BlockCodec=LZ4BlockCodec()`
- `compressionLevel::Integer=0`: Compression level, 0: default (fast mode); values > $(LZ4_MAX_CLEVEL) count as $(LZ4_MAX_CLEVEL); values < 0 trigger fast acceleration.
"""
struct LZ4BlockEncodeOptions <: EncodeOptions
    codec::LZ4BlockCodec
    compressionLevel::Int32
end
function LZ4BlockEncodeOptions(;
        codec::LZ4BlockCodec=LZ4BlockCodec(),
        compressionLevel::Integer=0,
        kwargs...
    )
    _clamped_compression_level = clamp(compressionLevel, LZ4_MIN_CLEVEL, LZ4_MAX_CLEVEL)
    LZ4BlockEncodeOptions(codec, _clamped_compression_level)
end

is_thread_safe(::LZ4BlockEncodeOptions) = true

decoded_size_range(::LZ4BlockEncodeOptions) = Int64(0):Int64(1):LZ4_MAX_INPUT_SIZE

function encode_bound(::LZ4BlockEncodeOptions, src_size::Int64)::Int64
    if src_size > LZ4_MAX_INPUT_SIZE
        typemax(Int64)
    else
        unsafe_lz4_compressbound(src_size)
    end
end

function try_encode!(e::LZ4BlockEncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)
    if dst_size < 1
        return nothing
    end
    # src_size must fit in an Int32 because it is in decoded_size_range(e)
    src_size32 = Int32(src_size)
    cconv_src = Base.cconvert(Ptr{UInt8}, src)
    cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
    ret = GC.@preserve cconv_src cconv_dst begin
        src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
        dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
        unsafe_lz4_compress(src_p, dst_p, src_size32, clamp(dst_size, Int32), e.compressionLevel)
    end
    if iszero(ret)
        nothing
    else
        Int64(ret)
    end
end

"""
    struct LZ4NumcodecsEncodeOptions <: EncodeOptions
    LZ4NumcodecsEncodeOptions(; kwargs...)

lz4 numcodecs style compression using liblz4: https://lz4.org/

This is the [`LZ4BlockCodec`](@ref) format with a 4-byte header containing the
size of the decoded data as a little-endian 32-bit signed integer.

This format is documented in https://numcodecs.readthedocs.io/en/stable/compression/lz4.html

This format is NOT compatible with the `lz4` CLI.

There is also a maximum decoded size of about 2 GB for this implementation.

# Keyword Arguments

- `codec::LZ4NumcodecsCodec=LZ4NumcodecsCodec()`
- `compressionLevel::Integer=0`: Compression level, 0: default (fast mode); values > $(LZ4_MAX_CLEVEL) count as $(LZ4_MAX_CLEVEL); values < 0 trigger fast acceleration.
"""
struct LZ4NumcodecsEncodeOptions <: EncodeOptions
    codec::LZ4NumcodecsCodec
    compressionLevel::Int32
end
function LZ4NumcodecsEncodeOptions(;
        codec::LZ4NumcodecsCodec=LZ4NumcodecsCodec(),
        compressionLevel::Integer=0,
        kwargs...
    )
    _clamped_compression_level = clamp(compressionLevel, LZ4_MIN_CLEVEL, LZ4_MAX_CLEVEL)
    LZ4NumcodecsEncodeOptions(codec, _clamped_compression_level)
end

is_thread_safe(::LZ4NumcodecsEncodeOptions) = true

decoded_size_range(::LZ4NumcodecsEncodeOptions) = Int64(0):Int64(1):LZ4_MAX_INPUT_SIZE

function encode_bound(::LZ4NumcodecsEncodeOptions, src_size::Int64)::Int64
    if src_size > LZ4_MAX_INPUT_SIZE
        typemax(Int64)
    else
        unsafe_lz4_compressbound(src_size) + Int64(4)
    end
end

function try_encode!(e::LZ4NumcodecsEncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)
    if dst_size < 5
        return nothing
    end
    # src_size must fit in an Int32 because it is in decoded_size_range(e)
    src_size32 = Int32(src_size)
    cconv_src = Base.cconvert(Ptr{UInt8}, src)
    cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
    ret = GC.@preserve cconv_src cconv_dst begin
        src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
        dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
        for i in 0:3
            unsafe_store!(dst_p+i, (src_size32>>>(i*8))%UInt8)
        end
        dst_size -= 4
        dst_p += 4
        unsafe_lz4_compress(src_p, dst_p, src_size32, clamp(dst_size, Int32), e.compressionLevel)
    end
    if iszero(ret)
        nothing
    else
        Int64(ret) + Int64(4)
    end
end


"""
    struct LZ4HDF5EncodeOptions <: EncodeOptions
    LZ4HDF5EncodeOptions(; kwargs...)

LZ4 HDF5 format compression using liblz4: https://lz4.org/

This is the LZ4 HDF5 format used in HDF5 Filter ID: 32004.

This format is documented in https://github.com/HDFGroup/hdf5_plugins

This format is NOT compatible with the `lz4` CLI.

# Keyword Arguments

- `codec::LZ4HDF5Codec=LZ4HDF5Codec()`
- `compressionLevel::Integer=0`: Compression level, 0: default (fast mode); values > $(LZ4_MAX_CLEVEL) count as $(LZ4_MAX_CLEVEL); values < 0 trigger fast acceleration.
- `blockSize::Integer=2^30`: Decompressed bytes per block. Must be in `1:$(LZ4_MAX_INPUT_SIZE)`.
"""
struct LZ4HDF5EncodeOptions <: EncodeOptions
    codec::LZ4HDF5Codec
    compressionLevel::Int32
    blockSize::Int32
end
function LZ4HDF5EncodeOptions(;
        codec::LZ4HDF5Codec=LZ4HDF5Codec(),
        compressionLevel::Integer=0,
        blockSize::Integer=2^30,
        kwargs...
    )
    check_in_range(1:LZ4_MAX_INPUT_SIZE; blockSize)
    _clamped_compression_level = clamp(compressionLevel, LZ4_MIN_CLEVEL, LZ4_MAX_CLEVEL)
    LZ4HDF5EncodeOptions(codec, _clamped_compression_level, blockSize)
end

is_thread_safe(::LZ4HDF5EncodeOptions) = true

# Prevent encode_bound reaching typemax(Int64) if blockSize is 1
decoded_size_range(e::LZ4HDF5EncodeOptions) = Int64(0):Int64(1):Int64(1844674407370955155)

function encode_bound(e::LZ4HDF5EncodeOptions, src_size::Int64)::Int64
    if src_size > last(decoded_size_range(e))
        typemax(Int64)
    else
        block_size = clamp(src_size, Int64(1), Int64(e.blockSize))
        nblocks = cld(src_size, block_size)
        lz4_scratch_space = block_size÷Int64(255) + Int64(16)
        src_size + Int64(4)*nblocks + lz4_scratch_space + Int64(12)
    end
end

function try_encode!(e::LZ4HDF5EncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)
    block_size = clamp(src_size, Int64(1), Int64(e.blockSize))
    if dst_size < 12
        return nothing
    end
    cconv_src = Base.cconvert(Ptr{UInt8}, src)
    cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
    GC.@preserve cconv_src cconv_dst begin
        src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
        dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
        src_left = src_size
        dst_left = dst_size
        # Store original size as big endian signed 64 bit
        for i in 0:7
            unsafe_store!(dst_p+i, (src_size>>>((7-i)*8))%UInt8)
        end
        dst_left -= 8
        dst_p += 8
        # Store block size as big endian signed 32 bit
        for i in 0:3
            unsafe_store!(dst_p+i, (block_size>>>((3-i)*8))%UInt8)
        end
        dst_left -= 4
        dst_p += 4
        while src_left > 0
            if dst_left < 5
                return nothing
            end
            local b_size = min(src_left, block_size)%Int32
            @assert !iszero(b_size)
            local c_size_p = dst_p
            dst_left -= 4
            dst_p += 4
            local ret = unsafe_lz4_compress(src_p, dst_p, b_size, clamp(dst_left, Int32), e.compressionLevel)
            # Store the data directly if there was no compression
            # iszero(ret) indicates that dst_left was too small for compression.
            # but it might be large enough for a copy.
            local c_size = if ret ≥ b_size || iszero(ret)
                if dst_left < b_size
                    return nothing
                end
                @static if VERSION ≥ v"1.10"
                    Libc.memcpy(dst_p, src_p, b_size)
                else
                    unsafe_copyto!(dst_p, src_p, b_size)
                end
                b_size
            else
                ret
            end
            # Store block compressed size as big endian signed 32 bit
            for i in 0:3
                unsafe_store!(c_size_p+i, (c_size>>>((3-i)*8))%UInt8)
            end
            dst_left -= c_size
            dst_p += c_size
            src_left -= b_size
            src_p += b_size
        end
        return dst_size - dst_left
    end
end
