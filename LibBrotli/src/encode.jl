"""
    struct BrotliEncodeOptions <: EncodeOptions
    BrotliEncodeOptions(; kwargs...)

brotli compression using the brotli C library <https://brotli.org/>

This is the brotli (.br) format described in RFC 7932

# Keyword Arguments

- `codec::BrotliCodec=BrotliCodec()`
- `quality::Integer=$(BROTLI_MAX_QUALITY)`: The quality must be between $(BROTLI_MIN_QUALITY) and $(BROTLI_MAX_QUALITY).

  $(BROTLI_MIN_QUALITY) gives best compression speed, $(BROTLI_MAX_QUALITY) gives best compressed size.
- `lgwin::Integer=$(BROTLI_MAX_WINDOW_BITS)`: Sliding LZ77 window size is at most `(1 << lgwin) - 16`.

  Must be between $(BROTLI_MIN_WINDOW_BITS) and $(BROTLI_MAX_WINDOW_BITS).
  Encoder may reduce this value, e.g. if input is much smaller than window size.
- `mode::Integer=0`: Tune encoder for specific input.

  0 is default.
  1 is for UTF-8 text.
  2 is for WOFF 2.0.
"""
struct BrotliEncodeOptions <: EncodeOptions
    codec::BrotliCodec
    quality::UInt32
    lgwin::UInt32
    mode::UInt32
end
function BrotliEncodeOptions(;
        codec::BrotliCodec=BrotliCodec(),
        quality::Integer=BROTLI_MAX_QUALITY,
        lgwin::Integer=BROTLI_MAX_WINDOW_BITS,
        mode::Integer=0,
        kwargs...
    )
    check_in_range(0:2; mode)
    check_in_range(BROTLI_MIN_WINDOW_BITS:BROTLI_MAX_WINDOW_BITS; lgwin)
    BrotliEncodeOptions(
        codec,
        UInt32(clamp(quality, BROTLI_MIN_QUALITY, BROTLI_MAX_QUALITY)),
        UInt32(lgwin),
        UInt32(mode),
    )
end

# https://github.com/google/brotli/issues/501
is_thread_safe(::BrotliEncodeOptions) = true

# Modified from the BrotliEncoderMaxCompressedSize function in
# https://github.com/google/brotli/blob/v1.1.0/c/enc/encode.c#L1202
# to use saturating Int64 instead of size_t
function encode_bound(::BrotliEncodeOptions, src_size::Int64)::Int64
    # [window bits / empty metadata] + N * [uncompressed] + [last empty]
    num_large_blocks = src_size >> 14
    overhead = 2 + (4 * num_large_blocks) + 3 + 1
    clamp(
        widen(src_size) +
        widen(overhead),
        Int64,
    )
end

function decoded_size_range(::BrotliEncodeOptions)
    # From ChunkCodecTests.find_max_decoded_size(::EncodeOptions)
    Int64(0):Int64(1):Int64(0x7ff8007ff8007ff4)
end

function try_encode!(e::BrotliEncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::Union{Nothing, Int64}
    check_contiguous(dst)
    check_contiguous(src)
    src_size::Int64 = length(src)
    dst_size::Int64 = length(dst)
    check_in_range(decoded_size_range(e); src_size)
    # Unfortunately the builtin BrotliEncoderCompress C function doesn't report errors
    # in a nice way. So this is ported from BrotliEncoderCompress in
    # https://github.com/google/brotli/blob/v1.1.0/c/enc/encode.c#L1247
    # with different error handling logic.
    max_out_size = encode_bound(e, src_size) # the decoded_size_range check ensures no overflow issue here.
    clamped_dst_size = min(dst_size, max_out_size)
    if iszero(dst_size)
        # Output buffer needs at least one byte.
        return nothing
    end
    cconv_src = Base.cconvert(Ptr{UInt8}, src)
    cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
    GC.@preserve cconv_src cconv_dst begin
        src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
        dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
        if iszero(src_size)
            # Handle the special case of empty input.
            unsafe_store!(dst_p, 0x06)
            return Int64(1)
        end
        s = @ccall libbrotlienc.BrotliEncoderCreateInstance(
            C_NULL::Ptr{Cvoid},
            C_NULL::Ptr{Cvoid},
            C_NULL::Ptr{Cvoid},
        )::Ptr{BrotliEncoderState}
        if s == C_NULL
            throw(OutOfMemoryError())
        end
        try
            unsafe_BrotliEncoderSetParameter(s, BROTLI_PARAM_QUALITY, e.quality)
            # https://github.com/google/brotli/blob/v1.1.0/c/tools/brotli.c#L1181
            # Decrease lgwin if src_size is small
            # At some point the C library may do this automatically
            lgwin = e.lgwin
            while BROTLI_MAX_BACKWARD_LIMIT(lgwin-1) ≥ src_size && lgwin > BROTLI_MIN_WINDOW_BITS
                lgwin -= UInt32(1)
            end
            @assert lgwin ≤ e.lgwin
            unsafe_BrotliEncoderSetParameter(s, BROTLI_PARAM_LGWIN, lgwin)
            unsafe_BrotliEncoderSetParameter(s, BROTLI_PARAM_MODE, e.mode)
            # https://github.com/google/brotli/blob/v1.1.0/c/tools/brotli.c#L1193
            unsafe_BrotliEncoderSetParameter(s, BROTLI_PARAM_SIZE_HINT,
                min(src_size, Int64(1)<<30)%UInt32
            )
            available_out = Ref(Csize_t(clamped_dst_size))
            result = @ccall libbrotlienc.BrotliEncoderCompressStream(
                s::Ptr{BrotliEncoderState}, # state
                BROTLI_OPERATION_FINISH::Cint, # op
                Ref(Csize_t(src_size))::Ref{Csize_t}, # available_in
                Ref(src_p)::Ref{Ptr{UInt8}}, # next_in
                available_out::Ref{Csize_t}, # available_out
                Ref(dst_p)::Ref{Ptr{UInt8}}, # next_out
                C_NULL::Ptr{Csize_t}, # total_out
            )::Cint
            if result == 1
                is_finished = @ccall libbrotlienc.BrotliEncoderIsFinished(
                    s::Ptr{BrotliEncoderState}, # state
                )::Cint
                if is_finished == 1
                    @assert available_out[] < clamped_dst_size
                    return clamped_dst_size - Int64(available_out[])
                else
                    @assert iszero(available_out[])
                    # not enough output space, try the fallback if it is safe
                    # This is needed because some options may fail to compress
                    # even if given encode_bound output space.
                    if dst_size ≥ max_out_size
                        return unsafe_MakeUncompressedStream(src_p, src_size, dst_p)
                    else
                        return nothing
                    end
                end
            else
                throw(OutOfMemoryError())
            end
        finally
            @ccall libbrotlienc.BrotliEncoderDestroyInstance(
                s::Ptr{BrotliEncoderState},
            )::Cvoid
        end
    end
end
