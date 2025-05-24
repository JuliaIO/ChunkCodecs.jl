"""
    BrotliDecodingError(msg)

Error for data that cannot be decoded.
"""
struct BrotliDecodingError <: DecodingError
    msg::String
end

function Base.showerror(io::IO, err::BrotliDecodingError)
    print(io, "BrotliDecodingError: ")
    print(io, err.msg)
    nothing
end

"""
    struct BrotliDecodeOptions <: DecodeOptions
    BrotliDecodeOptions(; kwargs...)

brotli decompression using the brotli C library <https://brotli.org/>

This is the brotli (.br) format described in RFC 7932

# Keyword Arguments

- `codec::BrotliCodec=BrotliCodec()`
"""
struct BrotliDecodeOptions <: DecodeOptions
    codec::BrotliCodec
end
function BrotliDecodeOptions(;
        codec::BrotliCodec=BrotliCodec(),
        kwargs...
    )
    BrotliDecodeOptions(codec)
end

# https://github.com/google/brotli/issues/501
is_thread_safe(::BrotliDecodeOptions) = true

function try_find_decoded_size(::BrotliDecodeOptions, src::AbstractVector{UInt8})::Nothing
    nothing
end

function try_decode!(d::BrotliDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    try_resize_decode!(d, dst, src, Int64(length(dst)))
end

function try_resize_decode!(d::BrotliDecodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}, max_size::Int64; kwargs...)::Union{Nothing, Int64}
    dst_size::Int64 = length(dst)
    src_size::Int64 = length(src)
    src_left::Int64 = src_size
    dst_left::Int64 = dst_size
    check_contiguous(dst)
    check_contiguous(src)
    if isempty(src)
        throw(BrotliDecodingError("unexpected end of stream"))
    end
    s = @ccall libbrotlidec.BrotliDecoderCreateInstance(
        C_NULL::Ptr{Cvoid},
        C_NULL::Ptr{Cvoid},
        C_NULL::Ptr{Cvoid},
    )::Ptr{BrotliDecoderState}
    if s == C_NULL
        throw(OutOfMemoryError())
    end
    try
        cconv_src = Base.cconvert(Ptr{UInt8}, src)
        while true
            # dst may get resized, so cconvert needs to be redone on each iteration.
            cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
            GC.@preserve cconv_src cconv_dst begin
                src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
                dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
                available_in = Ref(Csize_t(src_left))
                next_in = src_p + (src_size - src_left)
                available_out = Ref(Csize_t(dst_left))
                next_out = dst_p + (dst_size - dst_left)
                result = @ccall libbrotlidec.BrotliDecoderDecompressStream(
                    s::Ptr{BrotliDecoderState}, # state
                    available_in::Ref{Csize_t}, # available_in
                    next_in::Ref{Ptr{UInt8}}, # next_in
                    available_out::Ref{Csize_t}, # available_out
                    next_out::Ref{Ptr{UInt8}}, # next_out
                    C_NULL::Ptr{Csize_t}, # total_out
                )::Cint
                if result == BROTLI_DECODER_RESULT_SUCCESS || result == BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT
                    @assert available_in[] ≤ src_left
                    @assert available_out[] ≤ dst_left
                    src_left = available_in[]
                    dst_left = available_out[]
                    @assert src_left ∈ 0:src_size
                    @assert dst_left ∈ 0:dst_size
                end
                if result == BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT
                    @assert iszero(dst_left)
                    local next_size = @something grow_dst!(dst, max_size) return nothing
                    dst_left += next_size - dst_size
                    dst_size = next_size
                    @assert dst_left > 0
                elseif result == BROTLI_DECODER_RESULT_SUCCESS
                    if iszero(src_left)
                        # yay done return decompressed size
                        real_dst_size = dst_size - dst_left
                        @assert real_dst_size ∈ 0:length(dst)
                        return real_dst_size
                    else
                        # Otherwise, throw an error
                        throw(BrotliDecodingError("unexpected $(src_left) bytes after stream"))
                    end
                elseif result == BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT
                    throw(BrotliDecodingError("unexpected end of stream"))
                elseif result == BROTLI_DECODER_RESULT_ERROR
                    err_code = @ccall libbrotlidec.BrotliDecoderGetErrorCode(
                        s::Ptr{BrotliDecoderState}, # state
                    )::Cint
                    if err_code ∈ RANGE_BROTLI_DECODER_ERROR_ALLOC
                        throw(OutOfMemoryError())
                    else
                        err_str = @ccall libbrotlidec.BrotliDecoderErrorString(
                            err_code::Cint,
                        )::Ptr{Cchar}
                        throw(BrotliDecodingError(unsafe_string(err_str)))
                    end
                else
                    error("unknown brotli decoder result: $(result)")
                end
            end
        end
    finally
        @ccall libbrotlidec.BrotliDecoderDestroyInstance(
            s::Ptr{BrotliDecoderState},
        )::Cvoid
    end
end
