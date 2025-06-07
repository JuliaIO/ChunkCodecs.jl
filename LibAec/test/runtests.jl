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
using ChunkCodecTests: test_codec
using Test: @testset, @test_throws, @test
using Aqua: Aqua

Aqua.test_all(ChunkCodecLibAec; persistent_tasks = false)

Random.seed!(1234)

@testset "options" begin
    for options_mask in [Int32(0), SZ_MSB_OPTION_MASK, SZ_NN_OPTION_MASK, SZ_MSB_OPTION_MASK | SZ_NN_OPTION_MASK]
        for bits_per_pixel in [8, 16, 32, 64]
            for pixels_per_block in rand(2:2:32, 3)
                for pixels_per_scanline in rand(1:128*pixels_per_block, 3)
                    c = SzipHDF5Codec(; options_mask=0, bits_per_pixel, pixels_per_block, pixels_per_scanline)
                    test_codec(c, SzipHDF5EncodeOptions(c), SzipHDF5DecodeOptions(c); trials=5)
                end
            end
        end
    end
end
