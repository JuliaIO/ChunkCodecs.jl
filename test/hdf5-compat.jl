include("hdf5_helpers.jl")

# Useful links:
# https://support.hdfgroup.org/documentation/index.html
# https://github.com/HDFGroup/hdf5_plugins/blob/master/docs/RegisteredFilterPlugins.md
# https://github.com/HDFGroup/hdf5_plugins
# https://docs.h5py.org/en/stable/high/dataset.html#filter-pipeline
# https://www.silx.org/doc/hdf5plugin/latest/usage.html#write-compressed-datasets

# Test data written with encode options can be read with filter ids and client data
[do_hdf5_test(
    ChunkCodecLibZlib.ZlibEncodeOptions(;level),
    [0x0001], [[UInt32(level)]],
    200,
) for level in 0:9]
[do_hdf5_test(
    ChunkCodecCore.ShuffleEncodeOptions(ChunkCodecCore.ShuffleCodec(element_size)),
    [0x0002], [[UInt32(element_size)]],
    200,
) for element_size in [1:20; 1023; typemax(UInt32);]]
do_hdf5_test(
    ChunkCodecLibAec.SzipHDF5EncodeOptions(;codec=ChunkCodecLibAec.SzipHDF5Codec(;
        options_mask=ChunkCodecLibAec.SZ_LSB_OPTION_MASK | ChunkCodecLibAec.SZ_NN_OPTION_MASK,
        pixels_per_block=16,
        bits_per_pixel=32,
        pixels_per_scanline=17,
    )),
    [0x0004], [[(ChunkCodecLibAec.SZ_LSB_OPTION_MASK | ChunkCodecLibAec.SZ_NN_OPTION_MASK)%UInt32, UInt32(16), UInt32(32), UInt32(17)]],
    200,
)
do_hdf5_test(
    ChunkCodecLibAec.SzipHDF5EncodeOptions(;codec=ChunkCodecLibAec.SzipHDF5Codec(;
        options_mask=ChunkCodecLibAec.SZ_MSB_OPTION_MASK | ChunkCodecLibAec.SZ_NN_OPTION_MASK,
        pixels_per_block=16,
        bits_per_pixel=32,
        pixels_per_scanline=17,
    )),
    [0x0004], [[(ChunkCodecLibAec.SZ_MSB_OPTION_MASK | ChunkCodecLibAec.SZ_NN_OPTION_MASK)%UInt32, UInt32(16), UInt32(32), UInt32(17)]],
    200,
)
do_hdf5_test(
    ChunkCodecLibAec.SzipHDF5EncodeOptions(;codec=ChunkCodecLibAec.SzipHDF5Codec(;
        options_mask=ChunkCodecLibAec.SZ_LSB_OPTION_MASK | ChunkCodecLibAec.SZ_EC_OPTION_MASK,
        pixels_per_block=16,
        bits_per_pixel=32,
        pixels_per_scanline=17,
    )),
    [0x0004], [[(ChunkCodecLibAec.SZ_LSB_OPTION_MASK | ChunkCodecLibAec.SZ_EC_OPTION_MASK)%UInt32, UInt32(16), UInt32(32), UInt32(17)]],
    200,
)
do_hdf5_test(
    ChunkCodecLibAec.SzipHDF5EncodeOptions(;codec=ChunkCodecLibAec.SzipHDF5Codec(;
        options_mask=ChunkCodecLibAec.SZ_LSB_OPTION_MASK | ChunkCodecLibAec.SZ_EC_OPTION_MASK,
        pixels_per_block=16,
        bits_per_pixel=8,
        pixels_per_scanline=17,
    )),
    [0x0004], [[(ChunkCodecLibAec.SZ_LSB_OPTION_MASK | ChunkCodecLibAec.SZ_EC_OPTION_MASK)%UInt32, UInt32(16), UInt32(8), UInt32(17)]],
    200,
)
[do_hdf5_test(
    ChunkCodecLibLz4.LZ4HDF5EncodeOptions(;blockSize),
    [UInt16(32004)], [[blockSize%UInt32]],
    100,
) for blockSize in [1:5; 2^10; 2^20; 2^30; ChunkCodecLibLz4.LZ4_MAX_INPUT_SIZE;]]
[do_hdf5_test(
    BitshuffleEncodeOptions(;codec= BitshuffleCodec(element_size, 0)),
    [UInt16(32008)], [[UInt32(0), UInt32(4), UInt32(element_size)]],
    100,
) for element_size in [1:5; 1023;]]
[do_hdf5_test(
    BitshuffleEncodeOptions(;codec= BitshuffleCodec(element_size, block_size)),
    [UInt16(32008)], [[UInt32(0), UInt32(4), UInt32(element_size), UInt32(block_size)]],
    100,
) for element_size in [1:5; 1023;], block_size in [0, 8, 2^10]]
[do_hdf5_test(
    BitshuffleCompressEncodeOptions(;
        codec= BitshuffleCompressCodec(element_size, LZ4BlockCodec()),
        options= LZ4BlockEncodeOptions(),
        block_size,
    ),
    [UInt16(32008)], [[UInt32(0), UInt32(4), UInt32(element_size), UInt32(block_size), UInt32(2)]],
    100,
) for element_size in [1:5; 1023;], block_size in [0, 8, 2^10]]
[do_hdf5_test(
    BitshuffleCompressEncodeOptions(;
        codec= BitshuffleCompressCodec(element_size, ZstdCodec()),
        options= ZstdEncodeOptions(),
        block_size,
    ),
    [UInt16(32008)], [[UInt32(0), UInt32(4), UInt32(element_size), UInt32(block_size), UInt32(3)]],
    100,
) for element_size in [1:5; 1023;], block_size in [0, 8, 2^10]]
[do_hdf5_test(
    ChunkCodecLibZstd.ZstdEncodeOptions(;compressionLevel),
    [UInt16(32015)], [[compressionLevel%UInt32]],
    200,
) for compressionLevel in -3:9]
[do_hdf5_test(
    ChunkCodecLibBlosc.BloscEncodeOptions(;),
    [UInt16(32001)], [[UInt32(2),UInt32(2)]],
    200,
)]
[do_hdf5_test(
    ChunkCodecLibBzip2.BZ2EncodeOptions(;blockSize100k),
    [UInt16(307)], [[UInt32(blockSize100k)]],
    50,
) for blockSize100k in 1:9]


