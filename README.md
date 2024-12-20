# ChunkCodecs (WIP)

[![CI](https://github.com/nhz2/ChunkCodecs.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/nhz2/ChunkCodecs.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/github/nhz2/ChunkCodecs.jl/graph/badge.svg?token=6SPQQCHA0B)](https://codecov.io/github/nhz2/ChunkCodecs.jl)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

## Warning: ChunkCodecs is currently a WIP and its API may drastically change at any time.
## Warning: There is not enough compatibility testing, so do not save important data using this package yet.

A consistent Julia interface for lossless encoding and decoding of bytes in memory.

## Repository directories

This monorepo holds a number of different Julia packages:

- `ChunkCodecCore`: defines the interface.
- `ChunkCodecTests`: defines tests for the interface.
- `ChunkCodecs`: uses all the other ChunkCodec* packages.

There are also a number of packages with glue code to implement the interface for various C libraries.

- `ChunkCodecLibBlosc`
- `ChunkCodecLibBzip2`
- `ChunkCodecLibLz4`
- `ChunkCodecLibZlib`
- `ChunkCodecLibZstd`

Each package contains basic tests.

There is also a `test` directory for slower compatibility tests.

## Simple encoding and decoding

### Encoding

Let say you want to encode some data into the gzip (.gz) format.

```julia-repl
julia> data = zeros(UInt8, 1000);
```

First load the package with the encoding options you want to use.
In this case `ChunkCodecLibZlib`

```julia-repl
julia> using ChunkCodecLibZlib
```

#### `EncodeOptions`

Next create a `GzipEncodeOptions` and select options to tune performance.

```julia-repl
julia> e = GzipEncodeOptions(;level=4)
GzipEncodeOptions(4)

julia> e isa ChunkCodecCore.EncodeOptions
true
```

Most of the parameters in an `EncodeOptions` are not needed to be able to
decode back to the original data.

The `Codec` object returned by `codec` has the meta data required for decoding.

```julia-repl
julia> gz_codec = codec(e)
GzipCodec()

julia> gz_codec isa ChunkCodecCore.Codec
true
```

`GzipCodec` is empty because gzip decoding doesn't require additional meta data.

You can look at the docstring `help?> GzipCodec` to learn more about the format.

#### `encode`

Finally you can encode the data:

```julia-repl
julia> gzipped_data = encode(e, data)
29-element Vector{UInt8}:
```

#### Requirements for `encode` to work
`encode` will throw an error if the following conditions aren't met.

1. The input data is stored in contiguous memory.
1. The input length is in `ChunkCodecCore.decoded_size_range(e)`

For example:
```julia-repl
julia> encode(ChunkCodecLibBlosc.BloscEncodeOptions(), @view(zeros(UInt8, 8)[1:2:end]))
ERROR: ArgumentError: vector is not contiguous in memory

julia> encode(ChunkCodecLibBlosc.BloscEncodeOptions(), zeros(UInt8, Int64(2)^32))
ERROR: ArgumentError: src_size ∈ 0:1:1073741824 must hold. Got
src_size => 4294967296

julia> encode(ChunkCodecLibBlosc.BloscEncodeOptions(;typesize=3), zeros(UInt8,7))
ERROR: ArgumentError: src_size ∈ 0:3:1073741823 must hold. Got
src_size => 7
```

### Decoding

Lets say you have trusted gzipped data you want to decode.

```julia-repl
julia> using ChunkCodecLibZlib

julia> data = zeros(UInt8, 1000);

julia> gzipped_data = encode(GzipEncodeOptions(;level=4), data);

julia> un_gzipped_data = decode(GzipCodec(), gzipped_data);

julia> un_gzipped_data == data
true
```

There are many potential issues when decoding untrusted data.

If decoding fails because the input data is not valid,
`decode` throws a `DecodingError`.

For example:
```julia-repl
julia> bad_gzipped_data = copy(gzipped_data);

julia> bad_gzipped_data[end-4] ⊻= 0x01;

julia> decode(GzipCodec(), bad_gzipped_data);
ERROR: LibzDecodingError: incorrect data check

julia> LibzDecodingError <: ChunkCodecCore.DecodingError
true
```

The encoded input may also contain a zip bomb.
The `max_size` keyword argument causes `decode` to throw a `ChunkCodecCore.DecodedSizeError` if decoding fails because the output size would be greater than `max_size`. By default `max_size` is `typemax(Int64)`.

For example:
```julia-repl
julia> decode(GzipCodec(), gzipped_data; max_size=100);
ERROR: DecodedSizeError: decoded size is greater than max size: 100
```

If you have a good idea of what the decoded size is, using the `size_hint` keyword argument
can greatly improve performance.

For example:
```julia-repl
julia> @time decode(GzipCodec(), gzipped_data; size_hint=1000, max_size=1000);
  0.000016 seconds (4 allocations: 8.227 KiB)

julia> @time decode(GzipCodec(), gzipped_data; max_size=1000);
  0.000018 seconds (9 allocations: 42.195 KiB)
```

## Multithreading

If `ChunkCodecCore.is_thread_safe(::Union{Codec, DecodeOptions, EncodeOptions})` returns `true` it is safe to use the options to encode or decode concurrently in multiple threads.

## Related packages

### Julia

https://github.com/JuliaIO/TranscodingStreams.jl

Filters in https://github.com/JuliaIO/HDF5.jl

### Python

https://github.com/cgohlke/imagecodecs

https://github.com/zarr-developers/numcodecs

