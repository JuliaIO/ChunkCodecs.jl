# ChunkCodecLibBlosc2

## Warning: ChunkCodecLibBlosc2 is currently a WIP and its API may drastically change at any time.

This package implements the ChunkCodec interface for the following encoders and decoders
using the c-blosc2 library <https://github.com/Blosc/c-blosc2>

1. `Blosc2CFrame`, `Blosc2EncodeOptions`, `Blosc2DecodeOptions`

Note: It appears that the [Blosc2 Contiguous Frame
Format](https://www.blosc.org/c-blosc2/format/cframe_format.html) is
not fully protected by checksums. The [`c-blosc2`
library](https://www.blosc.org/c-blosc2) may crash (segfault) for
invalid inputs.

## Example

```julia-repl
julia> using ChunkCodecLibBlosc2

julia> data = collect(0x00:0x07);

julia> compressed_data = encode(Blosc2EncodeOptions(), data);

julia> decompressed_data = decode(Blosc2CFrame(), compressed_data; max_size=length(data), size_hint=length(data));

julia> data == decompressed_data
true
```

The low level interface is defined in the `ChunkCodecCore` package.