# Test data written by h5py can be decoded
function decode_h5_chunk(chunk::AbstractVector{UInt8}, id::Integer, client_data)
    if id == 1
        decode(ChunkCodecLibZlib.ZlibCodec(), chunk)
    elseif id == 2
        decode(ChunkCodecCore.ShuffleCodec(client_data[1]), chunk)
    elseif id == 4
        decode(ChunkCodecLibAec.SzipHDF5Codec(;
            options_mask=client_data[1]%Int32,
            pixels_per_block=client_data[2]%Int32,
            bits_per_pixel=client_data[3]%Int32,
            pixels_per_scanline=client_data[4]%Int32,
        ), chunk)
    elseif id == 307
        decode(ChunkCodecLibBzip2.BZ2Codec(), chunk)
    elseif id == 32001
        decode(ChunkCodecLibBlosc.BloscCodec(), chunk)
    elseif id == 32004
        decode(ChunkCodecLibLz4.LZ4HDF5Codec(), chunk)
    elseif id == 32008
        element_size = client_data[3]
        block_size = get(client_data, 4, UInt32(0))
        compress = get(client_data, 5, UInt32(0))
        decode(
            if compress == 0
                ChunkCodecBitshuffle.BitshuffleCodec(element_size, block_size)
            elseif compress == 2
                ChunkCodecBitshuffle.BitshuffleCompressCodec(element_size, ChunkCodecLibLz4.LZ4BlockCodec())
            elseif compress == 3
                ChunkCodecBitshuffle.BitshuffleCompressCodec(element_size, ChunkCodecLibZstd.ZstdCodec())
            end,
            chunk,
        )
    elseif id == 32015
        decode(ChunkCodecLibZstd.ZstdCodec(), chunk)
    else
        error("Unsupported filter id: $(id)")
    end
end

do_h5py_test(()->(;data=rand_array(), compression=hdf5plugin.LZ4()), 100)
do_h5py_test(()->(;data=rand_array(), compression=hdf5plugin.LZ4(nbytes=500)), 100)
do_h5py_test(()->(;data=rand_array(), compression=hdf5plugin.Zstd(clevel=3)), 100)
do_h5py_test(()->(;data=rand_array(), compression=hdf5plugin.Bitshuffle()), 100)
for cname in ["none","lz4", "zstd"]
    for nelems in [0, 8]
        do_h5py_test(()->(;data=rand_array(), compression=hdf5plugin.Bitshuffle(;cname, nelems)), 100)
    end
end
do_h5py_test(()->(;data=rand_array(), compression=hdf5plugin.Blosc(cname="zstd", clevel=3), shuffle=true), 100)
do_h5py_test(()->(;data=rand_array(), compression=hdf5plugin.BZip2(blocksize=5)), 10)
do_h5py_test(()->(;data=rand_array(), compression="gzip", compression_opts=3), 100)
do_h5py_test(()->(;data=rand_array(), compression="gzip", shuffle=true), 100)
# szip has extra requirements of chunk size, so `rand_array` doesn't work
do_h5py_test(()->(;data=rand(Int16, 1000), compression="szip"), 10)
do_h5py_test(()->(;data=rand(Int16(1):Int16(10), 100, 100), compression="szip"), 10)
do_h5py_test(()->(;data=rand(Int64(1):Int64(10), 100), compression="szip"), 10)
