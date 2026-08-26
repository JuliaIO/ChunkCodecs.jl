# Release Notes

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

## [v0.4.0](https://github.com/JuliaIO/ChunkCodecs.jl/tree/LibBlosc-v0.4.0) - 2026-08-26

- BREAKING changed the `BloscEncodeOptions` `compressor::String` field to `compcode::Int32`.
- BREAKING setting both the `compcode` and `compressor` keyword arguments of `BloscEncodeOptions` now throws an `ArgumentError`.
- BREAKING `is_compressor_valid`, `compcode`, and the `BloscEncodeOptions` `compressor` keyword argument now only accept `String`, instead of any `AbstractString`.

## [v0.3.2](https://github.com/JuliaIO/ChunkCodecs.jl/tree/LibBlosc-v0.3.2) - 2026-08-26

- Added a `compcode` keyword argument for `BloscEncodeOptions` and constants `BLOSC_BLOSCLZ`, `BLOSC_LZ4`, `BLOSC_LZ4HC`, `BLOSC_ZLIB`, and `BLOSC_ZSTD` [#94](https://github.com/JuliaIO/ChunkCodecs.jl/pull/94)

## [v0.3.1](https://github.com/JuliaIO/ChunkCodecs.jl/tree/LibBlosc-v0.3.1) - 2025-08-29

- Update to `ChunkCodecCore` 1

## [v0.3.0](https://github.com/JuliaIO/ChunkCodecs.jl/tree/LibBlosc-v0.3.0) - 2025-08-26

- Update to `ChunkCodecCore` 0.6 [#72](https://github.com/JuliaIO/ChunkCodecs.jl/pull/72)
- Added support for Julia 1.6 [#68](https://github.com/JuliaIO/ChunkCodecs.jl/pull/68)

## [v0.2.1](https://github.com/JuliaIO/ChunkCodecs.jl/tree/LibBlosc-v0.2.1) - 2025-07-28

- Added support for Julia 1.9 [#63](https://github.com/JuliaIO/ChunkCodecs.jl/pull/63)

## [v0.2.0](https://github.com/JuliaIO/ChunkCodecs.jl/tree/LibBlosc-v0.2.0) - 2025-05-23

- Update to `ChunkCodecCore` 0.5 [#45](https://github.com/JuliaIO/ChunkCodecs.jl/pull/45)

## [v0.1.2](https://github.com/JuliaIO/ChunkCodecs.jl/tree/LibBlosc-v0.1.2) - 2025-04-06

- Added support for Julia 1.10 [#33](https://github.com/JuliaIO/ChunkCodecs.jl/pull/33)

## [v0.1.1](https://github.com/JuliaIO/ChunkCodecs.jl/tree/LibBlosc-v0.1.1) - 2025-02-26

### Added

- Initial release
