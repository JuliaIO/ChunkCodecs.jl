# Code ported from the libbitshuffle C library <https://github.com/kiyo-masui/bitshuffle>
# There is a copy of the C library's license at the end of this file.
module ChunkCodecBitshuffle

# Transpose 8x8 bit array packed into `x`
# The most significant bit of x is the upper left corner of the matrix
function trans_bit_8x8(x::UInt64)::UInt64
    t = (x ⊻ (x >> 7)) & 0x00AA00AA00AA00AA
    x = x ⊻ t ⊻ (t << 7)
    t = (x ⊻ (x >> 14)) & 0x0000CCCC0000CCCC
    x = x ⊻ t ⊻ (t << 14)
    t = (x ⊻ (x >> 28)) & 0x00000000F0F0F0F0
    x ⊻ t ⊻ (t << 28)
end

# Transpose 8x8 bit array along the diagonal from upper right to lower left
# The most significant bit of x is the upper left corner of the matrix
function trans_bit_8x8_be(x::UInt64)::UInt64
    t = (x ⊻ (x >> 9)) & 0x0055005500550055
    x = x ⊻ t ⊻ (t << 9)
    t = (x ⊻ (x >> 18)) & 0x0000333300003333
    x = x ⊻ t ⊻ (t << 18)
    t = (x ⊻ (x >> 36)) & 0x000000000F0F0F0F
    x ⊻ t ⊻ (t << 36)
end

function bshuf_bitshuffle(in::AbstractVector{UInt8}, out::AbstractVector{UInt8}, elem_size::Int64, block_size::Int64)
    # bshuf_blocked_wrap_fun
end



end # module ChunkCodecBitshuffle

#= License file for C library https://www.github.com/kiyo-masui/bitshuffle
Bitshuffle - Filter for improving compression of typed binary data.

Copyright (c) 2014 Kiyoshi Masui (kiyo@physics.ubc.ca)

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
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
=#