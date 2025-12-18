# Constants and c wrapper functions ported to Julia from https://github.com/tukaani-project/xz/tree/v5.8.1/src/liblzma/api

#=
Return values used by several functions in liblzma
=#
const LZMA_OK = Cint(0)
const LZMA_STREAM_END = Cint(1)
const LZMA_NO_CHECK = Cint(2)
const LZMA_UNSUPPORTED_CHECK = Cint(3)
const LZMA_GET_CHECK = Cint(4)
const LZMA_MEM_ERROR = Cint(5)
const LZMA_MEMLIMIT_ERROR = Cint(6)
const LZMA_FORMAT_ERROR = Cint(7)
const LZMA_OPTIONS_ERROR = Cint(8)
const LZMA_DATA_ERROR = Cint(9)
const LZMA_BUF_ERROR = Cint(10)
const LZMA_PROG_ERROR = Cint(11)

#=
The 'action' argument for lzma_code()
=#
const LZMA_RUN = Cint(0)
const LZMA_SYNC_FLUSH = Cint(1)
const LZMA_FULL_FLUSH = Cint(2)
const LZMA_FULL_BARRIER = Cint(4)
const LZMA_FINISH = Cint(3)

#=
Custom functions for memory handling
=#
@assert typemax(Csize_t) ≥ typemax(Cint)

function lzma_alloc(::Ptr{Cvoid}, nmemb::Csize_t, size::Csize_t)::Ptr{Cvoid}
    # nmemb is always set to 1 and can be ignored
    @assert nmemb == 1
    ccall(:jl_malloc, Ptr{Cvoid}, (Csize_t,), size)
end
function lzma_free(::Ptr{Cvoid}, p::Ptr{Cvoid})
    ccall(:jl_free, Cvoid, (Ptr{Cvoid},), p)
end

struct lzma_allocator
    alloc::Ptr{Cvoid}
    free::Ptr{Cvoid}
    opaque::Ptr{Cvoid}
end

function default_allocator()
    lzma_allocator(
        @cfunction(lzma_alloc, Ptr{Cvoid}, (Ptr{Cvoid}, Csize_t, Csize_t)),
        @cfunction(lzma_free, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid})),
        C_NULL,
    )
end

mutable struct lzma_stream
    next_in::Ptr{UInt8}
    avail_in::Csize_t
    total_in::UInt64

    next_out::Ptr{UInt8}
    avail_out::Csize_t
    total_out::UInt64

    allocator::Ptr{lzma_allocator}
    internal::Ptr{Cvoid}

    reserved_ptr1::Ptr{Cvoid}
    reserved_ptr2::Ptr{Cvoid}
    reserved_ptr3::Ptr{Cvoid}
    reserved_ptr4::Ptr{Cvoid}

    seek_pos::UInt64

    reserved_int2::UInt64
    reserved_int3::Csize_t
    reserved_int4::Csize_t
    reserved_enum1::Cint
    reserved_enum2::Cint

    function lzma_stream()
        new(
            C_NULL, 0, 0,
            C_NULL, 0, 0,
            C_NULL,#default_allocator_ptr,
            C_NULL,
            C_NULL, C_NULL, C_NULL, C_NULL,
            0, 0, 0, 0,
            0, 0,
        )
    end
end

#=
Type of the integrity check (Check ID)
=#
"""
    const LZMA_CHECK_NONE = Cint(0)

No Check is calculated.

Size of the Check field: 0 bytes
"""
const LZMA_CHECK_NONE = Cint(0)

"""
    const LZMA_CHECK_CRC32 = Cint(1)

CRC32 using the polynomial from the IEEE 802.3 standard

Size of the Check field: 4 bytes
"""
const LZMA_CHECK_CRC32 = Cint(1)

"""
    const LZMA_CHECK_CRC64 = Cint(4)

CRC64 using the polynomial from the ECMA-182 standard

Size of the Check field: 8 bytes
"""
const LZMA_CHECK_CRC64 = Cint(4)

"""
    const LZMA_CHECK_SHA256 = Cint(10)

SHA-256

Size of the Check field: 32 bytes
"""
const LZMA_CHECK_SHA256 = Cint(10)

