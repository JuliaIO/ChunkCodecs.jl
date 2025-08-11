using ChunkCodecCore: encode_bound, decoded_size_range, encode, decode, DecodedSizeError, MaybeSize
using ChunkCodecLibLz4
using ChunkCodecTests: test_codec
using Test: @testset, @test_throws, @test

@testset "default" begin
    test_codec(LZ4NumcodecsCodec(), LZ4NumcodecsEncodeOptions(), LZ4NumcodecsDecodeOptions(); trials=100)
end
@testset "compressionLevel options" begin
    # Compression level is clamped
    for compressionLevel in [typemin(Int128); -30:13; typemax(Int128)]
        test_codec(
            LZ4NumcodecsCodec(),
            LZ4NumcodecsEncodeOptions(; compressionLevel),
            LZ4NumcodecsDecodeOptions();
            trials=3,
        )
    end
end
@testset "unexpected eof" begin
    e = LZ4NumcodecsEncodeOptions()
    d = LZ4NumcodecsDecodeOptions()
    u = [0x00, 0x01, 0x02]
    c = encode(e, u)
    @test decode(d, c) == u
    for i in 1:length(c)
        @test_throws LZ4DecodingError decode(d, c[1:i-1])
    end
    @test_throws LZ4DecodingError decode(d, u)
end
@testset "incorrect decoded size" begin
    e = LZ4NumcodecsEncodeOptions()
    d = LZ4NumcodecsDecodeOptions()
    c = [0xFF, 0xFF, 0xFF, 0xFF, 0x00]
    @test_throws LZ4DecodingError("decoded size is negative") decode(d, c)

    c = [0x00, 0x00, 0x00, 0x80, 0x00]
    @test_throws LZ4DecodingError("decoded size is negative") decode(d, c)

    c = [0x01, 0x00, 0x00, 0x00, 0x00]
    @test_throws LZ4DecodingError("saved decoded size is not correct") decode(d, c)

    c = [0x01, 0x00, 0x00, 0x00, 0x10, 0xaa]
    @test decode(d, c) == [0xaa]
end
@testset "max decoded size" begin
    d = LZ4NumcodecsDecodeOptions()
    c = UInt8[0xFF;0xFF;0xFF;0x7F; 0x1F;0x00;0x01;0x00;fill(0xFF,8421504);0x66;0x50;fill(0x00,5)]
    @test_throws DecodedSizeError(2^24, MaybeSize(-typemax(Int32))) decode(d, c; max_size=Int64(2)^24)
end
