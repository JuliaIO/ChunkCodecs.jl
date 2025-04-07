"""
    abstract type DecodingError <: Exception

Generic error for data that cannot be decoded.
"""
abstract type DecodingError <: Exception end

"""
    struct DecodedSizeError <: Exception
    DecodedSizeError(max_size, decoded_size)

Unable to decode the data because the decoded size is larger than `max_size`
or smaller than expected.
If the decoded size is unknown `decoded_size` is `nothing`.
"""
struct DecodedSizeError <: Exception
    max_size::Int64
    decoded_size::Union{Nothing, Int64}
end

function Base.showerror(io::IO, err::DecodedSizeError)
    print(io, "DecodedSizeError: ")
    if isnothing(err.decoded_size)
        print(io, "decoded size is greater than max size: ")
        print(io, err.max_size)
    elseif err.decoded_size < err.max_size
        print(io, "decoded size: ")
        print(io, err.decoded_size)
        print(io, " is less than expected size: ")
        print(io, err.max_size)
    else
        print(io, "decoded size: ")
        print(io, err.decoded_size)
        print(io, " is greater than max size: ")
        print(io, err.max_size)
    end
    nothing
end