"""
const LZMA_CHECK_ID_MAX = Cint(15)

Maximum valid Check ID

The .xz file format specification specifies 16 Check IDs (0-15). Some
of them are only reserved, that is, no actual Check algorithm has been
assigned. When decoding, liblzma still accepts unknown Check IDs for
future compatibility. If a valid but unsupported Check ID is detected,
liblzma can indicate a warning; see the flags LZMA_TELL_NO_CHECK,
LZMA_TELL_UNSUPPORTED_CHECK, and LZMA_TELL_ANY_CHECK.
"""
const LZMA_CHECK_ID_MAX = Cint(15)

"""
    lzma_check_is_supported(check::Cint)::Bool

Test if the given Check ID is supported.

LZMA_CHECK_NONE and LZMA_CHECK_CRC32 are always supported (even if
liblzma is built with limited features).

It is safe to call this with a value that is not in the range [0, 15];
in that case the return value is always false.

# Arguments
- `check`: Check ID

# Returns
- `true` if Check ID is supported by this liblzma build.
- `false` otherwise.
"""
function lzma_check_is_supported(check::Cint)::Bool
    @ccall liblzma.lzma_check_is_supported(check::Cint)::Bool
end

const LZMA_PRESET_DEFAULT = UInt32(6)

"""
    const LZMA_PRESET_LEVEL_MASK = UInt32(0x1F)

Mask for preset level

This is useful only if you need to extract the level from the preset
variable. That should be rare.
"""
const LZMA_PRESET_LEVEL_MASK = UInt32(0x1F)

"""
    const LZMA_PRESET_EXTREME = UInt32(1)<<31

Extreme compression preset

This flag modifies the preset to make the encoding significantly slower
while improving the compression ratio only marginally. This is useful
when you don't mind spending time to get as small result as possible.

This flag doesn't affect the memory usage requirements of the decoder (at
least not significantly). The memory usage of the encoder may be increased
a little but only at the lowest preset levels (0-3).
"""
const LZMA_PRESET_EXTREME = UInt32(1)<<31

#=
This flag enables decoding of concatenated files with file formats that
allow concatenating compressed files as is. From the formats currently
supported by liblzma, only the .xz and .lz formats allow concatenated
files. Concatenated files are not allowed with the legacy .lzma format.

This flag also affects the usage of the 'action' argument for lzma_code().
When LZMA_CONCATENATED is used, lzma_code() won't return LZMA_STREAM_END
unless LZMA_FINISH is used as 'action'. Thus, the application has to set
LZMA_FINISH in the same way as it does when encoding.

If LZMA_CONCATENATED is not used, the decoders still accept LZMA_FINISH
as 'action' for lzma_code(), but the usage of LZMA_FINISH isn't required.
=#
const LZMA_CONCATENATED = UInt32(0x08)


# The following is the original license info from lzma.h and LICENSE

#= header of lzma.h
/* SPDX-License-Identifier: 0BSD */

/**
 * \file        api/lzma.h
 * \brief       The public API of liblzma data compression library
 * \mainpage
 *
 * liblzma is a general-purpose data compression library with a zlib-like API.
 * The native file format is .xz, but also the old .lzma format and raw (no
 * headers) streams are supported. Multiple compression algorithms (filters)
 * are supported. Currently LZMA2 is the primary filter.
 *
 * liblzma is part of XZ Utils <https://tukaani.org/xz/>. XZ Utils
 * includes a gzip-like command line tool named xz and some other tools.
 * XZ Utils is developed and maintained by Lasse Collin.
 *
 * Major parts of liblzma are based on code written by Igor Pavlov,
 * specifically the LZMA SDK <https://7-zip.org/sdk.html>.
 *
 * The SHA-256 implementation in liblzma is based on code written by
 * Wei Dai in Crypto++ Library <https://www.cryptopp.com/>.
 *
 * liblzma is distributed under the BSD Zero Clause License (0BSD).
 */

/*
 * Author: Lasse Collin
 */
=#

#= contents of COPYING.0BSD
Permission to use, copy, modify, and/or distribute this
software for any purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL
THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
=#