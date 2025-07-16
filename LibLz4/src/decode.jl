"""
    LZ4DecodingError(msg)

Error for data that cannot be decoded.
"""
struct LZ4DecodingError <: DecodingError
    msg::String
end

function Base.showerror(io::IO, err::LZ4DecodingError)
    print(io, "LZ4DecodingError: ")
    print(io, err.msg)
    nothing
end

"""
    struct LZ4FrameDecodeOptions <: DecodeOptions
    LZ4FrameDecodeOptions(; kwargs...)

lz4 frame decompression using liblz4: https://lz4.org/

This is the LZ4 Frame (.lz4) format described in https://github.com/lz4/lz4/blob/v1.10.0/doc/lz4_Frame_format.md

This format is compatible with the `lz4` CLI.

Decoding will succeed even if the decompressed size is unknown.
Decoding accepts concatenated frames 
and will error if there is invalid data appended.

# Keyword Arguments

- `codec::LZ4FrameCodec=LZ4FrameCodec()`
"""
struct LZ4FrameDecodeOptions <: DecodeOptions
    codec::LZ4FrameCodec
end
function LZ4FrameDecodeOptions(;
        codec::LZ4FrameCodec=LZ4FrameCodec(),
        kwargs...
    )
    LZ4FrameDecodeOptions(codec)
end

is_thread_safe(::LZ4FrameDecodeOptions) = true

function try_find_decoded_size(::LZ4FrameDecodeOptions, src::AbstractVector{UInt8})::Nothing
    # TODO This might be possible to do using a method similar to ZstdDecodeOptions
    # For now just return nothing
    nothing
end

function try_decode!(d::LZ4FrameDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    try_resize_decode!(d, dst, src, Int64(length(dst)))
end

function try_resize_decode!(d::LZ4FrameDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}, max_size::Int64; kwargs...)::Union{Nothing, Int64}
    dst_size::Int64 = length(dst)
    src_size::Int64 = length(src)
    src_left::Int64 = src_size
    dst_left::Int64 = dst_size
    check_contiguous(dst)
    check_contiguous(src)
    cconv_src = Base.cconvert(Ptr{UInt8}, src)
    # This outer loop is to decode a concatenation of multiple compressed frames.
    while true
        dctx = LZ4F_createDecompressionContext()
        try
            while true
                # dst may get resized, so cconvert needs to be redone on each iteration.
                cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
                GC.@preserve cconv_src cconv_dst begin
                    src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
                    dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
                    start_avail_in = Csize_t(src_left)
                    start_avail_out = Csize_t(dst_left)
                    srcSizePtr = Ref(start_avail_in)
                    dstSizePtr = Ref(start_avail_out)
                    next_in = src_p + (src_size - src_left)
                    next_out = dst_p + (dst_size - dst_left)
                    # TODO maybe it is safe to set stableDst in LZ4F_decompressOptions_t
                    ret = ccall(
                        (:LZ4F_decompress, liblz4),
                        Csize_t,
                        (Ptr{LZ4F_dctx}, Ptr{UInt8}, Ref{Csize_t}, Ptr{UInt8}, Ref{Csize_t}, Ptr{LZ4F_decompressOptions_t}),
                        dctx, next_out, dstSizePtr, next_in, srcSizePtr, C_NULL,
                    )
                    if !LZ4F_isError(ret)
                        @assert srcSizePtr[] ≤ start_avail_in
                        @assert dstSizePtr[] ≤ start_avail_out
                        Δin = Int64(srcSizePtr[])
                        Δout = Int64(dstSizePtr[])
                        dst_left -= Δout
                        src_left -= Δin
                        @assert src_left ∈ 0:src_size
                        @assert dst_left ∈ 0:dst_size
                        if iszero(ret)
                            # Frame is fully decoded!!!!
                            if iszero(src_left)
                                # yay done return decompressed size
                                real_dst_size = dst_size - dst_left
                                @assert real_dst_size ∈ 0:length(dst)
                                return real_dst_size
                            else
                                # try and decompress next frame
                                # there must be progress
                                @assert Δin > 0 || Δout > 0
                                break
                            end
                        else
                            if iszero(dst_left) # needs more output
                                local next_size = @something grow_dst!(dst, max_size) return nothing
                                dst_left += next_size - dst_size
                                dst_size = next_size
                                @assert dst_left > 0
                            else # needs more input
                                if iszero(src_left)
                                    throw(LZ4DecodingError("unexpected end of stream"))
                                end
                                # there must be progress
                                @assert Δin > 0 || Δout > 0
                            end
                        end
                    else
                        throw(LZ4DecodingError(LZ4F_getErrorName(ret)))
                    end
                end
            end
        finally
            LZ4F_freeDecompressionContext(dctx)
        end
    end
