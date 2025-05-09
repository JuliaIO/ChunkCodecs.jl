# ChunkCodecLibBrotli

## Warning: ChunkCodecLibBrotli is currently a WIP and its API may drastically change at any time.

This package implements the ChunkCodec interface for the following encoders and decoders
using the brotli C library <https://brotli.org/>

1. `BrotliCodec`, `BrotliEncodeOptions`, `BrotliDecodeOptions`

## Example

```julia-repl
julia> using ChunkCodecLibBrotli

julia> data = [0x00, 0x01, 0x02, 0x03];

julia> compressed_data = encode(BrotliEncodeOptions(;quality=6), data);

julia> decompressed_data = decode(BrotliCodec(), compressed_data; max_size=length(data), size_hint=length(data));

julia> data == decompressed_data
true
```

The low level interface is defined in the `ChunkCodecCore` package.

