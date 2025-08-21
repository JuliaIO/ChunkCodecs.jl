using ChunkCodecBitshuffle:
    ChunkCodecBitshuffle,
    trans_bit_elem!,
    untrans_bit_elem!,
    BShufDecodingError,
    BShufCodec,
    BShufEncodeOptions,
    BShufDecodeOptions,
    BShufLZCodec,
    BShufLZEncodeOptions,
    BShufLZDecodeOptions
using ChunkCodecCore:
    ChunkCodecCore,
    decode,
    encode,
    Codec,
    EncodeOptions,
    DecodeOptions,
    NoopCodec,
    try_find_decoded_size,
    try_encode!,
    MaybeSize,
    is_size
using ChunkCodecTests: test_codec, test_encoder_decoder
using ChunkCodecLibLz4
using ChunkCodecLibZstd
using Test: @testset, @test_throws, @test
using Aqua: Aqua
using bitshuffle_jll: libbitshuffle

Aqua.test_all(ChunkCodecBitshuffle; persistent_tasks = false)

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

# version of NoopEncodeOptions that has an element size restriction
# Used to test strange edge case where encoder can encode full blocks but cannot encode partial blocks.
struct TestNoopEncodeOptions <: ChunkCodecCore.EncodeOptions
    codec::NoopCodec
    element_size::Int64
end
function TestNoopEncodeOptions(;
        codec::NoopCodec= NoopCodec(),
        element_size::Integer= 1,
        kwargs...
    )
    TestNoopEncodeOptions(codec, element_size)
end
ChunkCodecCore.encode_bound(::TestNoopEncodeOptions, src_size::Int64)::Int64 = src_size
ChunkCodecCore.decoded_size_range(e::TestNoopEncodeOptions) = Int64(8):e.element_size:typemax(Int64)-Int64(1)
function ChunkCodecCore.try_encode!(e::TestNoopEncodeOptions, dst::AbstractVector{UInt8}, src::AbstractVector{UInt8}; kwargs...)::MaybeSize
    dst_size::Int64 = length(dst)
    src_size::Int64 = length(src)
    check_in_range(decoded_size_range(e); src_size)
    if dst_size < src_size
        nothing
    else
        copyto!(dst, src)
        src_size
    end
end


@testset "trans_bit_elem! unit tests" begin
    for elem_size in Int64(1):Int64(50)
        for block_size in Int64(8):Int64(8):Int64(400)
            @assert iszero(mod(block_size, 8))
            og = rand(UInt8, block_size*elem_size)
            og_copy = copy(og)
            trans = similar(og)
            trans_bit_elem!(trans, Int64(0), og, Int64(0), elem_size, block_size)
            @test og == og_copy
            @test trans == bitshuffle_lib(og, elem_size)
            bm_og = make_bitmatrix(reshape(og, Int(elem_size), :))
            bm_trans = make_bitmatrix(reshape(trans, Int(fld(block_size, 8)), :))
            @test bm_og == transpose(bm_trans)
            untrans = similar(og)
            untrans_bit_elem!(untrans, Int64(0), trans, Int64(0), elem_size, block_size)
            @test untrans == og
        end
    end
end
@testset "bitshuffle codec" begin
    for element_size in [1:4; 8; 256; 513;]
        for block_size in [0; 8; 24; 2^32;]
            # zero is default
            c = BShufCodec(element_size, block_size)
            test_codec(
                c,
                BShufEncodeOptions(;codec= c),
                BShufDecodeOptions(;codec= c);
                trials=10,
            )
        end
    end
    c = BShufCodec(8, 0)
    # BShufCodec can be used as an encoder and decoder
    test_encoder_decoder(c, c; trials=20)
    # negative or zero element size should error
    @test_throws ArgumentError BShufCodec(0, 0)
    @test_throws ArgumentError BShufCodec(-1, 0)
    @test_throws ArgumentError BShufCodec(typemin(Int64), 0)
    # non multiple of 8 block_size should error
    @test_throws ArgumentError BShufCodec(1, 3)
