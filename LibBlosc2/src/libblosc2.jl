# Constants and C wrapper functions ported to Julia from blosc2.h https://github.com/Blosc/c-blosc2/blob/5fcd6fbf9ffcf613fabdb1eb3a90eeb12f7c04fe/include/blosc2.h

################################################################################
# Constants

# [175]
# Extended header length (Blosc2, see README_HEADER)
const BLOSC_EXTENDED_HEADER_LENGTH = 32
const BLOSC2_MAX_OVERHEAD = BLOSC_EXTENDED_HEADER_LENGTH
const BLOSC_MAX_TYPESIZE = Int(typemax(UInt8))

# [222]
const BLOSC2_MAX_FILTERS = 6

# [242] Codes for filters.
# No shuffle (for compatibility with Blosc1).
const BLOSC_NOSHUFFLE = 0
# No filter.
const BLOSC_NOFILTER = 0
const BLOSC_SHUFFLE = 1
# Byte-wise shuffle. `filters_meta` does not have any effect here.
const BLOSC_BITSHUFFLE = 2
# Bit-wise shuffle. `filters_meta` does not have any effect here.
const BLOSC_DELTA = 3
# Delta filter. `filters_meta` does not have any effect here.
const BLOSC_TRUNC_PREC = 4
# Truncate mantissa precision.
# Positive values in `filters_meta` will keep bits; negative values will zero bits.
const BLOSC_LAST_FILTER = 5

# [314]  Codes for the different compressors shipped with Blosc
const BLOSC_BLOSCLZ = 0
const BLOSC_LZ4 = 1
const BLOSC_LZ4HC = 2
const BLOSC_ZLIB = 4
const BLOSC_ZSTD = 5
const BLOSC_LAST_CODEC = 6

# [396] Split mode for blocks.
const BLOSC_ALWAYS_SPLIT = 1
const BLOSC_NEVER_SPLIT = 2
const BLOSC_AUTO_SPLIT = 3
const BLOSC_FORWARD_COMPAT_SPLIT = 4

# [1641]
const BLOSC2_MAX_METALAYERS = 16
const BLOSC2_MAX_VLMETALAYERS = 8 * 1024

################################################################################
# Types

"""
    struct Blosc2CParams

The parameters for creating a context for compression purposes.
"""
struct Blosc2CParams
    # The compressor codec.
    compcode::UInt8
    # The metadata for the compressor codec.
    compcode_meta::UInt8
    # The compression level (5).
    clevel::UInt8
    # Use dicts or not when compressing (only for ZSTD).
    use_dict::Cint
    # The type size (8).
    typesize::Int32
    # The number of threads to use internally (1).
    nthreads::Int16
    # The requested size of the compressed blocks (0 means automatic).
    blocksize::Int32
    # Whether the blocks should be split or not.
    splitmode::Int32
    # The associated schunk, if any (NULL).
    schunk::Ptr{Cvoid}
    # The (sequence of) filters.
    filters::NTuple{BLOSC2_MAX_FILTERS,UInt8}
    # The metadata for filters.
    filters_meta::NTuple{BLOSC2_MAX_FILTERS,UInt8}
    # The prefilter function.
    prefilter::Ptr{Cvoid}       # blosc2_prefilter_fn
    # The prefilter parameters.
    preparams::Ptr{Cvoid}       # blosc2_prefilter_params*
    # Tune configuration.
    tuner_params::Ptr{Cvoid}
    # The tuner id.
    tuner_id::Cint
    # Whether the codec is instrumented or not
    instr_codec::UInt8          # bool
    # User defined parameters for the codec
    codec_params::Ptr{Cvoid}
    # User defined parameters for the filters
    filter_params::NTuple{BLOSC2_MAX_FILTERS,Ptr{Cvoid}}
end
Blosc2CParams() = @ccall libblosc2.blosc2_get_blosc2_cparams_defaults()::Blosc2CParams

"""
    struct Blosc2DParams

The parameters for creating a context for decompression purposes.
"""
struct Blosc2DParams
    # The number of threads to use internally (1).
    nthreads::Int16
    # The associated schunk, if any (NULL).
    schunk::Ptr{Cvoid}
    # The postfilter function.
    postfilter::Ptr{Cvoid}   # blosc2_postfilter_fn
    # The postfilter parameters.
    postparams::Ptr{Cvoid}   # blosc2_postfilter_params*
end
Blosc2DParams() = @ccall libblosc2.blosc2_get_blosc2_dparams_defaults()::Blosc2DParams

"""
    struct Blosc2IO

Input/Output parameters.
"""
struct Blosc2IO
    id::UInt8
    # The IO identifier.
    name::Cstring
    # The IO parameters.
    params::Ptr{Cvoid}
end
Blosc2IO() = @ccall libblosc2.blosc2_get_blosc2_io_defaults()::Blosc2IO

"""
    struct Blosc2Storage

This struct is meant for holding storage parameters for a
for a blosc2 container, allowing to specify, for example, how to interpret
the contents included in the schunk.
"""
struct Blosc2Storage
    # Whether the chunks are contiguous or sparse.
    contiguous::UInt8   # bool
    # The path for persistent storage. If NULL, that means in-memory.
    urlpath::Cstring
    # The compression params when creating a schunk.
    # If NULL, sensible defaults are used depending on the context.
    cparams::Ptr{Blosc2CParams}
    # The decompression params when creating a schunk.
    # If NULL, sensible defaults are used depending on the context.
    dparams::Ptr{Blosc2DParams}
    # Input/output backend.
    io::Ptr{Blosc2IO}
