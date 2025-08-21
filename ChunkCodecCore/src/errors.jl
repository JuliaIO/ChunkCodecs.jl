"""
    abstract type DecodingError <: Exception

Generic error for data that cannot be decoded.
"""
abstract type DecodingError <: Exception end

"""
    struct MaybeSize
        val::Int64
    end

If `val ≥ 0` this represents a size, and can be converted back and forth with `Int64`.
Otherwise will error when converted to and from `Int64`.
`-val` is a size hint if not `typemin(Int64)`.

"""
struct MaybeSize
    val::Int64
end
"""
    const NOT_SIZE = MaybeSize(typemin(Int64))
"""
const NOT_SIZE = MaybeSize(typemin(Int64))
function is_size(x::MaybeSize)::Bool
    !signbit(x.val)
end
function Base.Int64(x::MaybeSize)
    if !is_size(x)
        throw(InexactError(:Int64, Int64, x))
    else
        x.val
    end
end
function Base.convert(::Type{Int64}, x::MaybeSize)
    Int64(x)
end
function Base.convert(::Type{MaybeSize}, x::Int64)::MaybeSize
    if signbit(x)
        throw(InexactError(:convert, MaybeSize, x))
    else
        MaybeSize(x)
    end
end

"""
    struct DecodedSizeError <: Exception
    DecodedSizeError(max_size, decoded_size)

Unable to decode the data because the decoded size is larger than `max_size`
or smaller than expected.
If the decoded size is unknown `decoded_size` is `nothing`.
"""
struct DecodedSizeError <: Exception
    max_size::Int64
    decoded_size::MaybeSize
end

function Base.showerror(io::IO, err::DecodedSizeError)
    print(io, "DecodedSizeError: ")
    if err.decoded_size === NOT_SIZE
        print(io, "decoded size is greater than max size: ")
        print(io, err.max_size)
    elseif !is_size(err.decoded_size)
        print(io, "decoded size is greater than max size: ")
        print(io, err.max_size)
        print(io, " decoder hints to try with ")
        print(io, -err.decoded_size.val)
        print(io, " bytes")
    else
        decoded_size::Int64 = err.decoded_size
        if decoded_size < err.max_size
            print(io, "decoded size: ")
            print(io, decoded_size)
            print(io, " is less than expected size: ")
            print(io, err.max_size)
        else
            print(io, "decoded size: ")
            print(io, decoded_size)
            print(io, " is greater than max size: ")
            print(io, err.max_size)
        end
    end
    nothing
end
