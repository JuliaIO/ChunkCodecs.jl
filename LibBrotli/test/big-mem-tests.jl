# This file contains tests that require a large amount of memory (at least 24 GB)
# and take a long time to run. The tests are designed to check the 
# compression and decompression functionality of the ChunkCodecLibBrotli package 
# with very large inputs. These tests are not run with CI

using ChunkCodecLibBrotli:
    ChunkCodecLibBrotli,
    BrotliCodec,
    BrotliEncodeOptions,
    encode,
    decode
using Test: @testset, @test

@testset "Big Memory Tests" begin
    Sys.WORD_SIZE == 64 || error("tests require 64 bit word size")
    @info "compressing zeros"
    for n in (2^32 - 1, 2^32, 2^32 +1, 2^33)
        @info "compressing"
        local c = encode(BrotliEncodeOptions(;quality=9), zeros(UInt8, n))
        @info "decompressing"
        local u = decode(BrotliCodec(), c; size_hint=n)
        c = nothing
        all_zero = all(iszero, u)
        len_n = length(u) == n
        @test all_zero && len_n
    end

    @info "compressing random"
    for n in (2^32 - 1, 2^32, 2^32 +1)
        local u = rand(UInt8, n)
        @info "compressing"
        local c = encode(BrotliEncodeOptions(;quality=9), u)
        @info "decompressing"
        local u2 = decode(BrotliCodec(), c; size_hint=n)
        c = nothing
        are_equal = u == u2
        @test are_equal
    end
end
