# ChunkCodecLibLz4

This package implements the ChunkCodec interface for the following encoders and decoders
using the lz4 C library <https://lz4.org/>

1. `LZ4FrameCodec`, `LZ4FrameEncodeOptions`, `LZ4FrameDecodeOptions`
1. `LZ4BlockCodec`, `LZ4BlockEncodeOptions`, `LZ4BlockDecodeOptions`
1. `LZ4NumcodecsCodec`, `LZ4NumcodecsEncodeOptions`, `LZ4NumcodecsDecodeOptions`

## Example

```julia-repl
julia> using ChunkCodecLibLz4

julia> data = [0x00, 0x01, 0x02, 0x03];

julia> compressed_data = encode(LZ4FrameEncodeOptions(;compressionLevel=3), data);

julia> decompressed_data = decode(LZ4FrameCodec(), compressed_data; max_size=length(data), size_hint=length(data));

julia> data == decompressed_data
true
```

The low level interface is defined in the `ChunkCodecCore` package.

