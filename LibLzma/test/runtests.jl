using Random: Random
using ChunkCodecCore: encode_bound, decoded_size_range, encode, decode
using ChunkCodecLibLzma:
    ChunkCodecLibLzma,
    XZCodec,
    XZEncodeOptions,
    XZDecodeOptions,
    LZMADecodingError,
    LZMA_CHECK_NONE,
    LZMA_CHECK_CRC32,
    LZMA_CHECK_CRC64,
    LZMA_CHECK_SHA256,
    LZMA_PRESET_EXTREME
using ChunkCodecTests: test_codec
using Test: @testset, @test_throws, @test
using Aqua: Aqua

Aqua.test_all(ChunkCodecLibLzma; persistent_tasks = false)

Random.seed!(1234)
@testset "default" begin
    test_codec(XZCodec(), XZEncodeOptions(), XZDecodeOptions(); trials=5)
end
@testset "preset options" begin
    @test_throws ArgumentError encode(XZEncodeOptions(; preset=UInt32(10)), UInt8[])
    for i in 0:9
        test_codec(XZCodec(), XZEncodeOptions(; preset=UInt32(i)), XZDecodeOptions(); trials=5)
    end
end
@testset "extreme preset" begin
    for i in 0:9
        test_codec(XZCodec(), XZEncodeOptions(; preset=UInt32(i) | LZMA_PRESET_EXTREME), XZDecodeOptions(); trials=5)
    end
end
@testset "check options" begin
    @test_throws ArgumentError XZEncodeOptions(; check=Int32(-1))
    @test_throws ArgumentError XZEncodeOptions(; check=Int32(16))
    for check in [LZMA_CHECK_NONE, LZMA_CHECK_CRC32, LZMA_CHECK_CRC64, LZMA_CHECK_SHA256]
        test_codec(XZCodec(), XZEncodeOptions(; check), XZDecodeOptions(); trials=5)
    end
end
@testset "concatenated streams" begin
    e = XZEncodeOptions()
    d = XZDecodeOptions()
    u1 = [0x00, 0x01, 0x02]
    u2 = [0x03, 0x04, 0x05, 0x06]
    u3 = UInt8[]
    c1 = encode(e, u1)
    c2 = encode(e, u2)
    c3 = encode(e, u3)
    # Two streams concatenated
    @test decode(d, [c1; c2]) == [u1; u2]
    # Three streams concatenated
    @test decode(d, [c1; c2; c1]) == [u1; u2; u1]
    # Empty stream in between
    @test decode(d, [c1; c3; c2]) == [u1; u2]
    # Multiple empty streams
    @test decode(d, [c3; c3; c1; c3; c2; c3]) == [u1; u2]
    # Just empty streams
    @test decode(d, [c3; c3; c3]) == UInt8[]
end
@testset "padding" begin
    e = XZEncodeOptions()
    d = XZDecodeOptions()
    u1 = [0x00, 0x01, 0x02]
    u2 = [0x03, 0x04, 0x05, 0x06]
    c1 = encode(e, u1)
    c2 = encode(e, u2)
    pad4 = zeros(UInt8, 4)
    pad8 = zeros(UInt8, 8)
    pad12 = zeros(UInt8, 12)
    # Padding at end of file (multiple of 4)
    @test decode(d, [c1; pad4]) == u1
    @test decode(d, [c1; pad8]) == u1
    @test decode(d, [c1; pad12]) == u1
    # Padding between streams (multiple of 4)
    @test decode(d, [c1; pad4; c2]) == [u1; u2]
    @test decode(d, [c1; pad8; c2]) == [u1; u2]
    @test decode(d, [c1; pad4; c2; pad4]) == [u1; u2]
    # Multiple padding sections
    @test decode(d, [c1; pad4; pad4; c2]) == [u1; u2]
    @test decode(d, [c1; pad4; c2; pad8]) == [u1; u2]
end
@testset "invalid padding" begin
    e = XZEncodeOptions()
    d = XZDecodeOptions()
    u = [0x00, 0x01, 0x02]
    c = encode(e, u)
    # Padding not a multiple of 4 at end
    @test_throws LZMADecodingError decode(d, [c; 0x00])
    @test_throws LZMADecodingError decode(d, [c; 0x00; 0x00])
    @test_throws LZMADecodingError decode(d, [c; 0x00; 0x00; 0x00])
    @test_throws LZMADecodingError decode(d, [c; zeros(UInt8, 5)])
    @test_throws LZMADecodingError decode(d, [c; zeros(UInt8, 6)])
    @test_throws LZMADecodingError decode(d, [c; zeros(UInt8, 7)])
    # Padding not a multiple of 4 between streams
    @test_throws LZMADecodingError decode(d, [c; 0x00; c])
    @test_throws LZMADecodingError decode(d, [c; 0x00; 0x00; c])
    @test_throws LZMADecodingError decode(d, [c; 0x00; 0x00; 0x00; c])
    @test_throws LZMADecodingError decode(d, [c; zeros(UInt8, 5); c])
    # Padding at beginning of file - not allowed
    @test_throws LZMADecodingError decode(d, [zeros(UInt8, 4); c])
    # Just padding (no stream) - should fail
    @test_throws LZMADecodingError decode(d, zeros(UInt8, 4))
    @test_throws LZMADecodingError decode(d, zeros(UInt8, 8))
end
@testset "unexpected eof" begin
    e = XZEncodeOptions()
    d = XZDecodeOptions()
    u = [0x00, 0x01, 0x02]
    c = encode(e, u)
    @test decode(d, c) == u
    for i in 1:length(c)
        @test_throws LZMADecodingError(ChunkCodecLibLzma.LZMA_BUF_ERROR) decode(d, c[1:i-1])
    end
    @test_throws LZMADecodingError decode(d, u)
    c[end] = 0x00
    @test_throws LZMADecodingError decode(d, c)
    @test_throws LZMADecodingError decode(d, [encode(e, u); c])
    @test_throws LZMADecodingError decode(d, [encode(e, u); 0x00])
end
@testset "errors" begin
    @test sprint(Base.showerror, LZMADecodingError(ChunkCodecLibLzma.LZMA_BUF_ERROR)) ==
        "LZMADecodingError: LZMA_BUF_ERROR: the compressed stream may be truncated or corrupt"
    @test sprint(Base.showerror, LZMADecodingError(ChunkCodecLibLzma.LZMA_DATA_ERROR)) ==
        "LZMADecodingError: LZMA_DATA_ERROR: data is corrupt"
    @test sprint(Base.showerror, LZMADecodingError(ChunkCodecLibLzma.LZMA_FORMAT_ERROR)) ==
        "LZMADecodingError: LZMA_FORMAT_ERROR: file format not recognized"
    @test sprint(Base.showerror, LZMADecodingError(ChunkCodecLibLzma.LZMA_OPTIONS_ERROR)) ==
        "LZMADecodingError: LZMA_OPTIONS_ERROR: reserved bits set in headers. Data corrupt, or upgrading liblzma may help"
    @test sprint(Base.showerror, LZMADecodingError(-100)) ==
        "LZMADecodingError: unknown lzma error code: -100"
end
