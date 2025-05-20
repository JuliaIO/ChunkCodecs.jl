module ChunkCodecLibBrotli

using brotli_jll: libbrotlidec, libbrotlienc

using ChunkCodecCore:
    Codec,
    EncodeOptions,
    DecodeOptions,
    check_contiguous,
    check_in_range,
    grow_dst!,
    DecodingError
import ChunkCodecCore:
    decode_options,
    try_decode!,
    try_resize_decode!,
    try_encode!,
    encode_bound,
    is_thread_safe,
    try_find_decoded_size,
    decoded_size_range

export BrotliCodec,
    BrotliEncodeOptions,
    BrotliDecodeOptions,
    BrotliDecodingError

# reexport ChunkCodecCore
using ChunkCodecCore: ChunkCodecCore, encode, decode
export ChunkCodecCore, encode, decode


include("libbrotli.jl")

"""
    struct BrotliCodec <: Codec
    BrotliCodec()

brotli compression using the brotli C library <https://brotli.org/>

This is the brotli (.br) format described in RFC 7932

See also [`BrotliEncodeOptions`](@ref) and [`BrotliDecodeOptions`](@ref)
"""
struct BrotliCodec <: Codec
end
decode_options(::BrotliCodec) = BrotliDecodeOptions()

include("encode.jl")
include("decode.jl")

end # module ChunkCodecLibBrotli
