include("asdf_helpers.jl")

# Useful links:
# https://www.asdf-format.org/projects/asdf-standard/en/latest/file_layout.html
# https://github.com/asdf-format/asdf/blob/main/asdf/_compression.py
# https://github.com/asdf-format/asdf-compression
# https://www.blosc.org/python-blosc/reference.html#blosc.compress
# https://python-lz4.readthedocs.io/en/stable/lz4.frame.html#lz4.frame.compress

@testset "minimal ASDF file" begin
    data = rand_test_data(1000)
    # uncompressed block
    @test read_py_asdf(make_asdf(data, 1000, "")) == data
    @test read_py_asdf(make_asdf(UInt8[], 0, "")) == UInt8[]
    # block can be read back
    block = read_first_asdf_block(make_asdf(encode(ZlibEncodeOptions(), data), 1000, "zlib"))
    @test block.compression == "zlib"
    @test block.flags == 0
    @test block.data_size == 1000
    @test block.used_size == block.allocated_size
    @test block.checksum == md5(block.data)
    @test decode(ZlibCodec(), block.data) == data
end

# Test data written with encode options can be read by python asdf
jl_to_py = [
    # (Julia encode options,                                          asdf label, trials)
    [(ZlibEncodeOptions(;level),                                        "zlib", 50) for level in -1:9];
    [(BZ2EncodeOptions(;blockSize100k),                                 "bzp2", 5) for blockSize100k in [1, 9]];
    [(BloscEncodeOptions(;clevel, doshuffle, typesize, compressor),     "blsc", 5)
        for clevel in [0, 5]
        for doshuffle in 0:2
        for typesize in [1, 8]
        for compressor in ["blosclz", "lz4", "lz4hc", "zlib", "zstd"]
    ];
    [(LZ4FrameEncodeOptions(;
        compressionLevel,
        blockSizeID,
        blockMode,
        contentChecksumFlag,
        contentSize,
        blockChecksumFlag,
    ),                                                                  "lz4f", 5)
        for compressionLevel in [-1, 0, 5]
        for blockSizeID in [0, 4, 7]
        for blockMode in [false, true]
        for contentChecksumFlag in [false, true]
        for contentSize in [false, true]
        for blockChecksumFlag in [false, true]
    ];
    [(ZstdEncodeOptions(;compressionLevel),                             "zstd", 5) for compressionLevel in -3:9];
    [(ZstdEncodeOptions(;checksum=true),                                "zstd", 5)];
]
@testset "Julia => python asdf" begin
    for (jl_options, compression, trials) in jl_to_py
        do_asdf_test(jl_options, compression, trials)
    end
end

# Test data written by python asdf can be decoded
py_to_jl = [
    # (asdf label, python compression kwargs,                    Julia codec,       trials)
    [("zlib", (;level),                                            ZlibCodec(),       50) for level in -1:9];
    [("bzp2", (;compresslevel),                                    BZ2Codec(),        5) for compresslevel in [1, 9]];
    [("blsc", (;clevel, shuffle, typesize, cname),                 BloscCodec(),      5)
        for clevel in [0, 5]
        for shuffle in 0:2
        for typesize in [1, 8]
        for cname in ["blosclz", "lz4", "lz4hc", "zlib", "zstd"]
    ];
    [("lz4f", (;
        compression_level,
        block_size,
        block_linked,
        content_checksum,
        block_checksum,
        store_size,
    ),                                                             LZ4FrameCodec(),   5)
        for compression_level in [-1, 0, 5]
        for block_size in [0, 4, 7]
        for block_linked in [false, true]
        for content_checksum in [false, true]
        for block_checksum in [false, true]
        for store_size in [false, true]
    ];
    [("zstd", (;level),                                            ZstdCodec(),       5) for level in -3:9];
    [("zstd", (;threads),                                          ZstdCodec(),       5) for threads in [-1, 0, 1, 4]];
]
@testset "python asdf => Julia" begin
    for (compression, compression_kwargs, jl_codec, trials) in py_to_jl
        do_py_asdf_test(jl_codec, compression, compression_kwargs, trials)
    end
end
