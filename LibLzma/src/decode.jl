"""
    LZMADecodingError(code)

Error for data that cannot be decoded.
"""
struct LZMADecodingError <: DecodingError
    code::Cint
end

function Base.showerror(io::IO, err::LZMADecodingError)
    print(io, "LZMADecodingError: ")
    if err.code == LZMA_DATA_ERROR
        print(io, "LZMA_DATA_ERROR: data is corrupt")
    elseif err.code == LZMA_FORMAT_ERROR
        print(io, "LZMA_FORMAT_ERROR: file format not recognized")
    elseif err.code == LZMA_OPTIONS_ERROR
        print(io, "LZMA_OPTIONS_ERROR: reserved bits set in headers. Data corrupt, or upgrading liblzma may help")
    elseif err.code == LZMA_BUF_ERROR
        print(io, "LZMA_BUF_ERROR: the compressed stream may be truncated or corrupt")
    else
        print(io, "unknown lzma error code: ")
        print(io, err.code)
    end
    nothing
end

"""
    struct XZDecodeOptions <: DecodeOptions
    XZDecodeOptions(; kwargs...)

xz decompression using the liblzma C library <https://tukaani.org/xz/>

Like the command line tool `xz`, decoding accepts concatenated and padded compressed data and returns the decompressed data concatenated.

# Keyword Arguments

- `codec::XZCodec=XZCodec()`
"""
struct XZDecodeOptions <: DecodeOptions
    codec::XZCodec
end
function XZDecodeOptions(;
        codec::XZCodec=XZCodec(),
        kwargs...
    )
    XZDecodeOptions(codec)
end
can_concatenate(::XZDecodeOptions) = true

function try_find_decoded_size(::XZDecodeOptions, src::AbstractVector{UInt8})::Nothing
    # Potentially this could be found by parsing through the index
    # This is complicated by potential padding and concatenated streams
    nothing
end

function try_decode!(d::XZDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::MaybeSize
    try_resize_decode!(d, dst, src, Int64(length(dst)))
end

function try_resize_decode!(d::XZDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}, max_size::Int64; kwargs...)::MaybeSize
    dst_size::Int64 = length(dst)
    src_size::Int64 = length(src)
    src_left::Int64 = src_size
    dst_left::Int64 = dst_size
    check_contiguous(dst)
    check_contiguous(src)
    if isempty(src)
        throw(LZMADecodingError(LZMA_BUF_ERROR))
    end
    cconv_src = Base.cconvert(Ptr{UInt8}, src)
    # We start by allocating our allocator
    cconv_allocator = Base.cconvert(Ref{lzma_allocator}, default_allocator())
    GC.@preserve cconv_allocator begin
        allocator_p = Base.unsafe_convert(Ref{lzma_allocator}, cconv_allocator)
        stream = lzma_stream()
        stream.allocator = allocator_p
        ret = @ccall liblzma.lzma_stream_decoder(
            stream::Ref{lzma_stream},
            typemax(UInt64)::UInt64,
            LZMA_CONCATENATED::UInt32,
        )::Cint
        if ret == LZMA_MEM_ERROR
            throw(OutOfMemoryError())
        elseif ret != LZMA_OK
            error("Unknown lzma error code: $(ret)")
        end
        try
            while true # Loop for resizing dst
                # dst may get resized, so cconvert needs to be redone on each iteration.
                cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
                GC.@preserve cconv_src cconv_dst begin
                    src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
                    dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
                    stream.avail_in = src_left
                    stream.avail_out = dst_left
                    stream.next_in = src_p + (src_size - src_left)
                    stream.next_out = dst_p + (dst_size - dst_left)
                    ret = @ccall liblzma.lzma_code(
                        stream::Ref{lzma_stream},
                        LZMA_FINISH::Cint,
                    )::Cint
                    if ret == LZMA_OK || ret == LZMA_STREAM_END
                        @assert stream.avail_in ≤ src_left
                        @assert stream.avail_out ≤ dst_left
                        src_left = stream.avail_in
                        dst_left = stream.avail_out
                        @assert src_left ∈ 0:src_size
                        @assert dst_left ∈ 0:dst_size
                    end
                    if ret == LZMA_OK
                        # Likely not enough output space
                        # but also potentially the input is truncated
                        # Unlike zlib, we can keep trying until we get LZMA_BUF_ERROR
                        if iszero(dst_left)
                            # Give more space and try again
                            # This might result in returning a NOT_SIZE
                            # when instead the actual issue is that the input is truncated.
                            local next_size = grow_dst!(dst, max_size)
                            if isnothing(next_size)
                                return NOT_SIZE
                            end
                            dst_left += next_size - dst_size
                            dst_size = next_size
                            @assert dst_left > 0
                        end
                    elseif ret == LZMA_STREAM_END
                        @assert iszero(src_left)
                        # yay done return decompressed size
                        real_dst_size = dst_size - dst_left
                        @assert real_dst_size ∈ 0:length(dst)
                        return real_dst_size
                    elseif ret == LZMA_DATA_ERROR || ret == LZMA_FORMAT_ERROR || ret == LZMA_OPTIONS_ERROR || ret == LZMA_BUF_ERROR
                        throw(LZMADecodingError(ret))
                    elseif ret == LZMA_MEM_ERROR
                        throw(OutOfMemoryError())
                    else
                        error("Unknown lzma error code: $(ret)")
                    end
                end
            end
        finally
            @ccall liblzma.lzma_end(stream::Ref{lzma_stream})::Cvoid
        end
    end
end
