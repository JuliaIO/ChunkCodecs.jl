# ChunkCodecBitshuffle

## Warning: ChunkCodecBitshuffle is currently a WIP and its API may drastically change at any time.

This package implements the ChunkCodec interface for the following encoders and decoders
ported from the libbitshuffle C library <https://github.com/kiyo-masui/bitshuffle>

1. `BShufCodec`, `BShufEncodeOptions`, `BShufDecodeOptions`
1. `BShufLZCodec`, `BShufLZEncodeOptions`, `BShufLZDecodeOptions`

## Example

```julia-repl
julia> using ChunkCodecBitshuffle

julia> data = collect(0x00:0xFF);

julia> compressed_data = encode(BShufCodec(2, 0), data);

julia> decompressed_data = decode(BShufCodec(2, 0), compressed_data; max_size=length(data), size_hint=length(data));

julia> data == decompressed_data
true
```

The low level interface is defined in the `ChunkCodecCore` package.
