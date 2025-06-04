module ChunkCodecLibAec

using libaec_jll: libsz

using ChunkCodecCore:
    Codec,
    EncodeOptions,
    DecodeOptions,
    check_in_range,
    check_contiguous,
    DecodingError
import ChunkCodecCore:
    decode_options,
    try_decode!,
    try_encode!,
    encode_bound,
    try_find_decoded_size,
    decoded_size_range

export SzipHDF5Codec,
    SzipHDF5EncodeOptions,
    SzipHDF5DecodeOptions,
    SzipDecodingError

if VERSION >= v"1.11.0-DEV.469"
    eval(Meta.parse("public SZ_MSB_OPTION_MASK, SZ_NN_OPTION_MASK"))
end

# reexport ChunkCodecCore
using ChunkCodecCore: ChunkCodecCore, encode, decode
export ChunkCodecCore, encode, decode

include("libaec.jl")
include("libsz.jl")

const sziphdf5_docs = """
Szip HDF5 format compression using the libaec C library: https://gitlab.dkrz.de/k202009/libaec

This is the format used in HDF5 Filter ID: 4.

The maximum decoded size is about 4 GB.
"""

"""
    struct SzipHDF5Codec <: Codec
    SzipHDF5Codec(options_mask::Integer, bits_per_pixel::Integer, pixels_per_block::Integer, pixels_per_scanline::Integer)

$(sziphdf5_docs)

Warning: 

A `SzipHDF5Codec` can be used as an encoder or decoder.

# Fields

## `options_mask::Int32`: A bitwise or of the following constants.

- `SZ_MSB_OPTION_MASK`:
    input data is stored most significant byte first
    i.e. big endian.
- `SZ_NN_OPTION_MASK`:
    Set if preprocessor should be used.

## `bits_per_pixel::Int32`

Warning: Setting this to anything other than 8, 16, 32, or 64 puts additional restrictions on the decoded data.

The following rules apply for deducing storage size from sample size
(`bits_per_pixel`):

 **sample size**  | **storage size**
--- | ---
 1 -  8 bits  | 1 byte
 9 - 16 bits  | 2 bytes
17 - 32 bits  | 4 bytes
64      bits  | 8 bytes

If a sample requires less bits than the storage size provides, then
you have to make sure that unused bits are not set. Libaec does not
enforce this for performance reasons and will produce undefined output
if unused bits are set. All input data must be a multiple of the
storage size in bytes.

## `pixels_per_block::Int32`: A number in `2:2:32`

Smaller blocks allow the
compression to adapt more rapidly to changing source
statistics. Larger blocks create less overhead but can be less
efficient if source statistics change across the block.

## `pixels_per_scanline::Int32`: A number in `1:$(SZ_MAX_BLOCKS_PER_SCANLINE)*pixels_per_block`

Sets the reference sample interval in pixels. A large `pixels_per_scanline` will
improve performance and efficiency. It will also increase memory
requirements since internal buffering is based on `pixels_per_scanline` size. A smaller
`pixels_per_scanline` may be desirable in situations where errors could occur in the
transmission of encoded data and the resulting propagation of errors
in decoded data has to be minimized.

Setting `pixels_per_scanline` to a multiple of `pixels_per_block` will avoid extra overhead.
"""
struct SzipHDF5Codec <: Codec
    options_mask::Int32
    bits_per_pixel::Int32
    pixels_per_block::Int32
    pixels_per_scanline::Int32
end
decode_options(x::SzipHDF5Codec) = SzipHDF5DecodeOptions(;codec=x)

include("encode.jl")
include("decode.jl")

end # module ChunkCodecLibAec
