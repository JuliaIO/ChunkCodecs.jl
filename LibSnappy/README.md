# ChunkCodecLibSnappy

## Warning: ChunkCodecLibSnappy is currently a WIP and its API may drastically change at any time.

This package implements the ChunkCodec interface for the following encoders and decoders
using the snappy library <https://github.com/google/snappy>

1. `SnappyCodec`, `SnappyEncodeOptions`, `SnappyDecodeOptions`

## Example

```julia-repl
julia> using ChunkCodecLibSnappy

julia> data = [0x00, 0x01, 0x02, 0x03];

julia> compressed_data = encode(SnappyEncodeOptions(), data);

julia> decompressed_data = decode(SnappyCodec(), compressed_data; max_size=length(data), size_hint=length(data));

julia> data == decompressed_data
true
```

The low level interface is defined in the `ChunkCodecCore` package.

