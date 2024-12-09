"""
    BZ2DecodingError(code)

Error for data that cannot be decoded.
"""
struct BZ2DecodingError <: DecodingError
    code::Cint
end

function Base.showerror(io::IO, err::BZ2DecodingError)
    print(io, "BZ2DecodingError: ")
    if err.code == BZ_DATA_ERROR
        print(io, "BZ_DATA_ERROR: a data integrity error is detected in the compressed stream")
    elseif err.code == BZ_DATA_ERROR_MAGIC
        print(io, "BZ_DATA_ERROR_MAGIC: the compressed stream doesn't begin with the right magic bytes")
    elseif err.code == BZ_UNEXPECTED_EOF
        print(io, "BZ_UNEXPECTED_EOF: the compressed stream may be truncated")
    else
        print(io, "unknown bzip2 error code: ")
        print(io, err.code)
    end
    nothing
end

"""
    struct BZ2DecodeOptions <: DecodeOptions
    BZ2DecodeOptions(::BloscCodec=BloscCodec(); kwargs...)

bzip2 decompression using libbzip2: https://sourceware.org/bzip2/
"""
struct BZ2DecodeOptions <: DecodeOptions
    function BZ2DecodeOptions(::BZ2Codec=BZ2Codec();
            kwargs...
        )
        new()
    end
end
codec(::BZ2DecodeOptions) = BZ2Codec()
is_thread_safe(::BZ2DecodeOptions) = true

function try_find_decoded_size(::BZ2DecodeOptions, src::AbstractVector{UInt8})::Nothing
    nothing
end

function try_decode!(d::BZ2DecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    try_resize_decode!(d, dst, src; max_size=Int64(length(dst)))
end

function try_resize_decode!(d::BZ2DecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; max_size::Int64=typemax(Int64), kwargs...)::Union{Nothing, Int64}
    max_size ≥ length(dst) || throw(ArgumentError("`max_size`: $(max_size) must be at least `length(dst)`: $(length(dst))"))
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
        stream = BZStream()
        BZ2_bzDecompressInit(stream)
        try
            # This inner loop is needed because libbzip2 can work on at most 
            # 2^32 - 1 bytes at a time.
            while true
                # dst may get resized, so cconvert needs to be redone on each iteration.
                cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
                GC.@preserve cconv_src cconv_dst begin
                    src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
                    dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
                    start_avail_in = clamp(src_left, Cuint)
                    start_avail_out = clamp(dst_left, Cuint)
                    stream.avail_in = start_avail_in
                    stream.avail_out = start_avail_out
                    stream.next_in = src_p + (src_size - src_left)
                    stream.next_out = dst_p + (dst_size - dst_left)
                    ret = BZ2_bzDecompress(stream)
                    if ret == BZ_OK || ret == BZ_STREAM_END
                        @assert stream.avail_in ≤ start_avail_in
                        @assert stream.avail_out ≤ start_avail_out
                        dst_left -= start_avail_out - stream.avail_out
                        src_left -= start_avail_in - stream.avail_in
                        @assert src_left ∈ 0:src_size
                        @assert dst_left ∈ 0:dst_size
                        @assert stream.next_in == src_p + (src_size - src_left)
                        @assert stream.next_out == dst_p + (dst_size - dst_left)
                    end
                    if ret == BZ_OK
                        if iszero(stream.avail_out) # needs more output
                            if iszero(dst_left)
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
                            end
                        else # needs more input
                            if iszero(src_left)
                                throw(BZ2DecodingError(BZ_UNEXPECTED_EOF))
                            end
                            # there must be progress
                            @assert stream.avail_in < start_avail_in || stream.avail_out < start_avail_out
                        end
                    elseif ret == BZ_STREAM_END
                        if iszero(src_left)
                            # yay done return decompressed size
                            real_dst_size = dst_size - dst_left
                            @assert real_dst_size ∈ 0:length(dst)
                            if length(dst) > olb && length(dst) != real_dst_size
                                resize!(dst, real_dst_size) # shrink to just contain output if it was resized.
                            end
                            return real_dst_size
                        else
                            # try and decompress next stream
                            # there must be progress
                            @assert stream.avail_in < start_avail_in || stream.avail_out < start_avail_out
                            break
                        end
                    elseif ret == BZ_PARAM_ERROR
                        error("BZ_PARAM_ERROR this should be unreachable")
                    elseif ret == BZ_DATA_ERROR || ret == BZ_DATA_ERROR_MAGIC
                        throw(BZ2DecodingError(ret))
                    elseif ret == BZ_MEM_ERROR
                        throw(OutOfMemoryError())
                    else
                        error("unknown bzip2 error code: $(ret)")
                    end
                end
            end
        finally
            BZ2_bzDecompressEnd(stream)
        end
    end
end