module ChunkCodecLibBlosc2

using Base.Libc: free
using Base.Threads

using Accessors

using Blosc2_jll: libblosc2

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

export Blosc2Codec,
       Blosc2EncodeOptions,
       Blosc2DecodeOptions,
       Blosc2DecodingError

if VERSION >= v"1.11.0-DEV.469"
    eval(Meta.parse("public is_compressor_valid, compcode, compname"))
end

# reexport ChunkCodecCore
using ChunkCodecCore: ChunkCodecCore, encode, decode
export ChunkCodecCore, encode, decode

include("libblosc2.jl")

"""
    struct Blosc2Codec <: Codec
    Blosc2Codec()

Blosc2 compression using c-blosc2 library: https://github.com/Blosc2/c-blosc2

Decoding does not accept any extra data appended to the compressed block.
Decoding also does not accept truncated data, or multiple compressed blocks concatenated together.

[`Blosc2EncodeOptions`](@ref) and [`Blosc2DecodeOptions`](@ref)
can be used to set decoding and encoding options.
"""
struct Blosc2Codec <: Codec end
decode_options(::Blosc2Codec) = Blosc2DecodeOptions()

include("encode.jl")
include("decode.jl")

end # module ChunkCodecLibBlosc2
