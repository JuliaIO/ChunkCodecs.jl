using Random: Random
using ChunkCodecLibAec:
    ChunkCodecLibAec,
    SzipHDF5Codec,
    SzipHDF5EncodeOptions,
    SzipHDF5DecodeOptions,
    SzipDecodingError,
    SZ_MSB_OPTION_MASK,
    SZ_NN_OPTION_MASK
using ChunkCodecCore: decode, encode
using ChunkCodecTests: test_codec, test_encoder_decoder
using Test: @testset, @test_throws, @test
using Aqua: Aqua

Aqua.test_all(ChunkCodecLibAec; persistent_tasks = false)

Random.seed!(1234)

@testset "round tripping" begin
    for options_mask in [Int32(0), SZ_MSB_OPTION_MASK, SZ_NN_OPTION_MASK, SZ_MSB_OPTION_MASK | SZ_NN_OPTION_MASK]
        for bits_per_pixel in [8, 16, 32, 64]
            for pixels_per_block in rand(2:2:32, 3)
                for pixels_per_scanline in rand(1:128*pixels_per_block, 3)
                    c = SzipHDF5Codec(;options_mask, bits_per_pixel, pixels_per_block, pixels_per_scanline)
                    test_codec(c, SzipHDF5EncodeOptions(c), SzipHDF5DecodeOptions(c); trials=5)
                end
            end
        end
    end
    # SzipHDF5Codec can be used as an encoder and decoder
    c = SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=8, pixels_per_block=8, pixels_per_scanline=16)
    test_encoder_decoder(c, c; trials=20)
end
@testset "non multiples of eight `bits_per_pixel`" begin
    for (T, bits) in [(UInt8, 1:7), (UInt16, 9:15), (UInt32, 17:31)]
        for bits_per_pixel in bits
            for big_endian in (false, true)
                c = SzipHDF5Codec(; options_mask=SZ_MSB_OPTION_MASK*big_endian, bits_per_pixel, pixels_per_block=32, pixels_per_scanline=128)
                # Important to not have unused bits set.
                # Libaec does not enforce this for performance reasons 
                # and will produce undefined output if unused bits are set.
                pixels = rand(T(0):T(UInt64(2)^bits_per_pixel - UInt64(1)), 1000)
                if big_endian
                    pixels = hton.(pixels)
                end
                u = reinterpret(UInt8, pixels)
                e = encode(c, u)
                @test u == decode(c, e)
                u = zeros(UInt8, 1000)
                e = encode(c, u)
                @test u == decode(c, e)
            end
        end
    end
end
@testset "errors" begin
    @testset "codec constructor" begin
        @test_throws ArgumentError SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=-1, pixels_per_block=32, pixels_per_scanline=128)
        @test_throws ArgumentError SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=0, pixels_per_block=32, pixels_per_scanline=128)
        @test_throws ArgumentError SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=33, pixels_per_block=32, pixels_per_scanline=128)
        @test_throws ArgumentError SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=8, pixels_per_block=-1, pixels_per_scanline=128)
        @test_throws ArgumentError SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=8, pixels_per_block=3, pixels_per_scanline=128)
        @test_throws ArgumentError SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=8, pixels_per_block=34, pixels_per_scanline=128)
        @test_throws ArgumentError SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=8, pixels_per_block=32, pixels_per_scanline=0)
        @test_throws ArgumentError SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=8, pixels_per_block=32, pixels_per_scanline=4097)
        @test_throws ArgumentError SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=8, pixels_per_block=2, pixels_per_scanline=257)
    end
    @testset "unexpected eof" begin
        c = SzipHDF5Codec(;options_mask=Int32(0), bits_per_pixel=8, pixels_per_block=4, pixels_per_scanline=4)
        u = [0x00, 0x01, 0x02, 0x03]
        e = encode(c, u)
        @test decode(c, e) == u
        for i in 1:length(e)
            @test_throws SzipDecodingError decode(c, e[1:i-1])
        end
    end
    @testset "printing errors" begin
        @test sprint(Base.showerror, SzipDecodingError("foo bar")) == "SzipDecodingError: foo bar"
    end
end
