module ChunkCodecLibLzma

using XZ_jll: liblzma

using ChunkCodecCore:
    Codec,
    EncodeOptions,
    DecodeOptions,
    check_in_range,
    check_contiguous,
    grow_dst!,
    DecodingError,
    MaybeSize,
    NOT_SIZE
import ChunkCodecCore:
    decode_options,
    can_concatenate,
    try_decode!,
    try_resize_decode!,
    try_encode!,
    encode_bound,
    try_find_decoded_size,
    decoded_size_range

export XZCodec,
    XZEncodeOptions,
    XZDecodeOptions,
    LZMADecodingError

if VERSION >= v"1.11.0-DEV.469"
    eval(Meta.parse("""
        public
            LZMA_PRESET_LEVEL_MASK,
            LZMA_PRESET_EXTREME,
            LZMA_CHECK_NONE,
            LZMA_CHECK_CRC32,
            LZMA_CHECK_CRC64,
            LZMA_CHECK_SHA256
    """))
end



# reexport ChunkCodecCore
using ChunkCodecCore: ChunkCodecCore, encode, decode
export ChunkCodecCore, encode, decode


include("liblzma.jl")

"""
    struct XZCodec <: Codec
    XZCodec()

xz compression using the liblzma C library <https://tukaani.org/xz/>

See also [`XZEncodeOptions`](@ref) and [`XZDecodeOptions`](@ref)
"""
struct XZCodec <: Codec
end
decode_options(::XZCodec) = XZDecodeOptions()

include("encode.jl")
include("decode.jl")

end # module ChunkCodecLibLzma
