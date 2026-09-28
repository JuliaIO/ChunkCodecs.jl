# Helper functions for testing with the python asdf library
using
    ChunkCodecLibZstd,
    ChunkCodecLibBlosc,
    ChunkCodecLibBzip2,
    ChunkCodecLibLz4,
    ChunkCodecLibZlib,
    ChunkCodecCore
using ChunkCodecTests: rand_test_data
using Test
using MD5: md5

using PythonCall
asdf = pyimport("asdf")
pyio = pyimport("io")
np = pyimport("numpy")
# Make sure the minimal ASDF files don't cause any warnings
pyimport("warnings").simplefilter("error", asdf.exceptions.AsdfWarning)

"""
    do_asdf_test(jl_options, compression::String, trials::Int)

Test that data encoded by `jl_options` can be read by the python asdf library.
"""
function do_asdf_test(jl_options, compression::String, trials::Int)
    @testset "$(jl_options) => python asdf $(repr(compression))" begin
        srange = ChunkCodecCore.decoded_size_range(jl_options)
        decoded_sizes = [
            first(srange):step(srange):min(last(srange), first(srange)+10*step(srange));
            rand(first(srange):step(srange):min(last(srange), 2000000), trials);
        ]
        for s in decoded_sizes
            data = rand_test_data(s)
            chunk = encode(jl_options, data)
            asdf_data = make_asdf(chunk, s, compression)
            @test read_py_asdf(asdf_data) == data
        end
    end
end

"Read the \"test-data\" array from an ASDF file with the python asdf library"
function read_py_asdf(asdf_data::Vector{UInt8})::Vector{UInt8}
    af = asdf.open(pyio.BytesIO(pybytes(asdf_data)); lazy_load=false, memmap=false, validate_checksums=true)
    try
        pyconvert(Vector{UInt8}, af["test-data"].tobytes())
    finally
        af.close()
    end
end

"""
    do_py_asdf_test(jl_codec, compression::String, compression_kwargs::NamedTuple, trials::Int)

Test that data written by the python asdf library with `compression`
and `compression_kwargs` can be decoded by `jl_codec`.
"""
function do_py_asdf_test(jl_codec, compression::String, compression_kwargs::NamedTuple, trials::Int)
    @testset "python asdf $(repr(compression)) $(compression_kwargs) => $(jl_codec)" begin
        decoded_sizes = [0:10; rand(0:2000000, trials);]
        for s in decoded_sizes
            data = rand_test_data(s)
            block = read_first_asdf_block(make_py_asdf(data, compression, compression_kwargs))
            @test block.compression == compression
            @test block.data_size == s
            @test block.checksum == md5(block.data)
            @test decode(jl_codec, block.data; size_hint=block.data_size) == data
        end
    end
end

"Write `data` as a uint8 array to an ASDF file with the python asdf library"
function make_py_asdf(data::Vector{UInt8}, compression::String, compression_kwargs::NamedTuple)::Vector{UInt8}
    arr = np.frombuffer(pybytes(data); dtype=np.uint8)
    af = asdf.AsdfFile(pydict(Dict("test-data" => arr)))
    af.set_array_compression(arr, compression; compression_kwargs...)
    buf = pyio.BytesIO()
    af.write_to(buf)
    pyconvert(Vector{UInt8}, buf.getvalue())
end

#=
Very minimal ASDF reading and writing for testing purposes
=#

function be(x)
    reinterpret(UInt8, [hton(x)])
end

function read_be(::Type{T}, data::Vector{UInt8}, pos::Integer)::T where {T<:Unsigned}
    x = zero(T)
    for i in 0:sizeof(T)-1
        x = (x << 8) | T(data[pos+i])
    end
    x
end

const ASDF_BLOCK_MAGIC = b"\xd3BLK"

# Size of the block header after the `header_size` field
const ASDF_BLOCK_HEADER_SIZE = 48

