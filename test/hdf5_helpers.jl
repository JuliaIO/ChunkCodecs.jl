# Helper functions for testing with HDF5
using HDF5
using
    ChunkCodecLibZstd,
    ChunkCodecLibBlosc,
    ChunkCodecLibBzip2,
    ChunkCodecLibLz4,
    ChunkCodecLibZlib,
    ChunkCodecLibAec,
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

function do_hdf5_test(
        jl_options::ChunkCodecCore.EncodeOptions,
        filter_ids::Vector{UInt16},
        client_datas::Vector{Vector{UInt32}},
        trials::Int,
    )
    @testset "$jl_options" begin
        srange = ChunkCodecCore.decoded_size_range(jl_options)
        # round trip tests
        decoded_sizes = [
            first(srange):step(srange):min(last(srange), first(srange)+10*step(srange));
            rand(first(srange):step(srange):min(last(srange), 2000000), trials);
        ]
        for s in decoded_sizes
            # HDF5 cannot handle zero sized chunks
            iszero(s) && continue
            data = rand_test_data(s)
            chunk = encode(jl_options, data)
            hdf_data = make_hdf5(chunk, s, filter_ids, client_datas)
            h5open(hdf_data, "r", name = "in_memory.h5") do f
                h5_decoded = collect(f["test-data"])
                @test h5_decoded == data
            end
            # Test reading with h5py
            f = h5py.File.in_memory(hdf_data)
            @test PyArray(f["test-data"][pybuiltins.Ellipsis]) == data
            f.close()
        end
    end
end

function do_h5py_test(options, trials)
    @testset "decoding h5py $(options().compression)" begin
        for trial in 1:trials
            _options = options()
            data = _options.data
            hdf_data = make_h5py_file(_options)
            decoded_data = decode_h5_data(hdf_data)
            @test decoded_data == permutedims(data, ((ndims(data):-1:1)...,))
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

function rand_array()
    choice = rand(1:8)
    if choice ∈ 1:5
        rand_test_data(rand(1:2000000))
    elseif choice == 6
        randn(rand(1:2000000))
    elseif choice == 7
        randn(2, rand(1:2000000))
    elseif choice == 8
        rand_test_data(rand(1:10))
    end
end


# Ported to Julia from original source at http://www.burtleburtle.net/bob/c/lookup3.c
# lookup3.c, by Bob Jenkins, May 2006, Public Domain.
function lookup3(key::AbstractVector{UInt8}, initvalue::UInt32=UInt32(0))::UInt32
    len::Int64 = Int64(length(key))
    offset::Int64 = Int64(0)
    a::UInt32 = b::UInt32 = c::UInt32 = 0xdeadbeef + (len%UInt32) + initvalue
    iszero(len) && return c
    @inbounds while true
        # Load 12 bytes from key, zero padding if out of bounds
        a, b, c = (a, b, c) .+ load_uint32_zpad.((key,), offset .+ (0,4,8))
        len - 12 > offset || break
        offset += 12
        a, b, c = lookup3_mix(a, b, c)
    end
    return lookup3_final(a, b, c)
end

@inline function load_uint32_zpad(v::AbstractVector{UInt8}, offset)::UInt32
    out::UInt32 = 0
    for i in 0:3
        idx = offset + i + firstindex(v)
        checkbounds(Bool, v, idx) || break
        out |= UInt32(v[idx]) << (i*8)
    end
    out
end

@inline function lookup3_mix(a, b, c)
    a -= c;  a ⊻= bitrotate(c, 4);  c += b
    b -= a;  b ⊻= bitrotate(a, 6);  a += c
    c -= b;  c ⊻= bitrotate(b, 8);  b += a
    a -= c;  a ⊻= bitrotate(c,16);  c += b
    b -= a;  b ⊻= bitrotate(a,19);  a += c
    c -= b;  c ⊻= bitrotate(b, 4);  b += a
    a, b, c
