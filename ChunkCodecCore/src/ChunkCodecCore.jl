module ChunkCodecCore

export decode, encode

@static if VERSION >= v"1.11.0-DEV.469"
    eval(Meta.parse("""
        public
            Codec,
            EncodeOptions,
            Codec,
            EncodeOptions,
            DecodeOptions,

            DecodingError,
            DecodedSizeError,

            decode_options,

            decoded_size_range,
            encode_bound,
            try_encode!,

            try_find_decoded_size,
            try_decode!,

            check_in_range,
            check_contiguous,

            can_concatenate,
            is_thread_safe,
            try_resize_decode!,

            NoopCodec,
            NoopEncodeOptions,
            NoopDecodeOptions,

            ShuffleCodec,
            ShuffleEncodeOptions,
            ShuffleDecodeOptions
    """))
end

include("types.jl")
include("errors.jl")
include("interface.jl")
include("noop.jl")
include("shuffle.jl")

end
