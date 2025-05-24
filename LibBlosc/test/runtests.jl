using Random: Random
using ChunkCodecLibBlosc:
    ChunkCodecLibBlosc,
    BloscCodec,
    BloscEncodeOptions,
    BloscDecodeOptions,
    BloscDecodingError
using ChunkCodecCore: decode, encode
using ChunkCodecTests: test_codec
using Test: @testset, @test_throws, @test
using Aqua: Aqua

Aqua.test_all(ChunkCodecLibBlosc; persistent_tasks = false)

Random.seed!(1234)

@testset "default" begin
    test_codec(BloscCodec(), BloscEncodeOptions(), BloscDecodeOptions(); trials=100)
end
@testset "typesize" begin
    for i in 1:50
        test_codec(BloscCodec(), BloscEncodeOptions(;typesize=i), BloscDecodeOptions(); trials=10)
    end
end
@testset "compressors" begin
    for clevel in 0:9
        for compressor in ["blosclz", "lz4", "lz4hc", "zlib", "zstd"]
            test_codec(BloscCodec(), BloscEncodeOptions(;compressor, clevel), BloscDecodeOptions(); trials=10)
        end
    end
end
@testset "invalid options" begin
    @test BloscEncodeOptions(;clevel=-1).clevel == 0
    @test BloscEncodeOptions(;clevel=100).clevel == 9
    # typesize can be anything, but out of the range it gets set to 1
    e = BloscEncodeOptions(;typesize=typemax(UInt128))
    @test e.typesize == 1
    e = BloscEncodeOptions(;typesize=0)
    @test e.typesize == 1
    e = BloscEncodeOptions(;typesize=-1)
    @test e.typesize == 1
    e = BloscEncodeOptions(;typesize=ChunkCodecLibBlosc.BLOSC_MAX_TYPESIZE)
    @test e.typesize == ChunkCodecLibBlosc.BLOSC_MAX_TYPESIZE
    e = BloscEncodeOptions(;typesize=ChunkCodecLibBlosc.BLOSC_MAX_TYPESIZE+1)
    @test e.typesize == 1
    @test_throws ArgumentError BloscEncodeOptions(;compressor="")
    @test_throws ArgumentError BloscEncodeOptions(;compressor="asfdgfsdgrwwea")
    @test_throws ArgumentError BloscEncodeOptions(;compressor="blosclz,")
    @test_throws ArgumentError BloscEncodeOptions(;compressor="blosclz\0")
end
@testset "compcode and compname" begin
    @test ChunkCodecLibBlosc.compcode("blosclz") == 0
    @test ChunkCodecLibBlosc.is_compressor_valid("blosclz")
    @test ChunkCodecLibBlosc.compname(0) == "blosclz"

    @test_throws ArgumentError ChunkCodecLibBlosc.compcode("sdaffads")
    @test !ChunkCodecLibBlosc.is_compressor_valid("sdaffads")
    @test_throws ArgumentError ChunkCodecLibBlosc.compcode("sdaffads")
    @test_throws ArgumentError ChunkCodecLibBlosc.compname(100)

    @test !ChunkCodecLibBlosc.is_compressor_valid("\0")
end
@testset "errors" begin
    # check BloscDecodingError prints the correct error message
    @test sprint(Base.showerror, BloscDecodingError(1)) ==
        "BloscDecodingError: blosc compressed buffer cannot be decoded, error code: 1"
    # check that a truncated buffer throws a BloscDecodingError
    u = UInt8[0x00]
    c = encode(BloscEncodeOptions(), u)
    @test_throws BloscDecodingError decode(BloscDecodeOptions(), c[1:end-1])
    @test_throws BloscDecodingError decode(BloscDecodeOptions(), UInt8[0x00])
    # check that a buffer with extra data throws a BloscDecodingError
    @test_throws BloscDecodingError decode(BloscDecodeOptions(), [c; 0x00;])
    # check corrupting LZ4 encoding throws a BloscDecodingError
    u = zeros(UInt8, 1000)
    c = encode(BloscEncodeOptions(), u)
    c[end-5] = 0x40
    @test_throws BloscDecodingError decode(BloscDecodeOptions(), c)
end
@testset "public" begin
    if VERSION >= v"1.11.0-DEV.469"
        for sym in (:is_compressor_valid, :compcode, :compname)
            @test Base.ispublic(ChunkCodecLibBlosc, sym)
        end
    end
end