end

@inline function lookup3_final(a, b, c)
    c ⊻= b; c -= bitrotate(b,14)
    a ⊻= c; a -= bitrotate(c,11)
    b ⊻= a; b -= bitrotate(a,25)
    c ⊻= b; c -= bitrotate(b,16)
    a ⊻= c; a -= bitrotate(c, 4)
    b ⊻= a; b -= bitrotate(a,14)
    c ⊻= b; c -= bitrotate(b,24)
    c
end

function stringify(x)
    codeunits(repr(String(view(x,:))))[begin+1:end-1]
end

# convert some data into a copy paste able julia string
function printby(data::AbstractVector{UInt8}; by=8)
    out = collect(b"\"")
    nfulllines = fld(length(data), by)
    for i in 1:nfulllines
        append!(
            out,
            stringify(data[((i-1)*by+1):((i)*by)]),
        )
        append!(out, b"\\\n")
    end
    if !iszero(mod(length(data), by))
        append!(
            out,
            stringify(data[((nfulllines)*by+1):end]),
        )
        append!(out, b"\\\n")
    end
    append!(out, b"\"")
    String(out)
end

function le(x)
    reinterpret(UInt8, [htol(x)])
end

function filter_message(filter_id::UInt16, client_data::Vector{UInt32})
    pad = isodd(length(client_data))
    UInt8[
        le(filter_id); # Filter Identification Value
        le(0x0000); # Filter Name Length
        le(0x0000); # Flags optional filter
        le(UInt16(length(client_data))); # Number Client Data Values
        (le(d) for d in client_data)...; # Client Data
        zeros(UInt8, pad ? 4 : 0); # padding
    ]
end

const H5_TEST_HEADER_SIZE = 2048

