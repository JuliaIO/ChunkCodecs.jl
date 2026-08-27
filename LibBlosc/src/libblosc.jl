# Constants and c wrapper functions ported to Julia from blosc.h https://github.com/Blosc/c-blosc/blob/3455c3810279ce709cf02f45beddbb31af418ab6/blosc/blosc.h

# The *_FORMAT symbols should be just 1-byte long
const BLOSC_VERSION_FORMAT   = Int64(2)   # Blosc format version, starting at 1

# Minimum header length
const BLOSC_MIN_HEADER_LENGTH = Int64(16)

# The maximum overhead during compression in bytes.  This equals to
#  BLOSC_MIN_HEADER_LENGTH now, but can be higher in future
#  implementations
const BLOSC_MAX_OVERHEAD = BLOSC_MIN_HEADER_LENGTH

# The maximum number of threads (for some static arrays)
const BLOSC_MAX_THREADS = Int64(256)

# Maximum typesize before considering source buffer as a stream of bytes
const BLOSC_MAX_TYPESIZE = Int64(255)   # Cannot be larger than 255

# Codes for shuffling
const BLOSC_NOSHUFFLE  = Int64(0)  # no shuffle
const BLOSC_SHUFFLE    = Int64(1)  # byte-wise shuffle
const BLOSC_BITSHUFFLE = Int64(2)  # bit-wise shuffle

# Codes for the different compressors shipped with Blosc
const BLOSC_BLOSCLZ = Int32(0)
const BLOSC_LZ4     = Int32(1)
const BLOSC_LZ4HC   = Int32(2)
# const BLOSC_SNAPPY  = Int32(3)  # snappy is not supported by the Blosc_jll build
const BLOSC_ZLIB    = Int32(4)
const BLOSC_ZSTD    = Int32(5)

const _COMP_CODE_NAME = (
    BLOSC_BLOSCLZ => "blosclz",
    BLOSC_LZ4 => "lz4",
    BLOSC_LZ4HC => "lz4hc",
    BLOSC_ZLIB => "zlib",
    BLOSC_ZSTD => "zstd",
)

"""
    is_compressor_valid(s::String)::Bool

Check if a compressor name is valid.
"""
function is_compressor_valid(s::String)
    for (code, name) in _COMP_CODE_NAME
        s == name && return true
    end
    return false
end

"""
    compcode(s::String)::Int32

Return a nonnegative integer code used by Blosc to identify the compressor.
Throws an `ArgumentError` if `s` is not the name of a supported algorithm.
"""
function compcode(s::String)::Int32
    for (code, name) in _COMP_CODE_NAME
        s == name && return code
    end
    throw(ArgumentError("unrecognized compressor $(repr(s))"))
end

"""
    compname(compcode::Integer)::String

Return the compressor name corresponding to the internal integer code used by Blosc.
Throws an `ArgumentError` if `compcode` is not a valid code.
"""
function compname(compcode::Integer)::String
    for (code, name) in _COMP_CODE_NAME
        compcode == code && return name
    end
    throw(ArgumentError("unrecognized compcode $compcode"))
end


# The following is the original license info from blosc.h and LICENSE.txt

#=====================================================================
  Blosc - Blocked Shuffling and Compression Library

  Author: Francesc Alted <francesc@blosc.org>

  See LICENSE.txt for details about copyright and rights to use.
======================================================================#

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
