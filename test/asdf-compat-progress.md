# ASDF compatibility tests: progress

Goal: test that ChunkCodecs.jl codecs can read and write ASDF compressed blocks
the same way the python [asdf](https://github.com/asdf-format/asdf) library and
[asdf-compression](https://github.com/asdf-format/asdf-compression) do.
Modelled on `hdf5-compat.jl` / `hdf5_helpers.jl`.

Run with:

```sh
julia --project=test -e 'import Pkg; Pkg.update()'
julia --project=test test/asdf-compat.jl
```

Takes about 4 minutes.

## Steps

- [x] Read the ASDF file layout spec
      <https://www.asdf-format.org/projects/asdf-standard/en/latest/file_layout.html>
- [x] `test/asdf_helpers.jl`: `make_asdf` builds a minimal ASDF file around one encoded chunk
- [x] `test/asdf_helpers.jl`: `read_asdf_blocks` parses the blocks of an ASDF file written by python
- [x] Add python deps to `test/CondaPkg.toml` (`asdf`, `asdf-compression`, `blosc`, `lz4`, `zstandard`)
- [x] `test/asdf-compat.jl`: Julia encode -> python asdf decode
- [x] `test/asdf-compat.jl`: python asdf encode -> Julia decode

## Compression labels

| Label  | Source           | Python encoder               | ChunkCodecs.jl codec                  | Status  |
|--------|------------------|------------------------------|---------------------------------------|---------|
| `zlib` | asdf builtin     | `zlib.compress`              | `ChunkCodecLibZlib.ZlibCodec`         | passing |
| `bzp2` | asdf builtin     | `bz2.compress`               | `ChunkCodecLibBzip2.BZ2Codec`         | passing |
| `blsc` | asdf-compression | `blosc.compress`             | `ChunkCodecLibBlosc.BloscCodec`       | passing |
| `lz4f` | asdf-compression | `lz4.frame.compress`         | `ChunkCodecLibLz4.LZ4FrameCodec`      | passing |
| `zstd` | asdf-compression | `zstandard` (level, threads) | `ChunkCodecLibZstd.ZstdCodec`         | passing |
| `lz4`  | asdf builtin     | framed `lz4.block.compress`  | none yet                              | skipped |
| `bls2` | asdf-compression (git main only) | `blosc2.compress` | none, blosc2 is not in ChunkCodecs.jl | skipped |

## Notes

- The minimal file written by `make_asdf` uses `#ASDF_STANDARD 1.5.0`, `core/asdf-1.1.0`, and
  `core/ndarray-1.0.0`, one block with an MD5 checksum, and a block index.
  Python asdf reads it with `validate_checksums=true` and `AsdfWarning`s turned into errors.
- Python asdf 5.4.0 writes `#ASDF_STANDARD 1.6.0` with `core/ndarray-1.1.0`, always writes MD5
  checksums of the encoded block data, and pads 3-byte labels with `\0` (for example `lz4\0`).
- Builtin asdf `lz4` format: the data is split into `compression_block_size` byte pieces
  (default 4 MiB). Each piece is `lz4.block.compress` output (a 4-byte little-endian decoded size
  followed by a raw LZ4 block, like `LZ4NumcodecsCodec`), prefixed by its encoded length as a big-endian `UInt32`.
- The `asdf-compression` 0.1.0 release on PyPI has `blsc`, `lz4f`, and `zstd`. `bls2` only exists on git main.
- ASDF.jl 2.0.2 uses `lz4\0` for both the builtin framed LZ4 format and the LZ4 frame format.
  Python asdf-compression uses `lz4f` for the LZ4 frame format.
