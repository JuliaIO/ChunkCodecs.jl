# Constants and c wrapper functions ported to Julia from lz4.h and lz4hc.h
# https://github.com/lz4/lz4/blob/v1.10.0/lib/lz4.h
# https://github.com/lz4/lz4/blob/v1.10.0/lib/lz4hc.h

const LZ4HC_CLEVEL_MIN      =  Int32(2)
const LZ4HC_CLEVEL_DEFAULT  =  Int32(9)
const LZ4HC_CLEVEL_OPT_MIN  = Int32(10)
const LZ4HC_CLEVEL_MAX      = Int32(12)

# Note this is in lz4.c but I'm not sure why
const LZ4_ACCELERATION_MAX = Int32(65537)

const LZ4_MAX_INPUT_SIZE = Int64(0x7E000000)

const LZ4_MIN_CLEVEL = Int32(-(LZ4_ACCELERATION_MAX - Int32(1)))
const LZ4_MAX_CLEVEL = Int32(LZ4HC_CLEVEL_MAX)

# LZ4_COMPRESSBOUND assuming `src_size` is in 0:LZ4_MAX_INPUT_SIZE
function unsafe_lz4_compressbound(src_size::Int64)
    src_size + src_size÷Int64(255) + Int64(16)
end

# Combination of LZ4_compress_fast and LZ4_compress_HC
# Returns the number of bytes written to `dst` or 0 if compression fails.
function unsafe_lz4_compress(src::Ptr{UInt8}, dst::Ptr{UInt8}, src_size::Int32, dst_size::Int32, level::Int32)::Int32
    if level < LZ4HC_CLEVEL_MIN
        # Fast mode 
        # Convert level to acceleration using
        # int const acceleration = (level < 0) ? -level + 1 : 1;
        # from:
        # https://github.com/lz4/lz4/blob/6cf42afbea04c9ea6a704523aead273715001330/lib/lz4frame.c#L913
        acceleration = if level < 0
            -level + Int32(1)
        else
            Int32(1)
        end
        ccall(
            (:LZ4_compress_fast, liblz4), Cint,
            (Ptr{UInt8}, Ptr{UInt8}, Cint, Cint, Cint),
            src, dst, src_size, dst_size, acceleration
        )
    else
        # HC mode
        # level is normal
        ccall(
            (:LZ4_compress_HC, liblz4), Cint,
            (Ptr{UInt8}, Ptr{UInt8}, Cint, Cint, Cint),
            src, dst, src_size, dst_size, level
        )
    end
end

# Returns the number of bytes written to `dst` or a negative if decompression fails.
function unsafe_lz4_decompress(src::Ptr{UInt8}, dst::Ptr{UInt8}, src_size::Int32, dst_size::Int32)::Int32
    ccall(
        (:LZ4_decompress_safe, liblz4), Cint,
        (Ptr{UInt8}, Ptr{UInt8}, Cint, Cint),
        src, dst, src_size, dst_size
    )
end

# The following is the original license info from lz4.h and lz4hc.h

#=
 *  LZ4 - Fast LZ compression algorithm
 *  Header File
 *  Copyright (C) 2011-2023, Yann Collet.

   BSD 2-Clause License (http://www.opensource.org/licenses/bsd-license.php)

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are
   met:

       * Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
       * Redistributions in binary form must reproduce the above
   copyright notice, this list of conditions and the following disclaimer
   in the documentation and/or other materials provided with the
   distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

   You can contact the author at :
    - LZ4 homepage : http://www.lz4.org
    - LZ4 source repository : https://github.com/lz4/lz4
=#

#=
   LZ4 HC - High Compression Mode of LZ4
   Header File
   Copyright (C) 2011-2020, Yann Collet.
   BSD 2-Clause License (http://www.opensource.org/licenses/bsd-license.php)

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are
   met:

       * Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
       * Redistributions in binary form must reproduce the above
   copyright notice, this list of conditions and the following disclaimer
   in the documentation and/or other materials provided with the
   distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

   You can contact the author at :
   - LZ4 source repository : https://github.com/lz4/lz4
   - LZ4 public forum : https://groups.google.com/forum/#!forum/lz4c
=#
