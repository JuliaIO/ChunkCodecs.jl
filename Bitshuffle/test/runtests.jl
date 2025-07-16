using Random: Random
using ChunkCodecBitshuffle:
    ChunkCodecBitshuffle,
    trans_bit_elem!,
    untrans_bit_elem!,
    BitshuffleCodec,
    BitshuffleEncodeOptions,
    BitshuffleDecodeOptions,
    BitshuffleCompressCodec,
    BitshuffleCompressEncodeOptions,
    BitshuffleCompressDecodeOptions
using ChunkCodecCore: ChunkCodecCore, decode, encode
using ChunkCodecTests: test_codec, test_encoder_decoder
using ChunkCodecLibLz4
using ChunkCodecLibZstd
using Test: @testset, @test_throws, @test
using Aqua: Aqua
using bitshuffle_jll: libbitshuffle

Aqua.test_all(ChunkCodecBitshuffle; persistent_tasks = false)

Random.seed!(1234)

# helper functions
# Take a matrix of UInt8, and create a BitMatrix
# The output should have the same number of columns as the input, but 8x as many rows.
# The least significant bit of the first byte goes in the top left of the output matrix.
function make_bitmatrix(v::AbstractMatrix{UInt8})::BitMatrix
    rows, cols = size(v)
    result = BitMatrix(undef, rows * 8, cols)
    for col in 1:cols, row in 1:rows
        byte = v[row, col]
        for bit in 0:7
            result[8*(row-1) + bit + 1, col] = (byte >> (bit)) & 1 == 1
        end
    end
    result
end

function bitshuffle_lib(in, elem_size)
    size = fld(length(in), elem_size)
    @assert size*elem_size == length(in)
    @assert iszero(mod(size, 8))
    out = zeros(UInt8, length(in))
    ret = @ccall libbitshuffle.bshuf_bitshuffle(
        in::Ptr{UInt8},
        out::Ptr{UInt8},
        size::Csize_t,
        elem_size::Csize_t,
        size::Csize_t, # make block size == size to just do one block
    )::Int64
    ret == length(in) || error("$(ret) returned from bshuf_bitshuffle expected $(length(in))")
    out
end

@testset "trans_bit_elem! unit tests" begin
    for elem_size in Int64(1):Int64(50)
        for block_size in 8:8:400
            @assert iszero(mod(block_size, 8))
            og = rand(UInt8, block_size*elem_size)
            og_copy = copy(og)
            trans = similar(og)
            trans_bit_elem!(trans, Int64(0), og, Int64(0), elem_size, block_size)
            @test og == og_copy
            @test trans == bitshuffle_lib(og, elem_size)
            bm_og = make_bitmatrix(reshape(og, elem_size, :))
            bm_trans = make_bitmatrix(reshape(trans, fld(block_size, 8), :))
            @test bm_og == transpose(bm_trans)
            untrans = similar(og)
            untrans_bit_elem!(untrans, Int64(0), trans, Int64(0), elem_size, block_size)
            @test untrans == og
        end
    end
end
@testset "bitshuffle codec" begin
    for element_size in [1:9; 256; 513;]
        for block_size in [0; 8; 24; 2^32;]
            # zero is default
            c = BitshuffleCodec(element_size, block_size)
            test_codec(
                c,
                BitshuffleEncodeOptions(;codec= c),
                BitshuffleDecodeOptions(;codec= c);
                trials=10,
            )
        end
    end
    c = BitshuffleCodec(8, 0)
    # BitshuffleCodec can be used as an encoder and decoder
    test_encoder_decoder(c, c; trials=20)
    # negative or zero element size should error
    @test_throws ArgumentError BitshuffleCodec(0, 0)
    @test_throws ArgumentError BitshuffleCodec(-1, 0)
    @test_throws ArgumentError BitshuffleCodec(typemin(Int64), 0)
    # non multiple of 8 block_size should error
    @test_throws ArgumentError BitshuffleCodec(1, 3)
end
@testset "bitshuffle compress codec" begin
    for element_size in [1:9; 256; 513;]
        for block_size in [0; 8; 24; 2^20;]
            # zero is default
            c = BitshuffleCompressCodec(element_size, LZ4BlockCodec())
            # @show c
            test_codec(
                c,
                BitshuffleCompressEncodeOptions(;codec= c, options= LZ4BlockEncodeOptions(), block_size),
                BitshuffleCompressDecodeOptions(;codec= c);
                trials=10,
            )
        end
    end
end
