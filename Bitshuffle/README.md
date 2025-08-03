# ChunkCodecBitshuffle

## Warning: ChunkCodecBitshuffle is currently a WIP and its API may drastically change at any time.

This package implements the ChunkCodec interface for the following encoders and decoders
ported from the libbitshuffle C library <https://github.com/kiyo-masui/bitshuffle>

1. `BShufCodec`, `BShufEncodeOptions`, `BShufDecodeOptions`
1. `BShufZCodec`, `BShufZEncodeOptions`, `BShufZDecodeOptions`

The low level interface is defined in the `ChunkCodecCore` package.