end
@testset "non multiple of element size" begin\
    # Ref https://github.com/kiyo-masui/bitshuffle/issues/3
    c = BShufCodec(5, 0)
    @test_throws ArgumentError encode(c, zeros(UInt8, 42))
    @test_throws BShufDecodingError("src_size isn't a multiple of element_size") decode(c, ones(UInt8, 42))
end
@testset "bitshuffle compress codec" begin
    for element_size in [1; 8; 256; 513;]
        for block_size in [0; 8; 24; 2^20;]
            # zero is default
            c = BShufLZCodec(element_size, ZstdCodec())
            # @show c
            test_codec(
                c,
                BShufLZEncodeOptions(;codec= c, options= ZstdEncodeOptions(), block_size),
                BShufLZDecodeOptions(;codec= c);
                trials=10,
            )
        end
    end
    c = BShufLZCodec(5, LZ4BlockCodec())
    test_codec(
        c,
        BShufLZEncodeOptions(;codec= c, options= LZ4BlockEncodeOptions()),
        BShufLZDecodeOptions(;codec= c);
        trials=10,
    )
end
@testset "non multiple of element size compress" begin
    e_opt = BShufLZEncodeOptions(;codec=BShufLZCodec(5, LZ4BlockCodec()), options=LZ4BlockEncodeOptions())
    # Ref https://github.com/kiyo-masui/bitshuffle/issues/3
    @test_throws ArgumentError encode(e_opt, zeros(UInt8, 42))
    # decode will copy leftover bytes at the end for future bitshuffle compatibility.
    e = encode(e_opt, ones(UInt8, 40))
    # patch the decoded size
    e[8] = 42
    @test_throws BShufDecodingError("decoded_size isn't a multiple of element_size") decode(e_opt.codec, [e; 0x12; 0x34;]) == [ones(UInt8, 40); 0x12; 0x34;]
