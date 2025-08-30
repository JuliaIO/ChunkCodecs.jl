# ChunkCodecLibBzip2

This package implements the ChunkCodec interface for the following encoders and decoders
using the bzip2 C library <https://sourceware.org/bzip2/>

1. `BZ2Codec`, `BZ2EncodeOptions`, `BZ2DecodeOptions`

## Example

```julia-repl
julia> using ChunkCodecLibBzip2

julia> data = [0x00, 0x01, 0x02, 0x03];

julia> compressed_data = encode(BZ2EncodeOptions(), data);

julia> decompressed_data = decode(BZ2Codec(), compressed_data; max_size=length(data), size_hint=length(data));

julia> data == decompressed_data
true
```

The low level interface is defined in the `ChunkCodecCore` package.

