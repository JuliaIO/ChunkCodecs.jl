# Constants and c wrapper functions ported to Julia from szlib.h https://github.com/MathisRosenhauer/libaec/blob/v1.1.3/include/szlib.h
const SZ_ALLOW_K13_OPTION_MASK = Int32(1)
const SZ_CHIP_OPTION_MASK = Int32(2)
const SZ_EC_OPTION_MASK = Int32(4)
const SZ_LSB_OPTION_MASK = Int32(8)
const SZ_MSB_OPTION_MASK = Int32(16)
const SZ_NN_OPTION_MASK = Int32(32)
const SZ_RAW_OPTION_MASK = Int32(128)

const SZ_OK = AEC_OK
const SZ_OUTBUFF_FULL = Cint(2)

const SZ_NO_ENCODER_ERROR = Cint(-1)
const SZ_PARAM_ERROR = AEC_CONF_ERROR
const SZ_MEM_ERROR = AEC_MEM_ERROR


const SZ_MAX_PIXELS_PER_BLOCK = 32
const SZ_MAX_BLOCKS_PER_SCANLINE = 128
const SZ_MAX_PIXELS_PER_SCANLINE = (SZ_MAX_BLOCKS_PER_SCANLINE) * (SZ_MAX_PIXELS_PER_BLOCK)

struct SZ_com_t
    options_mask::Cint
    bits_per_pixel::Cint
    pixels_per_block::Cint
    pixels_per_scanline::Cint
end

# The following is the original license info from szlib.h
#=
/**
 * @file szlib.h
 *
 * @section LICENSE
 * Copyright 2024 Mathis Rosenhauer, Moritz Hanke, Joerg Behrens, Luis Kornblueh
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above
 *    copyright notice, this list of conditions and the following
 *    disclaimer in the documentation and/or other materials provided
 *    with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * @section DESCRIPTION
 *
 * Adaptive Entropy Coding library
 *
 */
=#
