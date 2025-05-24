module ChunkCodecLibLz4

using Lz4_jll: liblz4

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
    can_concatenate,
    try_decode!,
    try_resize_decode!,
    try_encode!,
    encode_bound,
    is_thread_safe,
    try_find_decoded_size,
    decoded_size_range

export LZ4FrameCodec,
    LZ4FrameEncodeOptions,
    LZ4FrameDecodeOptions,
    LZ4BlockCodec,
    LZ4BlockEncodeOptions,
    LZ4BlockDecodeOptions,
    LZ4NumcodecsCodec,
    LZ4NumcodecsEncodeOptions,
    LZ4NumcodecsDecodeOptions,
    LZ4HDF5Codec,
    LZ4HDF5EncodeOptions,
    LZ4HDF5DecodeOptions,
    LZ4DecodingError

# reexport ChunkCodecCore
using ChunkCodecCore: ChunkCodecCore, encode, decode
export ChunkCodecCore, encode, decode


include("liblz4.jl")
include("liblz4frame.jl")

"""
    struct LZ4FrameCodec <: Codec
    LZ4FrameCodec()

LZ4 frame compression using liblz4: https://lz4.org/

This is the LZ4 Frame (.lz4) format described in https://github.com/lz4/lz4/blob/v1.10.0/doc/lz4_Frame_format.md

This format is compatible with the `lz4` CLI.

Encode compresses data as a single frame.
Decoding will succeed even if the decompressed size is unknown.
Decoding accepts concatenated frames 
and will error if there is invalid data appended.

See also [`LZ4FrameEncodeOptions`](@ref) and [`LZ4FrameDecodeOptions`](@ref)
"""
struct LZ4FrameCodec <: Codec
end
decode_options(::LZ4FrameCodec) = LZ4FrameDecodeOptions() # default decode options
can_concatenate(::LZ4FrameCodec) = true

"""
    struct LZ4BlockCodec <: Codec
    LZ4BlockCodec()

lz4 block compression using liblz4: https://lz4.org/

This is the LZ4 Block format described in https://github.com/lz4/lz4/blob/v1.10.0/doc/lz4_Block_format.md

This format has no framing layer and is NOT compatible with the `lz4` CLI.

Decoding requires the encoded size to be at most `typemax(Int32)`.

There is also a maximum decoded size of about 2 GB for this implementation.

See also [`LZ4BlockEncodeOptions`](@ref) and [`LZ4BlockDecodeOptions`](@ref)
"""
struct LZ4BlockCodec <: Codec
end
decode_options(::LZ4BlockCodec) = LZ4BlockDecodeOptions() # default decode options

"""
    struct LZ4NumcodecsCodec <: Codec
    LZ4NumcodecsCodec()

lz4 numcodecs style compression using liblz4: https://lz4.org/

This is the [`LZ4BlockCodec`](@ref) format with a 4-byte header containing the
size of the decoded data as a little-endian 32-bit signed integer.

This format is documented in https://numcodecs.readthedocs.io/en/stable/compression/lz4.html

This format is NOT compatible with the `lz4` CLI.

Decoding requires the encoded size to be at most `typemax(Int32) + 4`.

There is also a maximum decoded size of about 2 GB for this implementation.

See also [`LZ4NumcodecsEncodeOptions`](@ref) and [`LZ4NumcodecsDecodeOptions`](@ref)
"""
struct LZ4NumcodecsCodec <: Codec
end
decode_options(::LZ4NumcodecsCodec) = LZ4NumcodecsDecodeOptions() # default decode options

"""
    struct LZ4HDF5Codec <: Codec
    LZ4HDF5Codec()

LZ4 HDF5 format compression using liblz4: https://lz4.org/

This is the LZ4 HDF5 format used in HDF5 Filter ID: 32004.

This format is documented in https://github.com/HDFGroup/hdf5_plugins

This format is NOT compatible with the `lz4` CLI.

See also [`LZ4HDF5EncodeOptions`](@ref) and [`LZ4HDF5DecodeOptions`](@ref)
"""
struct LZ4HDF5Codec <: Codec
end
decode_options(::LZ4HDF5Codec) = LZ4HDF5DecodeOptions() # default decode options

include("encode.jl")
include("decode.jl")

end # module ChunkCodecLibLz4
