using ChunkCodecCore: try_encode!, try_find_decoded_size, encode, decode
using ChunkCodecLibLz4
using ChunkCodecTests: test_codec
using Test: @testset, @test_throws, @test

@testset "default" begin
    test_codec(LZ4HDF5Codec(), LZ4HDF5EncodeOptions(), LZ4HDF5DecodeOptions(); trials=1000)
end
@testset "compressionLevel options" begin
    # Compression level is clamped
    for compressionLevel in [typemin(Int128); -30:13; typemax(Int128)]
        test_codec(
            LZ4HDF5Codec(),
            LZ4HDF5EncodeOptions(; compressionLevel),
            LZ4HDF5DecodeOptions();
            trials=3,
        )
    end
end
@testset "blockSize options" begin
    # out of range options
    for blockSize in Any[0, -1, typemin(Int32), ChunkCodecLibLz4.LZ4_MAX_INPUT_SIZE+1, Int64(2)^32]
        @test_throws ArgumentError LZ4HDF5EncodeOptions(;blockSize)
    end
    for blockSize in [1:6; 2^10; 2^20; 2^30; ChunkCodecLibLz4.LZ4_MAX_INPUT_SIZE;]
        test_codec(
            LZ4HDF5Codec(),
            LZ4HDF5EncodeOptions(; blockSize),
            LZ4HDF5DecodeOptions();
            trials=10,
        )
    end
end
@testset "unexpected eof" begin
    for blockSize in (1,2,5,999,1000,1001,10000)
        e = LZ4HDF5EncodeOptions(;blockSize)
        d = LZ4HDF5DecodeOptions()
        u = rand(UInt8, 1000)
        c = encode(e, u)
        @test decode(d, c) == u
        for i in 1:length(c)
            @test_throws LZ4DecodingError decode(d, c[1:i-1])
        end
        @test_throws LZ4DecodingError decode(d, [c; c;])
        @test_throws LZ4DecodingError decode(d, [c; 0x00;])
    end
end
@testset "decoding errors" begin
    e = LZ4HDF5EncodeOptions()
    d = LZ4HDF5DecodeOptions()
    # less than 12 bytes
    @test_throws LZ4DecodingError("unexpected end of input") try_find_decoded_size(d, UInt8[])
    @test_throws LZ4DecodingError("decoded size is negative") try_find_decoded_size(d, fill(0xFF,12))
    @test typemax(Int64) == try_find_decoded_size(d, [0x7F; fill(0xFF, 11);])
    # invalid block size
    @test_throws LZ4DecodingError("block size must be greater than zero") decode(d, [
        reinterpret(UInt8, [hton(Int64(0))]);
        reinterpret(UInt8, [hton(Int32(-1))]);
    ])
    @test_throws LZ4DecodingError("block size must be greater than zero") decode(d, [
        reinterpret(UInt8, [hton(Int64(0))]);
        reinterpret(UInt8, [hton(Int32(0))]);
    ])
    @test_throws LZ4DecodingError("unexpected $(1) bytes after stream") decode(d, [
        reinterpret(UInt8, [hton(Int64(0))]);
        reinterpret(UInt8, [hton(Int32(1))]);
        0x00;
    ])
    @test_throws LZ4DecodingError("unexpected end of input") decode(d, [
        reinterpret(UInt8, [hton(Int64(1))]);
        reinterpret(UInt8, [hton(Int32(16))]);
    ])
    @test_throws LZ4DecodingError("block compressed size must be greater than zero") decode(d, [
        reinterpret(UInt8, [hton(Int64(1))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(0))]);
    ])
    @test_throws LZ4DecodingError("unexpected end of input") decode(d, [
        reinterpret(UInt8, [hton(Int64(1))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(16))]);
    ])
    # edge case where decoded size is greater than block size
    # in this case decode with lz4 block
    @test [0x12, 0x34] == decode(d, [
        reinterpret(UInt8, [hton(Int64(2))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(3))]);
        [0x20, 0x12, 0x34];
    ])
    @test_throws LZ4DecodingError("src is malformed") decode(d, [
        reinterpret(UInt8, [hton(Int64(2))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(3))]);
        [0x30, 0x12, 0x34];
    ])
    @test_throws LZ4DecodingError("saved decoded size is not correct") decode(d, [
        reinterpret(UInt8, [hton(Int64(16))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(3))]);
        [0x20, 0x12, 0x34];
    ])
    @test_throws LZ4DecodingError("unexpected end of input") decode(d, [
        reinterpret(UInt8, [hton(Int64(3))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(3))]);
        [0x20, 0x12,];
    ])
end
@testset "encoding without enough space" begin
    e = LZ4HDF5EncodeOptions(; blockSize=32)
    d = LZ4HDF5DecodeOptions()
    u = rand(UInt8, 1024)
    c = zeros(UInt8, 1024+12+32*4)
    @test try_encode!(e, c, u) == length(c)
    @test decode(d, c) == u
    for i in 1:length(c)
        @test isnothing(try_encode!(e, c[1:i-1], u))
    end
    # zero length
    u = UInt8[]
    c = zeros(UInt8, 12)
    @test try_encode!(e, c, u) == length(c)
    @test decode(d, c) == u
    for i in 1:length(c)
        @test isnothing(try_encode!(e, c[1:i-1], u))
    end
    # one length
    u = UInt8[0x00]
    c = zeros(UInt8, 12+5)
    @test try_encode!(e, c, u) == length(c)
    @test decode(d, c) == u
    for i in 1:length(c)
        @test isnothing(try_encode!(e, c[1:i-1], u))
    end
end