# I don't think this a proper hdf5 file, but it is useful for testing purposes
function make_hdf5(chunk::Vector{UInt8}, data_size::Integer, filter_ids::Vector{UInt16}, client_datas::Vector{Vector{UInt32}})
    chunk_size = length(chunk)
    @assert length(filter_ids) == length(client_datas)
    filter_messages = reduce(vcat, (filter_message(filter_ids[i], client_datas[i]) for i in eachindex(filter_ids)))
    super_block = UInt8[
        b"\x89HDF\r\n\x1a\n";
        0x02; # Version
        0x08; # Size of Offsets
        0x08; # Size of Lengths
        0x00; # File Consistency Flags
        le(UInt64(0)); # Base Address
        le(typemax(UInt64)); # Superblock Extension Address, undefined
        le(UInt64(chunk_size + H5_TEST_HEADER_SIZE)); # End of File Address
        le(UInt64(48)); # Root Group Object Header Address
    ]
    root_group_object_header = UInt8[
        0x01; # Version
        0x00; # reserved
        le(UInt16(4)); # Total Number of Header Messages
        le(UInt32(1)); # Object Reference Count
        le(UInt32(0x50)); # Object Header Size
        le(UInt32(0)); # reserved

        le(0x0002); # Header Message #1 Type: Link Info
        le(0x0018); # Size of Header Message #1 Data
        le(UInt32(0)); # Header Message #1 Flags and reserved
        0x00; # Version
        0x00; # Flags
        le(typemax(UInt64)); # Fractal Heap Address undefined
        le(typemax(UInt64)); # Address of v2 B-tree for Name Index undefined
        zeros(UInt8, 6); # padding to get to mult of 8 size

        le(0x000a); # Header Message #2 Type: Group Info
        le(0x0008); # Size of Header Message #2 Data
        le(UInt32(1)); # Header Message #2 Flags
        le(UInt64(0)); # version zero, no flags set

        le(0x0006); # Header Message #3 Type: Link
        # le(0x0000); # Header Message #3 Type: Nil
        le(0x0018); # Size of Header Message #3 Data
        le(UInt32(0)); # Header Message #3 Flags
        0x01; # version
        0x10; # Link Name Character Set Field Present
        0x01; # UTF8
        0x09; # Length of Link Name
        b"test-data"; # Link Name
        le(UInt64(144)); # The address of the object header for the object that the link points to.
        zeros(UInt8, 3); # padding to get to mult of 8 size
    ]
    dataset_object_header = UInt8[
        0x01; # Version
        0x00; # reserved
        le(UInt16(6)); # Total Number of Header Messages
        le(UInt32(1)); # Object Reference Count
        le(UInt32(H5_TEST_HEADER_SIZE-144-16)); # Object Header Size
        le(UInt32(0)); # reserved

        le(0x0001); # Header Message #1 Type: Dataspace
        le(0x0018); # Size of Header Message #1 Data
        le(UInt32(0)); # Header Message #1 Flags
        0x01; # Version
        0x01; # Dimensionality
        0x01; # Flags
        zeros(UInt8, 5); # reserved
        le(UInt64(data_size)); # Dimension #1 Size
        le(UInt64(data_size)); # Dimension #1 Size

        le(0x0003); # Header Message #2 Type: Datatype
        le(0x0010); # Size of Header Message #2 Data
        le(UInt32(1)); # Header Message #2 Flags
        0x10; # Version 1 Class 0, Fixed point
        0x00; # little endian unsigned zero pad
        0x00; # reserved class flags
        0x00; # reserved class flags
        le(UInt32(1)); # Size
        le(UInt16(0)); # Bit Offset
        le(UInt16(8)); # Bit Precision
        zeros(UInt8, 4); # padding

        le(0x0005); # Header Message #3 Type: Fill Value
        le(0x0008); # Size of Header Message #3 Data
        le(UInt32(1)); # Header Message #3 Flags
        0x02; # Version
        # I don't think these flags are correct.
        0x03; # Space Allocation Time
        0x02; # Fill Value Write Time
        0x00; # Fill Value Defined
        le(UInt32(0)); # Size

        le(0x000b); # Header Message #5 Type: Filter Pipeline
        le(UInt16(length(filter_messages)+8)); # Size of Header Message #5 Data
        le(UInt32(1)); # Header Message #5 Flags
        0x01; # Version
        UInt8(length(filter_ids)); # Number of filters
        zeros(UInt8, 6); # reserved
        filter_messages;

        le(0x0008); # Header Message #4 Type: Data Layout
        le(0x0030); # Size of Header Message #4 Data
        le(UInt32(0)); # Header Message #4 Flags
        0x04; # Version
        0x02; # Layout Class, Chunked Storage
        0x03; # Flags, A filtered chunk for Single Chunk indexing.
        # Dimensionality needs to be set to 2 for some reason
        # even though there is only one dimension.
        # I figured this out by looking at JLD2.jl source code.
        0x02; # Dimensionality
        0x08; # Dimension Size Encoded Length
        le(UInt64(data_size)); #  the dimension 1 size of a single chunk, in units of array elements
        le(UInt64(1)); # I don't know why this needed but I think it
        # is related to the additional dimension
        0x01; # Chunk Indexing Type, Single Chunk
        le(UInt64(chunk_size)); # size of filtered chunk
        le(UInt32(0)); # Enabled filters
        le(UInt64(H5_TEST_HEADER_SIZE)); # Address of the chunk, give 2KB of padding for meta data
        zeros(UInt8, 6); # padding
    ]
    header = [
        super_block;
        le(lookup3(super_block));
        root_group_object_header;
        dataset_object_header;
    ]
    pad = H5_TEST_HEADER_SIZE - length(header) - 8
    UInt8[
        header;
        le(0x0000); # Header Message #6 Type: Nil
        le(UInt16(pad)); # Size of Header Message #6 Data
        le(UInt32(0)); # Header Message #6 Flags
        zeros(UInt8, pad);
        chunk;
    ]
end