end
@testset "BShufLZ constructors" begin
    BCC = BShufLZCodec
    BCE = BShufLZEncodeOptions
    BCD = BShufLZDecodeOptions
    @test_throws ArgumentError BCC(0, LZ4BlockCodec())
    @test_throws ArgumentError BCC(-1, LZ4BlockCodec())
    @test_throws ArgumentError BCC(fld(typemax(Int32),8) + 1, LZ4BlockCodec())
    @test_throws MethodError BCC(1, 1)
    @test_throws MethodError BCC{Codec}(1, 1)
    @test_throws MethodError BCC{ZstdCodec}(1, LZ4BlockCodec())
    a = BCC(1, LZ4BlockCodec())
    b = BCC{LZ4BlockCodec}(1, LZ4BlockCodec())
    c = BCC{Codec}(1, LZ4BlockCodec())
    @test a === b
    @test a !== c

    # Encode options
    @test_throws MethodError BCE(;codec= ZstdCodec(), options= ZstdEncodeOptions())
    @test_throws ArgumentError BCE(;codec= BCC(1, ZstdCodec()), options= LZ4BlockEncodeOptions())
    @test_throws MethodError BCE{ZstdCodec, ZstdEncodeOptions}(;codec= BCC(1, LZ4BlockCodec()), options= LZ4BlockEncodeOptions())
    @test_throws ArgumentError BCE{Codec, EncodeOptions}(;codec= BCC(1, ZstdCodec()), options= LZ4BlockEncodeOptions())
    a = BCE(;codec= BCC(1, ZstdCodec()), options= ZstdEncodeOptions())
    b = BCE{ZstdCodec, ZstdEncodeOptions}(;codec= BCC(1, ZstdCodec()), options= ZstdEncodeOptions())
    c = BCE{Codec, ZstdEncodeOptions}(;codec= BCC{Codec}(1, ZstdCodec()), options= ZstdEncodeOptions())
    d = BCE{ZstdCodec, EncodeOptions}(;codec= BCC(1, ZstdCodec()), options= ZstdEncodeOptions())
    e = BCE{Codec, EncodeOptions}(;codec= BCC{Codec}(1, ZstdCodec()), options= ZstdEncodeOptions())
    @test typeof(a) == typeof(b)
    @test allunique(typeof.([b, c, d, e]))

    @test_throws ArgumentError BCE(;codec= BCC(1, ZstdCodec()), options= ZstdEncodeOptions(), block_size=Int64(2)^31)
    @test_throws ArgumentError BCE(;codec= BCC(1, ZstdCodec()), options= ZstdEncodeOptions(), block_size=9)
    @test_throws ArgumentError BCE(;codec= BCC(1, ZstdCodec()), options= ZstdEncodeOptions(), block_size=-1)

    # max block compressed and uncompressed bytes must be less than typemax(Int32)
    @test_throws ArgumentError BCE(;codec= BCC(8, ZstdCodec()), options= ZstdEncodeOptions(), block_size=2147483640)
    @test_throws ArgumentError BCE(;codec= BCC(268435455, ZstdCodec()), options= ZstdEncodeOptions(), block_size=16)
    @test_throws ArgumentError BCE(;codec= BCC(268435455, ZstdCodec()), options= ZstdEncodeOptions(), block_size=8)
    BCE(;codec= BCC(258435455, ZstdCodec()), options= ZstdEncodeOptions(), block_size=8)
    @test_throws ArgumentError BCE(;codec= BCC(268435455, LZ4BlockCodec()), options= LZ4BlockEncodeOptions(), block_size=8)
    @test_throws ArgumentError BCE(;codec= BCC(134217727, LZ4BlockCodec()), options= LZ4BlockEncodeOptions(), block_size=16)

    # Test strange edge case where encoder can encode full blocks but cannot encode partial blocks.
    BCE(;codec= BCC(1, NoopCodec()), options= TestNoopEncodeOptions(), block_size=32)
    @test_throws ArgumentError BCE(;codec= BCC(1, NoopCodec()), options= TestNoopEncodeOptions(element_size=24), block_size=32)

    # Decode options
    @test_throws ArgumentError BCD(;codec= BCC(1, ZstdCodec()), options= LZ4BlockDecodeOptions())
    a = BCD(;codec= BCC(1, ZstdCodec()), options= ZstdDecodeOptions())
    b = BCD{ZstdCodec, ZstdDecodeOptions}(;codec= BCC(1, ZstdCodec()), options= ZstdDecodeOptions())
    c = BCD{Codec, ZstdDecodeOptions}(;codec= BCC{Codec}(1, ZstdCodec()), options= ZstdDecodeOptions())
    d = BCD{ZstdCodec, DecodeOptions}(;codec= BCC(1, ZstdCodec()), options= ZstdDecodeOptions())
    e = BCD{Codec, DecodeOptions}(;codec= BCC{Codec}(1, ZstdCodec()), options= ZstdDecodeOptions())
    @test typeof(a) == typeof(b)
    @test allunique(typeof.([b, c, d, e]))
end
@testset "unexpected eof" begin
    codec= BShufLZCodec(1, ZstdCodec())
    for element_size in (1,5)
        codec= BShufLZCodec(element_size, ZstdCodec())
        for block_size in (0,8,16,1000,1008,10000)
            e_opt = BShufLZEncodeOptions(;
                codec,
                options= ZstdEncodeOptions(),
                block_size,
            )
            u = rand(UInt8, 1015)
            c = encode(e_opt, u)
            @test decode(codec, c) == u
            for i in 1:length(c)
                @test_throws BShufDecodingError decode(codec, c[1:i-1])
            end
            @test_throws BShufDecodingError decode(codec, [c; c;])
            @test_throws BShufDecodingError decode(codec, [c; 0x00;])
        end
    end
