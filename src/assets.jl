@enumx AssetType Stock Crypto Unknown

"""
Represents the various asset classes.
So far `Stock` or `Crypto`, each with a `ticker` as identification.
"""
struct Asset
    type::AssetType.T
    ticker::String
end
Base.string(a::Asset) = a.ticker
Base.show(io::IO, a::Asset) = print(io, a.ticker)

Base.:(==)(a1::Asset, a2::Asset) = a1.type == a2.type && a1.ticker == a2.ticker

Stock(ticker::String) = Asset(AssetType.Stock, ticker)
Crypto(ticker::String) = Asset(AssetType.Crypto, ticker)
