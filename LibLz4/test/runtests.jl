using Random: Random
using ChunkCodecLibLz4
using Test: @testset, @test_throws, @test
using Aqua: Aqua

Aqua.test_all(ChunkCodecLibLz4; persistent_tasks = false)

Random.seed!(1234)
@testset "frame" begin
    include("frame.jl")
end
@testset "block" begin
    include("block.jl")
end
@testset "numcodecs" begin
    include("numcodecs.jl")
end
@testset "hdf5" begin
    include("hdf5.jl")
end
@testset "errors" begin
    @test sprint(Base.showerror, LZ4DecodingError("test message")) ==
        "LZ4DecodingError: test message"
end
