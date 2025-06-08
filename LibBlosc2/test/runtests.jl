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

#TODO @testset "default" begin
#TODO     test_codec(Blosc2Codec(), Blosc2EncodeOptions(), Blosc2DecodeOptions(); trials=100)
#TODO end
#TODO @testset "typesize" begin
#TODO     for i in 1:50
#TODO         test_codec(Blosc2Codec(), Blosc2EncodeOptions(; typesize=i), Blosc2DecodeOptions(); trials=10)
#TODO     end
#TODO end
#TODO @testset "compressors" begin
#TODO     for clevel in 0:9
#TODO         for compressor in ["blosclz", "lz4", "lz4hc", "zlib", "zstd"]
#TODO             test_codec(Blosc2Codec(), Blosc2EncodeOptions(; compressor, clevel), Blosc2DecodeOptions(); trials=10)
#TODO         end
#TODO     end
#TODO end
#TODO @testset "invalid options" begin
#TODO     @test Blosc2EncodeOptions(; clevel=-1).clevel == 0
#TODO     @test Blosc2EncodeOptions(; clevel=100).clevel == 9
#TODO     # typesize can be anything, but out of the range it gets set to 1
#TODO     e = Blosc2EncodeOptions(; typesize=typemax(UInt128))
#TODO     @test e.typesize == 1
#TODO     e = Blosc2EncodeOptions(; typesize=0)
#TODO     @test e.typesize == 1
#TODO     e = Blosc2EncodeOptions(; typesize=-1)
#TODO     @test e.typesize == 1
#TODO     e = Blosc2EncodeOptions(; typesize=ChunkCodecLibBlosc2.BLOSC_MAX_TYPESIZE)
#TODO     @test e.typesize == ChunkCodecLibBlosc2.BLOSC_MAX_TYPESIZE
#TODO     e = Blosc2EncodeOptions(; typesize=(ChunkCodecLibBlosc2.BLOSC_MAX_TYPESIZE+1))
#TODO     @test e.typesize == 1
#TODO     @test_throws ArgumentError Blosc2EncodeOptions(; compressor="")
#TODO     @test_throws ArgumentError Blosc2EncodeOptions(; compressor="asfdgfsdgrwwea")
#TODO     @test_throws ArgumentError Blosc2EncodeOptions(; compressor="blosclz,")
#TODO     @test_throws ArgumentError Blosc2EncodeOptions(; compressor="blosclz\0")
#TODO end
#TODO @testset "compcode and compname" begin
#TODO     @test ChunkCodecLibBlosc2.compcode("blosclz") == 0
#TODO     @test ChunkCodecLibBlosc2.is_compressor_valid("blosclz")
#TODO     @test ChunkCodecLibBlosc2.compname(0) == "blosclz"
#TODO 
#TODO     @test_throws ArgumentError ChunkCodecLibBlosc2.compcode("sdaffads")
#TODO     @test !ChunkCodecLibBlosc2.is_compressor_valid("sdaffads")
#TODO     @test_throws ArgumentError ChunkCodecLibBlosc2.compcode("sdaffads")
#TODO     @test_throws ArgumentError ChunkCodecLibBlosc2.compname(100)
#TODO 
#TODO     @test !ChunkCodecLibBlosc2.is_compressor_valid("\0")
#TODO end
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
