# Constants and c wrapper functions ported to Julia from https://github.com/google/brotli/blob/v1.1.0/c

const BROTLI_MIN_WINDOW_BITS = 10
const BROTLI_MAX_WINDOW_BITS = 24

const BROTLI_WINDOW_GAP = 16
BROTLI_MAX_BACKWARD_LIMIT(W) = (Int64(1) << W) - BROTLI_WINDOW_GAP

const BROTLI_MIN_QUALITY = 0
const BROTLI_MAX_QUALITY = 11

# Default compression mode.
const BROTLI_MODE_GENERIC = 0
# Compression mode for UTF-8 formatted text input.
const BROTLI_MODE_TEXT = 1
# Compression mode used in WOFF 2.0.
const BROTLI_MODE_FONT = 2

# Options that are used here.
@enum BrotliEncoderParameter::Cint begin
    BROTLI_PARAM_MODE = 0
    BROTLI_PARAM_QUALITY = 1
    BROTLI_PARAM_LGWIN = 2
    BROTLI_PARAM_SIZE_HINT = 5
end

const BROTLI_OPERATION_PROCESS = Cint(0)
const BROTLI_OPERATION_FLUSH = Cint(1)
const BROTLI_OPERATION_FINISH = Cint(2)
const BROTLI_OPERATION_EMIT_METADATA = Cint(3)

# Just used to mark the type of pointers
mutable struct BrotliEncoderState end
mutable struct BrotliDecoderState end

function unsafe_BrotliEncoderSetParameter(state::Ptr{BrotliEncoderState}, param::BrotliEncoderParameter, value::UInt32)::Nothing
    res = @ccall libbrotlienc.BrotliEncoderSetParameter(
        state::Ptr{BrotliEncoderState},
        Integer(param)::Cint,
        value::UInt32,
    )::Cint
    if res != 1
        error("setting parameter $(param) to $(value)")
    end
    nothing
end

# Helper function ported from https://github.com/google/brotli/blob/v1.1.0/c/enc/encode.c#L1215
# /* Wraps data to uncompressed brotli stream with minimal window size.
#    |output| should point at region with at least encode_bound
#    addressable bytes.
#    Returns the length of stream. */
function unsafe_MakeUncompressedStream(input::Ptr{UInt8}, input_size::Int64, output::Ptr{UInt8})::Int64
    size::Int64 = input_size
    result::Int64 = 0
    offset::Int64 = 0
    if iszero(input_size)
        unsafe_store!(output, 0x06)
        return 1
    end
    unsafe_store!(output + result, 0x21) # window bits = 10, is_last = false
    result += 1
    unsafe_store!(output + result, 0x03) # empty metadata, padding
    result += 1
    while size > 0
        local nibbles::UInt32 = 0
        local chunk_size::UInt32
        local bits::UInt32
        chunk_size = (size > (Int64(1) << 24)) ? (UInt32(1) << 24) : size%UInt32
        if chunk_size > (UInt32(1) << 16)
            nibbles = (chunk_size > (UInt32(1) << 20)) ? 2 : 1
        end
        bits = (nibbles << 1) | ((chunk_size - UInt32(1)) << 3) | (UInt32(1) << (19 + 4 * nibbles))
        unsafe_store!(output + result, bits%UInt8)
        result += 1
        unsafe_store!(output + result, (bits >> 8)%UInt8)
        result += 1
        unsafe_store!(output + result, (bits >> 16)%UInt8)
        result += 1
        if nibbles == 2
            unsafe_store!(output + result, (bits >> 24)%UInt8)
            result += 1
        end
        @static if VERSION ≥ v"1.10"
            Libc.memcpy(output + result, input + offset, chunk_size)
        else
            unsafe_copyto!(output + result, input + offset, chunk_size)
        end
        result += chunk_size
        offset += chunk_size
        size -= chunk_size
    end
    unsafe_store!(output + result, 0x03)
    result += 1
    return result
end

const BROTLI_DECODER_RESULT_ERROR = Cint(0)
const BROTLI_DECODER_RESULT_SUCCESS = Cint(1)
const BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT = Cint(2)
const BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT = Cint(3)

# Range of memory allocation error codes.
const RANGE_BROTLI_DECODER_ERROR_ALLOC = -30:-21

# The following is the original license info from https://github.com/google/brotli/blob/v1.1.0/LICENSE

#=
Copyright (c) 2009, 2010, 2013-2016 by the Brotli Authors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
=#