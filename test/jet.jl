using JET
using Test

codec_packages = [
    :ChunkCodecCore,
    :ChunkCodecBitshuffle,
    :ChunkCodecLibAec,
    :ChunkCodecLibBlosc,
    :ChunkCodecLibBrotli,
    :ChunkCodecLibBzip2,
    :ChunkCodecLibLz4,
    :ChunkCodecLibLzma,
    :ChunkCodecLibSnappy,
    :ChunkCodecLibZlib,
    :ChunkCodecLibZstd,
]

for p in codec_packages
    @eval import $(p)
end

# The implicit positional constructor of a struct takes all arguments as `Any` and
# converts them to the field types. JET analyzes that method as defined, so for a field
# of type `Vector{Pair{Int32, Int32}}` it explores `convert(Vector{Pair{Int32, Int32}}, ::Any)`
# and descends into the `Vector{T}(::AbstractRange{T})` and `Vector{T}(::BitVector)`
# methods in Base, which cannot work for a `Pair` element type. These are false positives:
# the constructors are only ever called with the exact field types.
# Note that despite the name, `ignored_modules` also accepts method matchers.
function untyped_constructor(T::Type)
    sig = Tuple{Type{T}, ntuple(_ -> Any, fieldcount(T))...}
    only(filter(m -> m.sig === sig, methods(T)))
end
ignored_methods = map(JET.AnyFrameMethod, [
    untyped_constructor(ChunkCodecLibZstd.ZstdEncodeOptions),
    untyped_constructor(ChunkCodecLibZstd.ZstdDecodeOptions),
])

@testset "$(p)" for p in codec_packages
    JET.test_package(getproperty(@__MODULE__, p); ignored_modules=ignored_methods)
end
