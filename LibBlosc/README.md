# ChunkCodecLibBlosc

This package implements the ChunkCodec interface for the following encoders and decoders
using the c-blosc library <https://github.com/Blosc/c-blosc>

1. `BloscCodec`, `BloscEncodeOptions`, `BloscDecodeOptions`

> [!CAUTION]
> c-blosc is currently not thread safe
> and has [other known issues](https://github.com/Blosc/c-blosc/issues/385) that are currently being worked around.

## Example

```julia-repl
julia> using ChunkCodecLibBlosc

julia> data = [0x00, 0x01, 0x02, 0x03];

julia> compressed_data = encode(BloscEncodeOptions(), data);

julia> decompressed_data = decode(BloscCodec(), compressed_data; max_size=length(data), size_hint=length(data));

julia> data == decompressed_data
true
```

The low level interface is defined in the `ChunkCodecCore` package.

