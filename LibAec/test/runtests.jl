using Random: Random
using ChunkCodecLibAec:
    ChunkCodecLibAec,
    SzipHDF5Codec,
    SzipHDF5EncodeOptions,
    SzipHDF5DecodeOptions,
    SzipDecodingError
using ChunkCodecCore: decode, encode
using ChunkCodecTests: test_codec
using Test: @testset, @test_throws, @test
using Aqua: Aqua

Aqua.test_all(ChunkCodecLibAec; persistent_tasks = false)

Random.seed!(1234)

@testset "options" begin
    for bits_per_pixel in [8, 16, 32, 64]
        for pixels_per_block in 2:2:32
            for pixels_per_scanline in rand(1:128*pixels_per_block, 10)
                c = SzipHDF5Codec(0, bits_per_pixel, pixels_per_block, pixels_per_scanline)
                @show c
                test_codec(c, SzipHDF5EncodeOptions(c), SzipHDF5DecodeOptions(c); trials=10)
            end
        end
    end
end
