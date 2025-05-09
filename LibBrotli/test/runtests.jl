using Random: Random
using ChunkCodecCore: encode_bound, decoded_size_range, encode, decode
using ChunkCodecLibBrotli:
    ChunkCodecLibBrotli,
    BrotliCodec,
    BrotliEncodeOptions,
    BrotliDecodeOptions,
    BrotliDecodingError
using ChunkCodecTests: test_codec
using Test: @testset, @test_throws, @test
using Aqua: Aqua

Aqua.test_all(ChunkCodecLibBrotli; persistent_tasks = false)

Random.seed!(1234)

@testset "encode_bound" begin
    local a = last(decoded_size_range(BrotliEncodeOptions()))
    @test encode_bound(BrotliEncodeOptions(), a) == typemax(Int64) - 1
end
@testset "default" begin
    test_codec(BrotliCodec(), BrotliEncodeOptions(), BrotliDecodeOptions(); trials=5)
end
@testset "options" begin
    # quality should get clamped to 0 to 11
    @test BrotliEncodeOptions(; quality=-10).quality == 0
    @test BrotliEncodeOptions(; quality=12).quality == 11
    @test BrotliEncodeOptions(; quality=-1).quality == 0
    # Test invalid lgwin
    @test_throws ArgumentError BrotliEncodeOptions(; lgwin=9)
    @test_throws ArgumentError BrotliEncodeOptions(; lgwin=25)
    # Test invalid mode values
    @test_throws ArgumentError BrotliEncodeOptions(; mode=-1)
    @test_throws ArgumentError BrotliEncodeOptions(; mode=3)

    for quality in 0:11
        test_codec(BrotliCodec(), BrotliEncodeOptions(; quality), BrotliDecodeOptions(); trials=5)
    end

    # Test encoding/decoding with options
    # quality below 2 and lgwin below 14 seems to trigger the fallback compression
    for mode in [0, 1, 2]
        for quality in [0, 1, 2]
            for lgwin in [10, 20, 24]
                test_codec(BrotliCodec(), BrotliEncodeOptions(; quality, lgwin, mode), BrotliDecodeOptions(); trials=5)
            end
        end
    end
end
@testset "unexpected eof" begin
    local d = BrotliDecodeOptions()
    local u = [0x00, 0x01, 0x02]
    local c = encode(BrotliEncodeOptions(), u)
    @test decode(d, c) == u
    for i in 1:length(c)
        @test_throws BrotliDecodingError("unexpected end of stream") decode(d, c[1:i-1])
    end
end
@testset "Brotli doesn't support concatenation" begin
    e = BrotliEncodeOptions()
    d = BrotliDecodeOptions()
    u = [0x00, 0x01, 0x02]
    c = encode(e, u)
    @test decode(d, c) == u
    @test_throws BrotliDecodingError decode(d, u)
    c[begin] ⊻= 0xFF
    @test_throws BrotliDecodingError decode(d, c)
    @test_throws BrotliDecodingError("unexpected $(length(c)) bytes after stream") decode(d, [encode(e, u); c])
    @test_throws BrotliDecodingError("unexpected $(length(c)) bytes after stream") decode(d, [encode(e, u); encode(e, u)])
    @test_throws BrotliDecodingError("unexpected 1 bytes after stream") decode(d, [encode(e, u); 0x00])
end
@testset "errors" begin
    @test sprint(Base.showerror, BrotliDecodingError("test error message")) ==
        "BrotliDecodingError: test error message"
end
@testset "unit tests for unsafe_MakeUncompressedStream" begin
    for n in [0:200000; 2^20-2:2^20+2; 2^24-1:2^24+1]
        src = rand(UInt8, n)
        dst = zeros(UInt8, encode_bound(BrotliEncodeOptions(), Int64(n)))
        cconv_src = Base.cconvert(Ptr{UInt8}, src)
        cconv_dst = Base.cconvert(Ptr{UInt8}, dst)
        enc_size = GC.@preserve cconv_src cconv_dst let
            src_p = Base.unsafe_convert(Ptr{UInt8}, cconv_src)
            dst_p = Base.unsafe_convert(Ptr{UInt8}, cconv_dst)
            ChunkCodecLibBrotli.unsafe_MakeUncompressedStream(src_p, Int64(n), dst_p)
        end
        @test enc_size ≤ length(dst)
        resize!(dst, enc_size)
        @test decode(BrotliCodec(), dst; size_hint=n) == src
    end
end
