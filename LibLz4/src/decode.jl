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
    check_in_range(Int64(0):max_size; dst_size=length(dst))
    olb::Int64 = length(dst)
    dst_size::Int64 = olb
    src_size::Int64 = length(src)
    src_left::Int64 = src_size
    dst_left::Int64 = dst_size
    check_contiguous(dst)
    check_contiguous(src)
    cconv_src = Base.cconvert(Ptr{UInt8}, src)
    # This outer loop is to decode a concatenation of multiple compressed streams.
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
                                if length(dst) > olb && length(dst) != real_dst_size
                                    resize!(dst, real_dst_size) # shrink to just contain output if it was resized.
                                end
                                return real_dst_size
                            else
                                # try and decompress next frame
                                # there must be progress
                                @assert Δin > 0 || Δout > 0
                                break
                            end
                        else
                            if iszero(dst_left) # needs more output
                                # grow dst or return nothing
                                if dst_size ≥ max_size
                                    return nothing
                                end
                                # This inequality prevents overflow
                                local next_size = if max_size - dst_size ≤ dst_size
                                    max_size
                                else
                                    max(2*dst_size, Int64(1))
                                end
                                resize!(dst, next_size)
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
    LZ4BlockDecodeOptions(::LZ4BlockCodec=LZ4BlockCodec(); kwargs...)

lz4 block decompression using liblz4: https://lz4.org/

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
    check_in_range(Cint(0):typemax(Cint); src_size)
    # LZ4_decompress_safe (const char* src, char* dst, int compressedSize, int dstCapacity);
    dstCapacity = clamp(length(dst), Cint)
    ret = ccall(
        (:LZ4_decompress_safe, liblz4), Cint,
        (Ptr{UInt8}, Ptr{UInt8}, Cint, Cint),
        src, dst, src_size, dstCapacity
    )
    if signbit(ret)
        # Manually find the decoded size because
        # Otherwise there is no way to tell if malformed or dst is
        # too small :(.
        # This is not done in try_find_decoded_size because it is too slow
        actual_decoded_len = dry_run_block_decode(src)
        if actual_decoded_len ≤ dstCapacity
            throw(LZ4DecodingError("unknown LZ4 block decoding error"))
        elseif actual_decoded_len > typemax(Cint)
            throw(LZ4DecodingError("actual decoded length > typemax(Cint): $(actual_decoded_len) > $(typemax(Cint))"))
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
    struct LZ4ZarrDecodeOptions <: DecodeOptions
    LZ4ZarrDecodeOptions(::LZ4ZarrCodec=LZ4ZarrCodec(); kwargs...)

lz4 numcodecs style compression using liblz4: https://lz4.org/

This is the LZ4 Zarr format described in https://numcodecs.readthedocs.io/en/stable/compression/lz4.html

# Keyword Arguments

- `codec::LZ4ZarrCodec=LZ4ZarrCodec()`
"""
struct LZ4ZarrDecodeOptions <: DecodeOptions
    codec::LZ4ZarrCodec
end
function LZ4ZarrDecodeOptions(;
        codec::LZ4ZarrCodec=LZ4ZarrCodec(),
        kwargs...
    )
    LZ4ZarrDecodeOptions(codec)
end

is_thread_safe(::LZ4ZarrDecodeOptions) = true

# There is a 4 byte header with the decoded size as a 32 bit unsigned integer
function try_find_decoded_size(::LZ4ZarrDecodeOptions, src::AbstractVector{UInt8})::Int64
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

function try_decode!(d::LZ4ZarrDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    decoded_size = try_find_decoded_size(d, src)
    @assert !isnothing(decoded_size)
    dst_size::Int64 = length(dst)
    if decoded_size > dst_size
        nothing
    else
        ret = try_decode!(LZ4BlockDecodeOptions(), dst, @view(src[begin+4:end]))
        if ret != decoded_size
            throw(LZ4DecodingError("saved decoded size is not correct"))
        end
        ret
    end
end