end
Blosc2Storage() = @ccall libblosc2.blosc2_get_blosc2_storage_defaults()::Blosc2Storage

struct Blosc2Metalayer
    # The metalayer identifier for Blosc client (e.g. Blosc2 NDim).
    name::Cstring
    # The serialized (msgpack preferably) content of the metalayer.
    content::Ptr{UInt8}
    # The length in bytes of the content.
    content_len::Int32
end

"""
    struct Blosc2SChunk

This struct is the standard container for Blosc 2 compressed data.
"""
struct Blosc2SChunk
    version::UInt8
    # The default compressor. Each chunk can override this.
    compcode::UInt8
    # The default compressor metadata. Each chunk can override this.
    compcode_meta::UInt8
    # The compression level and other compress params.
    clevel::UInt8
    # The split mode.
    splitmode::UInt8
    # The type size.
    typesize::Int32
    # The requested size of the compressed blocks (0; meaning automatic).
    blocksize::Int32
    # Size of each chunk. 0 if not a fixed chunksize.
    chunksize::Int32
    # The (sequence of) filters.  8-bit per filter.
    filters::NTuple{BLOSC2_MAX_FILTERS,UInt8}
    # Metadata for filters. 8-bit per meta-slot.
    filters_meta::NTuple{BLOSC2_MAX_FILTERS,UInt8}
    # Number of chunks in super-chunk.
    nchunks::Int64
    # The current chunk that is being accessed
    current_nchunk::Int64
    # The data size (uncompressed).
    nbytes::Int64
    # The data size + chunks header size (compressed).
    cbytes::Int64
    # Pointer to chunk data pointers buffer.
    data::Ptr{Ptr{UInt8}}
    # Length of the chunk data pointers buffer.
    data_len::Csize_t
    # Pointer to storage info.
    storage::Ptr{Blosc2Storage}
    # Pointer to frame used as store for chunks.
    frame::Ptr{Cvoid}  # blosc2_frame*
    # Context for the thread holder. NULL if not acquired.
    # ctx::Ptr{UInt8}
    # Context for compression
    cctx::Ptr{Cvoid} # blosc2_context*
    # Context for decompression.
    dctx::Ptr{Cvoid} # blosc2_context*
    # The array of metalayers.
    metalayers::NTuple{BLOSC2_MAX_METALAYERS,Ptr{Blosc2Metalayer}}
    # The number of metalayers in the super-chunk
    nmetalayers::UInt16
    # The array of variable-length metalayers.
    vlmetalayers::NTuple{BLOSC2_MAX_VLMETALAYERS,Ptr{Blosc2Metalayer}}
    # The number of variable-length metalayers.
    nvlmetalayers::Int16
    # Tune configuration.
    tuner_params::Ptr{Cvoid}
    # Id for tuner
    tuner_id::Cint
    # The ndim (mainly for ZFP usage)
    ndim::Int8
    # The blockshape (mainly for ZFP usage)
    blockshape::Ptr{Int64}
end

################################################################################
# Functions

"""
    is_compressor_valid(s::AbstractString)::Bool

Check if a compressor name is valid.
"""
function is_compressor_valid(s::AbstractString)
    '\0' ∈ s && return false
    code = @ccall libblosc2.blosc2_compname_to_compcode(s::Cstring)::Cint
    return code >= 0
end

"""
    compcode(s::AbstractString)::Int

Return a nonnegative integer code used internally by Blosc to identify the compressor.
Throws an `ArgumentError` if `s` is not the name of a supported algorithm.
"""
function compcode(s::AbstractString)
    code = @ccall libblosc2.blosc2_compname_to_compcode(s::Cstring)::Cint
    code == -1 && throw(ArgumentError("unrecognized compressor $(repr(s))"))
    return Int(code)
end

"""
    compname(compcode::Integer)::String

Return the compressor name corresponding to the internal integer code used by Blosc.
Throws an `ArgumentError` if `compcode` is not a valid code.
"""
function compname(compcode::Integer)
    name = Ref{Ptr{UInt8}}()
    code = @ccall libblosc2.blosc2_compcode_to_compname(compcode::Cint, name::Ref{Ptr{UInt8}})::Cint
    code == -1 && throw(ArgumentError("unrecognized compcode $compcode"))
    name = name[]
    return unsafe_string(name)
end

################################################################################

# The following is the original license info from blosc2.h and LICENSE.txt

#=
/*********************************************************************
  Blosc - Blocked Shuffling and Compression Library

  Copyright (c) 2021  Blosc Development Team <blosc@blosc.org>
  https://blosc.org
  License: BSD 3-Clause (see LICENSE.txt)

  See LICENSE.txt for details about copyright and rights to use.
**********************************************************************/
=#

#= contents of LICENSE.txt
BSD License

For Blosc - A blocking, shuffling and lossless compression library

Copyright (c) 2009-2018 Francesc Alted <francesc@blosc.org>
Copyright (c) 2019-present Blosc Development Team <blosc@blosc.org>

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

 * Neither the name Francesc Alted nor the names of its contributors may be used
   to endorse or promote products derived from this software without specific
   prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
=#
