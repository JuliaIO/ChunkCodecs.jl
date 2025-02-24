module ChunkCodecLibBlosc

using Blosc_jll: libblosc

using ChunkCodecCore:
    Codec,
    EncodeOptions,
    DecodeOptions,
    check_in_range,
    check_contiguous,
    DecodingError
import ChunkCodecCore:
    decode_options,
    try_decode!,
    try_encode!,
    encode_bound,
    try_find_decoded_size,
    decoded_size_range

export BloscCodec,
    BloscEncodeOptions,
    BloscDecodeOptions,
    BloscDecodingError

public is_compressor_valid

# reexport ChunkCodecCore
using ChunkCodecCore: ChunkCodecCore, encode, decode
export ChunkCodecCore, encode, decode

include("libblosc.jl")

"""
    struct BloscCodec <: Codec
    BloscCodec()

Blosc compression using c-blosc library: https://github.com/Blosc/c-blosc

Decoding does not accept any extra data appended to the compressed block.
Decoding also does not accept truncated data, or multiple compressed blocks concatenated together.

[`BloscEncodeOptions`](@ref) and [`BloscDecodeOptions`](@ref)
can be used to set decoding and encoding options.
"""
struct BloscCodec <: Codec end
decode_options(::BloscCodec) = BloscDecodeOptions() # default decode options

include("encode.jl")
include("decode.jl")

end # module ChunkCodecLibBlosc
