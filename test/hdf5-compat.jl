include("hdf5_helpers.jl")

using HDF5
using
    ChunkCodecLibZstd,
    ChunkCodecLibBlosc,
    ChunkCodecLibBzip2,
    ChunkCodecLibLz4,
    ChunkCodecLibZlib,
    ChunkCodecCore
using ChunkCodecTests: rand_test_data
using Test
# Trigger HDF5 filter loading
import CodecBzip2
import Blosc
import CodecZstd
import CodecLz4

using PythonCall
hdf5plugin = pyimport("hdf5plugin")
h5py = pyimport("h5py")

# Useful links:
# https://support.hdfgroup.org/documentation/index.html
# https://github.com/HDFGroup/hdf5_plugins/blob/master/docs/RegisteredFilterPlugins.md
# https://github.com/HDFGroup/hdf5_plugins

# List of encode options and filter ids and client data
codecs = [
    [(
        ChunkCodecLibLz4.LZ4HDF5EncodeOptions(;blockSize),
        ([UInt16(32004)], [[blockSize%UInt32]]),
        100,
    ) for blockSize in [1:5; 2^10; 2^20; 2^30; ChunkCodecLibLz4.LZ4_MAX_INPUT_SIZE;]];
    [(
        ChunkCodecLibZstd.ZstdEncodeOptions(;compressionLevel),
        ([UInt16(32015)], [[compressionLevel%UInt32]]),
        200,
    ) for compressionLevel in -3:9];
    [(
        ChunkCodecLibBlosc.BloscEncodeOptions(;),
        ([UInt16(32001)], [[UInt32(2),UInt32(2)]]),
        200,
    )];
    [(
        ChunkCodecLibBzip2.BZ2EncodeOptions(;blockSize100k),
        ([UInt16(307)], [[UInt32(blockSize100k)]]),
        50,
    ) for blockSize100k in 1:9];
    [(
        ChunkCodecLibZlib.ZlibEncodeOptions(;level),
        ([0x0001], [[UInt32(level)]]),
        200,
    ) for level in 0:9];
    [(
        ChunkCodecCore.ShuffleEncodeOptions(ChunkCodecCore.ShuffleCodec(element_size)),
        ([0x0002], [[UInt32(element_size)]]),
        200,
    ) for element_size in [1:20; 1023; typemax(UInt32);]];
]

function decode_h5_chunk(chunk::AbstractVector{UInt8}, id::Integer, client_data)
    if id == 1
        decode(ChunkCodecLibZlib.ZlibCodec(), chunk)
    elseif id == 2
        decode(ChunkCodecCore.ShuffleCodec(client_data[1]), chunk)
    elseif id == 307
        decode(ChunkCodecLibBzip2.BZ2Codec(), chunk)
    elseif id == 32001
        decode(ChunkCodecLibBlosc.BloscCodec(), chunk)
    elseif id == 32004
        decode(ChunkCodecLibLz4.LZ4HDF5Codec(), chunk)
    elseif id == 32015
        decode(ChunkCodecLibZstd.ZstdCodec(), chunk)
    else
        error("Unsupported filter id: $(id)")
    end
end

test_h5py_options = [
    ((;compression=hdf5plugin.LZ4()), 100);
    ((;compression=hdf5plugin.LZ4(nbytes=500)), 100);
    ((;compression=hdf5plugin.Zstd(clevel=3)), 100);
    ((;compression=hdf5plugin.Blosc(cname="zstd", clevel=3), shuffle=true), 100);
    ((;compression=hdf5plugin.BZip2(blocksize=5)), 10);
    ((;compression="gzip", compression_opts=3), 100);
    ((;compression="gzip", shuffle=true), 100);
]

@testset "$(jl_options) $(h5_options)" for (jl_options, h5_options, trials) in codecs
    h5file = tempname()
    srange = ChunkCodecCore.decoded_size_range(jl_options)
    # round trip tests
    decoded_sizes = [
        first(srange):step(srange):min(last(srange), first(srange)+10*step(srange));
        rand(first(srange):step(srange):min(last(srange), 2000000), trials);
    ]
    for s in decoded_sizes
        # HDF5 cannot handle zero sized chunks
        iszero(s) && continue
        local data = rand_test_data(s)
        chunk = encode(jl_options, data)
        mktemp() do path, io
            write(io, make_hdf5(chunk, s, h5_options...))
            close(io)
            h5open(path, "r") do f
                h5_decoded = collect(f["test-data"])
                @test h5_decoded == data
            end
            # Test reading with h5py
            f = h5py.File(path, "r")
            @test PyArray(f["test-data"][pybuiltins.Ellipsis]) == data
            f.close()
        end
    end
end

function make_h5py_file(options)
    f = h5py.File.in_memory()
    f.create_dataset("a"; options...)
    f.flush()
    hdf_data = collect(PyArray(f.id.get_file_image()))
    f.close()
    return hdf_data
end

function decode_h5_data(hdf_data)
    h5open(hdf_data, "r"; name = "in_memory.h5") do f
        ds = f["a"]
        filters = HDF5.get_create_properties(ds).filters
        chunk_size = HDF5.get_chunk(ds)
        data_size = size(ds)
        out = zeros(eltype(ds), data_size)
        for chunkinfo in HDF5.get_chunk_info_all(ds)
            start = chunkinfo.addr + firstindex(hdf_data)
            stop = start + chunkinfo.size - 1
            chunk = hdf_data[start:stop]
            for i in length(filters):-1:1
                if chunkinfo.filter_mask & (1 << (i - 1)) != 0
                    continue
                end
                filter = filters[HDF5.Filters.ExternalFilter, i]
                chunk = decode_h5_chunk(chunk, filter.filter_id, filter.data)
            end
            chunkstart = chunkinfo.offset .+ 1
            chunkstop = min.(chunkstart .+ chunk_size .- 1, data_size)
            real_chunksize = chunkstop .- chunkstart .+ 1
            shaped_chunkdata = reshape(reinterpret(eltype(out), chunk), chunk_size...)
            copyto!(
                out,
                CartesianIndices(((range.(chunkstart, chunkstop))...,)),
                shaped_chunkdata,
                CartesianIndices(((range.(1, real_chunksize))...,))
            )
        end
        out
    end
end

@testset "HDF5 compatibility with h5py $(options)" for (options, trials) in test_h5py_options
    decoded_sizes = [
        1:10;
        rand((1:2000000), trials);
    ]
    for s in decoded_sizes
        choice = rand(1:3)
        data = if choice == 1
            rand_test_data(s)
        elseif choice == 2
            randn(s)
        elseif choice == 3
            randn(2, s)
        end
        hdf_data = make_h5py_file((;data, options...))
        decoded_data = decode_h5_data(hdf_data)
        @test decoded_data == permutedims(data, ((ndims(data):-1:1)...,))
    end
end