end
@testset "BShufLZ errors" begin
    @test sprint(Base.showerror, BShufDecodingError("foo")) ==
        "BShufDecodingError: foo"
    codec=BShufLZCodec(1, ZstdCodec())
    e = BShufLZEncodeOptions(;
        codec,
        options= ZstdEncodeOptions(),
    )
    d = BShufLZDecodeOptions(;codec)
    # less than 12 bytes
    @test_throws BShufDecodingError("unexpected end of input") try_find_decoded_size(d, UInt8[])
    @test_throws BShufDecodingError("decoded size is negative") try_find_decoded_size(d, fill(0xFF,12))
    @test typemax(Int64) == try_find_decoded_size(d, [0x7F; fill(0xFF, 11);])
    # invalid block size
    @test_throws BShufDecodingError("block size must not be negative") decode(d, [
        reinterpret(UInt8, [hton(Int64(0))]);
        reinterpret(UInt8, [hton(Int32(-1))]);
    ])
    @test_throws BShufDecodingError("block size must be a multiple of 8") decode(d, [
        reinterpret(UInt8, [hton(Int64(0))]);
        reinterpret(UInt8, [hton(Int32(3))]);
    ])
    @test_throws BShufDecodingError("unexpected $(1) bytes after stream") decode(d, [
        reinterpret(UInt8, [hton(Int64(0))]);
        reinterpret(UInt8, [hton(Int32(0))]);
        0x00;
    ])
    @test_throws BShufDecodingError("unexpected end of input") decode(d, [
        reinterpret(UInt8, [hton(Int64(1))]);
        reinterpret(UInt8, [hton(Int32(16))]);
    ])
    @test_throws BShufDecodingError("block compressed size must not be negative") decode(d, [
        reinterpret(UInt8, [hton(Int64(8))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(-1))]);
    ])
    @test_throws BShufDecodingError("unexpected end of input") decode(d, [
        reinterpret(UInt8, [hton(Int64(8))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(16))]);
    ])
    @test_throws ZstdDecodingError decode(d, [
        reinterpret(UInt8, [hton(Int64(8))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(100))]);
        ones(UInt8, 100);
    ])
    oneszstd17 = encode(ZstdEncodeOptions(), fill(0x01, 17))
    @test_throws BShufDecodingError("saved decoded size is not correct") decode(d, [
        reinterpret(UInt8, [hton(Int64(16))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(length(oneszstd17)))]);
        oneszstd17;
    ])
    oneszstd15 = encode(ZstdEncodeOptions(), fill(0x01, 15))
    @test_throws BShufDecodingError("saved decoded size is not correct") decode(d, [
        reinterpret(UInt8, [hton(Int64(16))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(length(oneszstd15)))]);
        oneszstd15;
    ])
    @test_throws BShufDecodingError("unexpected end of input") decode(d, [
        reinterpret(UInt8, [hton(Int64(16))]);
        reinterpret(UInt8, [hton(Int32(16))]);
        reinterpret(UInt8, [hton(Int32(3))]);
        [0x20, 0x12,];
    ])
end
@testset "encoding without enough space" begin
    codec=BShufLZCodec(1, ZstdCodec())
    e = BShufLZEncodeOptions(;
        codec,
        options= ZstdEncodeOptions(),
        block_size= 32,
    )
    d = BShufLZDecodeOptions(;codec)
    u = rand(UInt8, 1024)
    c = encode(e, u)
    @test decode(d, c) == u
    for i in 1:length(c)
        @test !is_size(try_encode!(e, c[1:i-1], u))
    end
    # zero length
    u = UInt8[]
    c = zeros(UInt8, 12)
    @test try_encode!(e, c, u) == MaybeSize(length(c))
    @test decode(d, c) == u
    for i in 1:length(c)
        @test !is_size(try_encode!(e, c[1:i-1], u))
    end
    # one length
    u = UInt8[0x00]
    c = zeros(UInt8, 12+1)
    @test try_encode!(e, c, u) == MaybeSize(length(c))
    @test decode(d, c) == u
    for i in 1:length(c)
        @test !is_size(try_encode!(e, c[1:i-1], u))
    end
end
