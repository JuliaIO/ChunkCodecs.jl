using Random: Random
using ChunkCodecLibBlosc2:
                           ChunkCodecLibBlosc2,
                           Blosc2Codec,
                           Blosc2EncodeOptions,
                           Blosc2DecodeOptions,
                           Blosc2DecodingError
using ChunkCodecCore: decode, encode
using ChunkCodecTests: test_codec
using Test: @testset, @test_throws, @test
using Aqua: Aqua

Aqua.test_all(ChunkCodecLibBlosc2; persistent_tasks=false)

Random.seed!(1234)

@testset "default" begin
    test_codec(Blosc2Codec(), Blosc2EncodeOptions(), Blosc2DecodeOptions(); trials=100)
end
@testset "typesize" begin
    for i in 1:50
        test_codec(Blosc2Codec(), Blosc2EncodeOptions(; typesize=i), Blosc2DecodeOptions(); trials=10)
    end
end
@testset "compressors" begin
    for clevel in 0:9
        for compressor in ["blosclz", "lz4", "lz4hc", "zlib", "zstd"]
            test_codec(Blosc2Codec(), Blosc2EncodeOptions(; compressor, clevel), Blosc2DecodeOptions(); trials=10)
        end
    end
end
@testset "large inputs" begin
    # We cannot really test large inputs (multi-Gigabyte) in a regular test.
    # We therefore simulate this with smaller inputs and a ridiculously small chunk size.
    u = reinterpret(UInt8, collect(float(1:(10 ^ 6))))
    e = Blosc2EncodeOptions(; clevel=9, doshuffle=2, typesize=sizeof(float(1)), chunksize=10^4, compressor="zstd")
    c = encode(e, u)
    u′ = decode(Blosc2DecodeOptions(), c)
    @test u′ == u
end
@testset "invalid options" begin
    @test Blosc2EncodeOptions(; clevel=-1).clevel == 0
    @test Blosc2EncodeOptions(; clevel=100).clevel == 9
    # typesize can be anything, but out of the range it gets set to 1
    e = Blosc2EncodeOptions(; typesize=typemax(UInt128))
    @test e.typesize == 1
    e = Blosc2EncodeOptions(; typesize=0)
    @test e.typesize == 1
    e = Blosc2EncodeOptions(; typesize=-1)
    @test e.typesize == 1
    e = Blosc2EncodeOptions(; typesize=ChunkCodecLibBlosc2.BLOSC_MAX_TYPESIZE)
    @test e.typesize == ChunkCodecLibBlosc2.BLOSC_MAX_TYPESIZE
    e = Blosc2EncodeOptions(; typesize=(ChunkCodecLibBlosc2.BLOSC_MAX_TYPESIZE+1))
    @test e.typesize == 1
    @test_throws ArgumentError Blosc2EncodeOptions(; compressor="")
    @test_throws ArgumentError Blosc2EncodeOptions(; compressor="asfdgfsdgrwwea")
    @test_throws ArgumentError Blosc2EncodeOptions(; compressor="blosclz,")
    @test_throws ArgumentError Blosc2EncodeOptions(; compressor="blosclz\0")
end
@testset "compcode and compname" begin
    @test ChunkCodecLibBlosc2.compcode("blosclz") == 0
    @test ChunkCodecLibBlosc2.is_compressor_valid("blosclz")
    @test ChunkCodecLibBlosc2.compname(0) == "blosclz"

    @test_throws ArgumentError ChunkCodecLibBlosc2.compcode("sdaffads")
    @test !ChunkCodecLibBlosc2.is_compressor_valid("sdaffads")
    @test_throws ArgumentError ChunkCodecLibBlosc2.compcode("sdaffads")
    @test_throws ArgumentError ChunkCodecLibBlosc2.compname(100)

    @test !ChunkCodecLibBlosc2.is_compressor_valid("\0")
end
@testset "errors" begin
    # check Blosc2DecodingError prints the correct error message
    @test sprint(Base.showerror, Blosc2DecodingError()) == "Blosc2DecodingError: blosc2 compressed buffer cannot be decoded"
    # check that a truncated buffer throws a Blosc2DecodingError
    u = UInt8[0x00]
    c = encode(Blosc2EncodeOptions(), u)
    @test_throws Blosc2DecodingError decode(Blosc2DecodeOptions(), c[1:(end - 1)])
    @test_throws Blosc2DecodingError decode(Blosc2DecodeOptions(), UInt8[0x00])
    # check that a buffer with extra data throws a Blosc2DecodingError
    @test_throws Blosc2DecodingError decode(Blosc2DecodeOptions(), [c; 0x00;])
    # check corrupting LZ4 encoding throws a Blosc2DecodingError
    u = zeros(UInt8, 1000)
    c = encode(Blosc2EncodeOptions(), u)

    c[end-5] = 0x40
    # Blosc2 does not detect this corruption. (Apparently it stores
    # unused and unchecked data in the trailer near the end of the
    # compressed data.) We check whether at least the decompressed
    # data are correct.
    # BROKEN @test_throws Blosc2DecodingError decode(Blosc2DecodeOptions(), c)
    @test decode(Blosc2DecodeOptions(), c) == u

    # There's more unused/unchecked data
    c[end-50] = 0x40
    # BROKEN @test_throws Blosc2DecodingError decode(Blosc2DecodeOptions(), c)
    @test decode(Blosc2DecodeOptions(), c) == u

    # Finally, this corruption has an effect
    c[end-100] = 0x40
    @test_throws Blosc2DecodingError decode(Blosc2DecodeOptions(), c)
end
@testset "public" begin
    if VERSION >= v"1.11.0-DEV.469"
        for sym in (:is_compressor_valid, :compcode, :compname)
            @test Base.ispublic(ChunkCodecLibBlosc2, sym)
        end
    end
end
