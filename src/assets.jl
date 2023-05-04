"""
Represents the various asset classes.
So far `Stock` or `Crypto`, each with a `ticker` as identification.
"""
abstract type Asset end

struct UnknownAsset <: Asset
    ticker::String
end

struct Stock <: Asset
    ticker::String
end

struct Crypto <: Asset
    ticker::String
end

Base.string(a::Asset) = a.ticker
Base.show(io::IO, a::Asset) = print(io, a.ticker)

Base.:(==)(a1::Asset, a2::Asset) = a1.ticker == a2.ticker
