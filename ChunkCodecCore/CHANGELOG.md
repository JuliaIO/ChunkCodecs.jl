# Release Notes

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Unreleased

### BREAKING the resizing behavior in `try_resize_decode!` changed [#45](https://github.com/JuliaIO/ChunkCodecs.jl/pull/45)

`dst` may now be longer than the returned number of bytes, even if `dst` was grown with `resize!`.

`try_resize_decode!` will now only grow `dst`, never shrink it.

If `max_size` is less than `length(dst)`, instead of throwing an error, `try_resize_decode!` will now act as if `max_size == length(dst)`.

- Added the `grow_dst!` helper function. [#45](https://github.com/JuliaIO/ChunkCodecs.jl/pull/45)

## [v0.4.2](https://github.com/JuliaIO/ChunkCodecs.jl/tree/ChunkCodecCore-v0.4.2) - 2025-04-07

- Added the `decode!` function. [#41](https://github.com/JuliaIO/ChunkCodecs.jl/pull/41)

## [v0.4.1](https://github.com/JuliaIO/ChunkCodecs.jl/tree/ChunkCodecCore-v0.4.1) - 2025-04-06

- Added support for Julia 1.10 [#33](https://github.com/JuliaIO/ChunkCodecs.jl/pull/33)

## [v0.4.0](https://github.com/JuliaIO/ChunkCodecs.jl/tree/ChunkCodecCore-v0.4.0) - 2025-02-24

### BREAKING the `codec` function is replaced with a `.codec` property [#11](https://github.com/JuliaIO/ChunkCodecs.jl/pull/11)

## [v0.3.0](https://github.com/JuliaIO/ChunkCodecs.jl/tree/ChunkCodecCore-v0.3.0) - 2025-01-03

### BREAKING `encode_bound` is required to be monotonically increasing [#7](https://github.com/JuliaIO/ChunkCodecs.jl/pull/7)

### Added

- `ShuffleCodec` and HDF5 compatibility test [#6](https://github.com/JuliaIO/ChunkCodecs.jl/pull/6)

## [v0.2.0](https://github.com/JuliaIO/ChunkCodecs.jl/tree/ChunkCodecCore-v0.2.0) - 2024-12-29

### BREAKING `try_resize_decode!`'s signature is changed. [#5](https://github.com/JuliaIO/ChunkCodecs.jl/pull/5)

`max_size` is a required positional argument instead of an optional keyword argument.

### Fixed

- When using a `Codec` as a decoder the `max_size` option was ignored. [#5](https://github.com/JuliaIO/ChunkCodecs.jl/pull/5)

## [v0.1.1](https://github.com/JuliaIO/ChunkCodecs.jl/tree/ChunkCodecCore-v0.1.1) - 2024-12-20

### Added

- Initial release
