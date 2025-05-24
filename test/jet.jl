using JET
using Test

codec_packages = [
    :ChunkCodecLibBlosc,
    :ChunkCodecLibBrotli,
    :ChunkCodecLibBzip2,
    :ChunkCodecLibLz4,
    :ChunkCodecLibSnappy,
    :ChunkCodecLibZlib,
    :ChunkCodecLibZstd,
]

for p in codec_packages
    @eval import $(p)
end

@testset "$(p)" for p in codec_packages
    JET.test_package(string(p))
end
