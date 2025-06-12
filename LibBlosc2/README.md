# ChunkCodecLibBlosc2

## Warning: ChunkCodecLibBlosc2 is currently a WIP and its API may drastically change at any time.

This package implements the ChunkCodec interface for the following encoders and decoders
using the c-blosc2 library <https://github.com/Blosc/c-blosc2>

1. `Blosc2Codec`, `Blosc2EncodeOptions`, `Blosc2DecodeOptions`

## Example

```julia-repl
julia> using ChunkCodecLibBlosc2

julia> data = [0x00, 0x01, 0x02, 0x03];

julia> compressed_data = encode(Blosc2EncodeOptions(), data);

julia> decompressed_data = decode(Blosc2Codec(), compressed_data; max_size=length(data), size_hint=length(data));

julia> data == decompressed_data
true
```

The low level interface is defined in the `ChunkCodecCore` package.