"""
    asdf_block(chunk::Vector{UInt8}, data_size::Integer, compression::String)::Vector{UInt8}

Return an ASDF block containing `chunk`.
`data_size` is the size of the decoded data.
`compression` is the up to 4 byte compression label, "" for no compression.
"""
function asdf_block(chunk::Vector{UInt8}, data_size::Integer, compression::String)::Vector{UInt8}
    @assert ncodeunits(compression) ≤ 4
    UInt8[
        ASDF_BLOCK_MAGIC; # block_magic_token
        be(UInt16(ASDF_BLOCK_HEADER_SIZE)); # header_size
        be(UInt32(0)); # flags, not STREAMED
        codeunits(compression); zeros(UInt8, 4 - ncodeunits(compression)); # compression
        be(UInt64(length(chunk))); # allocated_size
        be(UInt64(length(chunk))); # used_size
        be(UInt64(data_size)); # data_size
        md5(chunk); # checksum
        chunk;
    ]
end

"""
    make_asdf(chunk::Vector{UInt8}, data_size::Integer, compression::String)::Vector{UInt8}

Return an ASDF file with a "test-data" 1D uint8 array of length `data_size`.
The header and tree match what python asdf 5.4.0 writes.
The array's data is stored in a single block containing `chunk`,
which was compressed with `compression`.
"""
function make_asdf(chunk::Vector{UInt8}, data_size::Integer, compression::String)::Vector{UInt8}
    header_and_tree = """
        #ASDF 1.0.0
        #ASDF_STANDARD 1.6.0
        %YAML 1.1
        %TAG ! tag:stsci.edu:asdf/
        --- !core/asdf-1.1.0
        asdf_library: !core/software-1.0.0 {author: The ASDF Developers, homepage: 'http://github.com/asdf-format/asdf',
          name: asdf, version: 5.4.0}
        history:
          extensions:
          - !core/extension_metadata-1.0.0
            extension_class: asdf.extension._manifest.ManifestExtension
            extension_uri: asdf://asdf-format.org/core/extensions/core-1.6.0
            manifest_software: !core/software-1.0.0 {name: asdf_standard, version: 1.5.0}
            software: !core/software-1.0.0 {name: asdf, version: 5.4.0}
        test-data: !core/ndarray-1.1.0
          source: 0
          datatype: uint8
          byteorder: big
          shape: [$(data_size)]
        ...
        """
    # Byte offset of the start of the block
    block_offset = ncodeunits(header_and_tree)
    block_index = """
        #ASDF BLOCK INDEX
        %YAML 1.1
        ---
        - $(block_offset)
        ...
        """
    UInt8[
        codeunits(header_and_tree);
        asdf_block(chunk, data_size, compression);
        codeunits(block_index);
    ]
end

struct ASDFBlock
    flags::UInt32
    compression::String
    allocated_size::Int64
    used_size::Int64
    data_size::Int64
    checksum::Vector{UInt8}
    data::Vector{UInt8}
end

"""
    read_first_asdf_block(asdf_data::Vector{UInt8})::ASDFBlock

Parse the first block of an ASDF file.
This does not support streamed blocks.
"""
function read_first_asdf_block(asdf_data::Vector{UInt8})::ASDFBlock
    @assert view(asdf_data, 1:6) == codeunits("#ASDF ")
    # The block magic is invalid UTF-8, so it cannot appear in the
    # header, comments, or YAML tree before the first block.
    magic = findfirst(ASDF_BLOCK_MAGIC, asdf_data)
    @assert !isnothing(magic) "no blocks found"
    pos = first(magic)
    header_size = Int64(read_be(UInt16, asdf_data, pos + 4))
    @assert header_size ≥ ASDF_BLOCK_HEADER_SIZE
    h = pos + 6 # start of the rest of the header
    flags = read_be(UInt32, asdf_data, h)
    @assert iszero(flags & 0x1) "streamed blocks are not supported by this testing function yet"
    compression = String(rstrip(String(view(asdf_data, h+4:h+7)), '\0'))
    allocated_size = Int64(read_be(UInt64, asdf_data, h + 8))
    used_size = Int64(read_be(UInt64, asdf_data, h + 16))
    data_size = Int64(read_be(UInt64, asdf_data, h + 24))
    checksum = asdf_data[h+32:h+47]
    data_start = h + header_size
    data = asdf_data[data_start:data_start+used_size-1]
    ASDFBlock(flags, compression, allocated_size, used_size, data_size, checksum, data)
end
