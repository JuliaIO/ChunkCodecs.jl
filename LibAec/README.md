# ChunkCodecLibBrotli

## Warning: ChunkCodecLibAec is currently a WIP and its API may drastically change at any time.

This package implements the ChunkCodec interface for the following encoders and decoders
using the libaec C library <https://gitlab.dkrz.de/k202009/libaec>

1. `SzipHDF5Codec`, `SzipHDF5EncodeOptions`, `SzipHDF5DecodeOptions`

## Example

```julia-repl
julia> using ChunkCodecLibAec

julia> data = [0x00, 0x01, 0x02, 0x03];

julia> codec = SzipHDF5Codec(;options_mask=0, bits_per_pixel=32, pixels_per_block=8, pixels_per_scanline=8)

julia> compressed_data = encode(codec, data);

julia> decompressed_data = decode(codec, compressed_data; max_size=length(data), size_hint=length(data));

julia> data == decompressed_data
true
```

The low level interface is defined in the `ChunkCodecCore` package.