end


"""
    struct LZ4BlockDecodeOptions <: DecodeOptions
    LZ4BlockDecodeOptions(; kwargs...)

lz4 block compression using liblz4: https://lz4.org/

This is the LZ4 Block format described in https://github.com/lz4/lz4/blob/v1.10.0/doc/lz4_Block_format.md

This format has no framing layer and is NOT compatible with the `lz4` CLI.

Decoding requires the encoded size to be at most `typemax(Int32)`.

# Keyword Arguments

- `codec::LZ4BlockCodec=LZ4BlockCodec()`
"""
struct LZ4BlockDecodeOptions <: DecodeOptions
    codec::LZ4BlockCodec
end
function LZ4BlockDecodeOptions(;
        codec::LZ4BlockCodec=LZ4BlockCodec(),
        kwargs...
    )
    LZ4BlockDecodeOptions(codec)
end

is_thread_safe(::LZ4BlockDecodeOptions) = true

# There is no header or footer, so always return nothing
function try_find_decoded_size(::LZ4BlockDecodeOptions, src::AbstractVector{UInt8})::Nothing
    nothing
end

function try_decode!(d::LZ4BlockDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    if src_size > typemax(Int32)
        throw(LZ4DecodingError("encoded size is larger than `typemax(Int32)`"))
    end
    src_size32 = src_size%Int32
    dst_size32 = clamp(length(dst), Int32)
    cconv_src = Base.cconvert(Ptr{UInt8}, src)
    cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
    ret = GC.@preserve cconv_src cconv_dst begin
        src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
        dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
        unsafe_lz4_decompress(src_p, dst_p, src_size32, dst_size32)
    end
    if signbit(ret)
        # Manually find the decoded size because
        # Otherwise there is no way to tell if malformed or dst is
        # too small :(.
        # This is not done in try_find_decoded_size because it is too slow
        actual_decoded_len = dry_run_block_decode(src)
        if actual_decoded_len ≤ dst_size32
            throw(LZ4DecodingError("unknown LZ4 block decoding error"))
        elseif actual_decoded_len > typemax(Int32)
            throw(LZ4DecodingError("actual decoded size > typemax(Int32): $(actual_decoded_len) > $(typemax(Int32))"))
        else
            # Ok to try again with larger dst
           return nothing
        end
    else
        return Int64(ret)
    end
end

"""
    dry_run_block_decode(src::AbstractVector{UInt8})::Int64

If src is a valid independent lz4 block, return the decoded size. Otherwise throw a
`LZ4DecodingError`.

The `(:LZ4_decompress_safe, liblz4)` c function doesn't allow distinguishing
between different errors. Ref: https://github.com/lz4/lz4/issues/156

This function can be used if `LZ4_decompress_safe` fails to get more information
about a block for error recovery purposes.
"""
function dry_run_block_decode(src::AbstractVector{UInt8})::Int64
    # based on https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
    src_size::Int64 = length(src)
    @assert !signbit(src_size)
    src_ptr::Int64 = 0
    dst_size::Int64 = 0
    last_match_start::Int64 = -1 # -1 marks first sequence
    while true
        # read token
        if src_ptr > src_size - 1
            throw(LZ4DecodingError("unexpected end of input"))
        end
        local token = src[begin+src_ptr]
        src_ptr += Int64(1)

        # read length of literals
        local h_bits = token >> 4
        local l_bits = token & 0x0F
        local length_of_literals::Int64 = h_bits
        if h_bits == 0x0F
            # The value 15 is a special case: more bytes are required to indicate the full length.
            while true
                if src_ptr > src_size - 1
                    throw(LZ4DecodingError("unexpected end of input"))
                end
                local x = src[begin+src_ptr]
                src_ptr += Int64(1)
                # `length_of_literals` shouldn't overflow unless input size
                # is multiple petabytes
                length_of_literals += Int64(x)
                x == 0xFF || break
            end
        end

        # read literals and end of block checks
        dst_size += length_of_literals
        src_ptr += length_of_literals
        if src_ptr > src_size
            throw(LZ4DecodingError("unexpected end of input"))
        elseif src_ptr == src_size
            # End of block condition 1
            # The last sequence contains only literals. The block ends right after the literals (no offset field).
            if !iszero(l_bits)
                throw(LZ4DecodingError("end of block condition 1 violated"))
            end
            if last_match_start != -1
                # There was a previous match.
                # Check end of block condition 2:
                # The last 5 bytes of input are always literals. Therefore, the last sequence contains at least 5 bytes.
                if length_of_literals < 5
                    throw(LZ4DecodingError("end of block condition 2 violated"))
                end
                # Check end of block condition 3:
                # The last match must start at least 12 bytes before the end of block. The last match is part of the penultimate sequence. It is followed by the last sequence, which contains only literals.
                if last_match_start > dst_size - 12
                    throw(LZ4DecodingError("end of block condition 3 violated"))
                end
                return dst_size
            else
                # No previous match.
                # End of block condition 2 and 3 do not need to be checked
                return dst_size
            end
        end

        # read offset
        if src_ptr > src_size - 2
            throw(LZ4DecodingError("unexpected end of input"))
        end
        local offset::UInt16 = UInt16(src[begin+src_ptr]) | UInt16(src[begin+src_ptr+1])<<8
        src_ptr += Int64(2)
        if iszero(offset)
            # The presence of a 0 offset value denotes an invalid (corrupted) block.
            throw(LZ4DecodingError("zero offset value found"))
        elseif offset > dst_size
            throw(LZ4DecodingError("offset is before the beginning of the output"))
        end
        last_match_start = dst_size

        # read matchlength
        matchlength::Int64 = Int64(l_bits) + Int64(4)
        if l_bits == 0x0F
            while true
                if src_ptr > src_size - 1
                    throw(LZ4DecodingError("unexpected end of input"))
                end
                local x = src[begin+src_ptr]
                src_ptr += Int64(1)
                # `matchlength` shouldn't overflow unless input size
                # is multiple petabytes
                matchlength += Int64(x)
                x == 0xFF || break
            end
        end
        dst_size += matchlength

        # continue to next sequence
    end
end

"""
    struct LZ4NumcodecsDecodeOptions <: DecodeOptions
    LZ4NumcodecsDecodeOptions(; kwargs...)

lz4 numcodecs style compression using liblz4: https://lz4.org/

This is the [`LZ4BlockCodec`](@ref) format with a 4-byte header containing the
size of the decoded data as a little-endian 32-bit signed integer.

This format is documented in https://numcodecs.readthedocs.io/en/stable/compression/lz4.html

This format is NOT compatible with the `lz4` CLI.

Decoding requires the exact encoded size to be known and be no more than `typemax(Int32) + 4`.

# Keyword Arguments

- `codec::LZ4NumcodecsCodec=LZ4NumcodecsCodec()`
"""
struct LZ4NumcodecsDecodeOptions <: DecodeOptions
    codec::LZ4NumcodecsCodec
end
function LZ4NumcodecsDecodeOptions(;
        codec::LZ4NumcodecsCodec=LZ4NumcodecsCodec(),
        kwargs...
    )
    LZ4NumcodecsDecodeOptions(codec)
end

is_thread_safe(::LZ4NumcodecsDecodeOptions) = true

function try_find_decoded_size(::LZ4NumcodecsDecodeOptions, src::AbstractVector{UInt8})::Int64
    if length(src) < 4
        throw(LZ4DecodingError("unexpected end of input"))
    else
        decoded_size = Int32(0)
        for i in 0:3
            decoded_size |= Int32(src[begin+i])<<(i*8)
        end
        if signbit(decoded_size)
            throw(LZ4DecodingError("decoded size is negative"))
        else
            Int64(decoded_size)
        end
    end
end

function try_decode!(d::LZ4NumcodecsDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    decoded_size = try_find_decoded_size(d, src)
    @assert !isnothing(decoded_size)
    src_size::Int64 = length(src)
    if src_size-4 > typemax(Int32)
        throw(LZ4DecodingError("encoded size is larger than `typemax(Int32) + 4`"))
    end
    src_size32 = (src_size-4)%Int32
    dst_size::Int64 = length(dst)
    if decoded_size > dst_size
        nothing
    else
        cconv_src = Base.cconvert(Ptr{UInt8}, src)
        cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
        GC.@preserve cconv_src cconv_dst begin
            src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
            dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
            # decoded_size must already be ≤ typemax(Int32) from try_find_decoded_size
            ret = unsafe_lz4_decompress(src_p+4, dst_p, src_size32, decoded_size%Int32)
            if signbit(ret)
                throw(LZ4DecodingError("src is malformed"))
            elseif ret != decoded_size
                throw(LZ4DecodingError("saved decoded size is not correct"))
            else
                return Int64(ret)
            end
        end
    end
end


"""
    struct LZ4HDF5DecodeOptions <: DecodeOptions
    LZ4HDF5DecodeOptions(; kwargs...)

LZ4 HDF5 format compression using liblz4: https://lz4.org/

This is the LZ4 HDF5 format used in HDF5 Filter ID: 32004.

This format is documented in https://github.com/HDFGroup/hdf5_plugins

This format is NOT compatible with the `lz4` CLI.

# Keyword Arguments

- `codec::LZ4HDF5Codec=LZ4HDF5Codec()`
"""
struct LZ4HDF5DecodeOptions <: DecodeOptions
    codec::LZ4HDF5Codec
end
function LZ4HDF5DecodeOptions(;
        codec::LZ4HDF5Codec=LZ4HDF5Codec(),
        kwargs...
    )
    LZ4HDF5DecodeOptions(codec)
end

is_thread_safe(::LZ4HDF5DecodeOptions) = true

function try_find_decoded_size(::LZ4HDF5DecodeOptions, src::AbstractVector{UInt8})::Int64
    if length(src) < 12
        throw(LZ4DecodingError("unexpected end of input"))
    else
        decoded_size = Int64(0)
        for i in 0:7
            decoded_size |= Int64(src[begin+i])<<((7-i)*8)
        end
        if signbit(decoded_size)
            throw(LZ4DecodingError("decoded size is negative"))
        else
            decoded_size
        end
    end
end

function unsafe_load_i32be(src_p::Ptr{UInt8})::Int32
    r = Int32(0)
    for i in 0:3
        r |= Int32(unsafe_load(src_p+i))<<((3-i)*8)
    end
    r
end

function try_decode!(d::LZ4HDF5DecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    decoded_size = try_find_decoded_size(d, src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    if decoded_size > dst_size
        return nothing
    end
    cconv_src = Base.cconvert(Ptr{UInt8}, src)
    cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
    GC.@preserve cconv_src cconv_dst begin
        src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
        dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
        src_left = src_size
        dst_left = decoded_size
        @assert src_left ≥ 12 # this is checked by try_find_decoded_size
        src_left -= 8
        src_p += 8
        block_size = unsafe_load_i32be(src_p)
        src_left -= 4
        src_p += 4
        if block_size ≤ 0
            throw(LZ4DecodingError("block size must be greater than zero"))
        end
        while dst_left > 0
            local b_size = min(Int64(block_size), dst_left)%Int32
            if src_left < 4
                throw(LZ4DecodingError("unexpected end of input"))
            end
            local c_size = unsafe_load_i32be(src_p)
            src_left -= 4
            src_p += 4
            if c_size ≤ 0
                throw(LZ4DecodingError("block compressed size must be greater than zero"))
            end
            if src_left < c_size
                throw(LZ4DecodingError("unexpected end of input"))
            end
            if c_size == b_size # There was no compression
                @static if VERSION ≥ v"1.10"
                    Libc.memcpy(dst_p, src_p, b_size)
                else
                    unsafe_copyto!(dst_p, src_p, b_size)
                end
            else # do the decompression
                local ret = unsafe_lz4_decompress(src_p, dst_p, c_size, b_size)
                if signbit(ret)
                    throw(LZ4DecodingError("src is malformed"))
                elseif ret != b_size
                    throw(LZ4DecodingError("saved decoded size is not correct"))
                end
            end
            src_left -= c_size
            src_p += c_size
            dst_left -= b_size
            dst_p += b_size
        end
        if !iszero(src_left)
            throw(LZ4DecodingError("unexpected $(src_left) bytes after stream"))
        end
        return decoded_size
    end
end
