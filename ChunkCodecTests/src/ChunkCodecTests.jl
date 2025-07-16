module ChunkCodecTests

using ChunkCodecCore:
    ChunkCodecCore,
    Codec,
    EncodeOptions,
    DecodeOptions,
    is_thread_safe,
    can_concatenate,
    decode_options,
    decoded_size_range,
    encode_bound,
    encode,
    decode,
    DecodedSizeError,
    try_find_decoded_size,
    try_encode!,
    try_decode!,
    try_resize_decode!

using Test: Test, @test, @test_throws

export test_codec, test_encoder_decoder, rand_test_data

function test_codec(c::Codec, e::EncodeOptions, d::DecodeOptions; trials=100)
    @test decode_options(c) isa DecodeOptions
    @test can_concatenate(c) isa Bool
    @test e.codec == c
    @test d.codec == c
    @test is_thread_safe(e) isa Bool
    @test is_thread_safe(d) isa Bool

    e_props = Tuple(propertynames(e))
    @test typeof(e)(;NamedTuple{e_props}(getproperty.((e,), e_props))...) == e

    d_props = Tuple(propertynames(d))
    @test typeof(d)(;NamedTuple{d_props}(getproperty.((d,), d_props))...) == d

    test_encoder_decoder(e, d; trials)

    # can_concatenate tests
    if can_concatenate(c)
        srange = decoded_size_range(e)
        a = rand(UInt8, 100*step(srange))
        b = rand(UInt8, 200*step(srange))
        @test decode(d, [encode(e, a); encode(e, b);]) == [a; b;]
        @test decode(d, [encode(e, UInt8[]); encode(e, UInt8[]);]) == UInt8[]
    end
end

function test_encoder_decoder(e, d; trials=100)
    @test decoded_size_range(e) isa StepRange{Int64, Int64}
    @test ChunkCodecCore.is_lossless(e) isa Bool

    srange = decoded_size_range(e)
    @test !isempty(srange)
    @test step(srange) > 0
    @test first(srange) ≥ 0
    @test last(srange) != typemax(Int64) # avoid length overflow
    # typemax(Int64) is reserved for overflow
    @test encode_bound(e, typemax(Int64)) == typemax(Int64)

    for s in [first(srange):step(srange):min(last(srange), 1000); rand(srange, 10000); last(srange); typemax(Int64)-1; typemax(Int64);]
        @test encode_bound(e, s) isa Int64
        @test encode_bound(e, s) ≥ s
    end

    # round trip tests
    decoded_sizes = [
        first(srange):step(srange):min(last(srange), first(srange)+10*step(srange));
        rand(first(srange):step(srange):min(last(srange), 2000000), trials);
    ]
    for s in decoded_sizes
        local data = rand_test_data(s)
        local e_bound = encode_bound(e, s)
        local encoded = encode(e, data)
        local buffer = rand(UInt8, max(length(encoded)+11, e_bound+11))
        local b_copy = copy(buffer)
        for buffer_size in [length(encoded):length(encoded)+11; max(e_bound-11,0):e_bound+11;]
            buffer .= b_copy
            local encoded_size = try_encode!(e, view(buffer,1:buffer_size), data)
            # try to test no out of bounds writing
            @test @view(buffer[buffer_size+1:end]) == @view(b_copy[buffer_size+1:end])
            if !isnothing(encoded_size)
                @test decode(d, view(buffer, 1:encoded_size)) == data
            else
                @test buffer_size < e_bound
            end
        end
        # @test try_encode!(e, zeros(UInt8, length(encoded)+1), data) === length(encoded)
        if length(encoded) > 0
            @test isnothing(try_encode!(e, zeros(UInt8, length(encoded)-1), data))
        end
        local ds = try_find_decoded_size(d, encoded)
        @test ds isa Union{Nothing, Int64}
        if !isnothing(ds)
            @test ds === s
        end
        local dst = zeros(UInt8, s)
        @test try_decode!(d, dst, encoded) === s
        @test dst == data
        if s > 0
            dst = zeros(UInt8, s - 1)
            @test isnothing(try_decode!(d, dst, encoded))
            @test isnothing(try_decode!(d, UInt8[], encoded))
        end
        dst = zeros(UInt8, s + 1)
        @test try_decode!(d, dst, encoded) === s
        @test length(dst) == s + 1
        @test dst[1:s] == data

        if s > 0
            dst = zeros(UInt8, s - 1)
            @test isnothing(try_resize_decode!(d, dst, encoded, Int64(-1)))
            @test length(dst) == s - 1
            dst = zeros(UInt8, s - 1)
            @test try_resize_decode!(d, dst, encoded, s) == s
            @test length(dst) == s
            @test dst == data
            dst = UInt8[]
            @test isnothing(try_resize_decode!(d, dst, encoded, Int64(0)))
        end
        if s > 1
            dst = UInt8[]
            @test isnothing(try_resize_decode!(d, dst, encoded, Int64(1)))
            dst = UInt8[0x01]
            @test isnothing(try_resize_decode!(d, dst, encoded, Int64(1)))
            @test_throws DecodedSizeError(1, try_find_decoded_size(d, encoded)) decode(d, encoded; max_size=Int64(1))
        end
        dst_buffer = zeros(UInt8, s + 2)
        dst = view(dst_buffer, 1:s+1)
        @test try_resize_decode!(d, dst, encoded, s-1) === s
        @test try_resize_decode!(d, dst, encoded, s) === s
        @test try_resize_decode!(d, dst, encoded, s+2) === s
        @test length(dst) == s + 1
        @test dst[1:s] == data
        @test dst_buffer[end] == 0x00

        @test decode(d, encoded) == data
    end
end

function rand_test_data(s::Int64)::Vector{UInt8}
    choice = rand(1:4)
    if choice == 1
        rand(UInt8, s)
    elseif choice == 2
        zeros(UInt8, s)
    elseif choice == 3
        ones(UInt8, s)
    elseif choice == 4
        rand(0x00:0x0f, s)
    end
end

"""
    last_good_input(f)

Return the max value of `x` where `f(x::Int64)` doesn't equal typemax(Int64)
`f` must be monotonically increasing
"""
function last_good_input(f)
    low::Int64 = 0
    high::Int64 = typemax(Int64)
    while low != high - 1
        x = (low+high)>>>1
        if f(x) != typemax(Int64)
            low = x
        else
            high = x
        end
    end
    low
end

function find_max_decoded_size(e::EncodeOptions)
    last_good_input(x->encode_bound(e, x))
end

end # module ChunkCodecTests
