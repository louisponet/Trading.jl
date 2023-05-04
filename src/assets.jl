abstract type Asset end

struct Stock <: Asset
    ticker::String
end

struct Crypto <: Asset
    ticker::String
end
