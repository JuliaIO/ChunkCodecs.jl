# ChunkCodecLibLzma

## Warning: ChunkCodecLibLzma is currently a WIP and its API may drastically change at any time.

This package implements the ChunkCodec interface for the following encoders and decoders
using the liblzma C library <https://tukaani.org/xz/>

1. `XZCodec`, `XZEncodeOptions`, `XZDecodeOptions`

## Example

```julia-repl
julia> using ChunkCodecLibLzma

julia> data = [0x00, 0x01, 0x02, 0x03];

julia> compressed_data = encode(XZEncodeOptions(;preset=UInt32(6), check=ChunkCodecLibLzma.LZMA_CHECK_CRC64), data);

julia> decompressed_data = decode(XZCodec(), compressed_data; max_size=length(data), size_hint=length(data));

julia> data == decompressed_data
true
```

The low level interface is defined in the `ChunkCodecCore` package.

