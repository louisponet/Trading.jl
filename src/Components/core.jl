@component Base.@kwdef mutable struct Clock
    time::TimeDate = TimeDate(now())
    dtime::Period  = Minute(1)
end

@component Base.@kwdef mutable struct AccountInfo
    key_id::String
    secret_key::String
    rate::Int=200
    last::DateTime = now()
    nrequests::Int=0
end
AccountInfo(x::String, y::String; kwargs...) =
    AccountInfo(key_id=x, secret_key = y; kwargs...)
    
header(a) = ["APCA-API-KEY-ID" => a.key_id, "APCA-API-SECRET-KEY" => a.secret_key]

@component struct Trade
    exchange::String
    price::Float64
    size::Int
    conditions::Vector{String}
end

function Base.show(io::IO, t::Trade)
    println(io,"""
    exchange:   $(EXCHS[t.exchange])
    price:      $(t.price)
    size:       $(t.size)
    conditions: $(t.conditions)
    """)
end

@component struct Quote
    ask_exchange::String
    ask_price::Float64
    ask_size::Int
    bid_exchange::String
    bid_price::Float64
    bid_size::Int
    conditions::Vector{String}
end

function Base.show(io::IO, t::Quote)
    println(io,"""
    ask exchange:   $(EXCHS[t.ask_exchange])
    ask price:      $(t.ask_price)
    ask size:       $(t.ask_size)
    bid exchange:   $(EXCHS[t.ask_exchange])
    bid price:      $(t.ask_price)
    bid size:       $(t.ask_size)
    conditions:     $(t.conditions)
    """)
end

# All need to have a single field v
abstract type SingleValIndicator end


@component struct Open <: SingleValIndicator
    v::Float64
end
@component struct Close <: SingleValIndicator
    v::Float64
end
@component struct High <: SingleValIndicator
    v::Float64
end
@component struct Low <: SingleValIndicator
    v::Float64
end
@component struct Volume <: SingleValIndicator
    v::Float64
end

@component struct LogVal{T} <: SingleValIndicator
    v::T
end

for op in (:+, :-, :*, :/,  :^)
    @eval @inline Base.$op(b1::T, b2::T) where {T <: SingleValIndicator} = T($op(b1.v,   b2.v))
    @eval @inline Base.$op(b1::T, b2::Number) where {T <: SingleValIndicator} = T($op(b1.v,   b2))
    @eval @inline Base.$op(b1::Number, b2::T) where {T <: SingleValIndicator} = T($op(b1,   b2.v))
end

for op in (:(<), :(>), :(>=), :(<=), :(==))
    @eval @inline Base.$op(b1::SingleValIndicator, b2::SingleValIndicator) = $op(b1.v,   b2.v)
    @eval @inline Base.$op(b1::SingleValIndicator, b2::Number)             = $op(b1.v,   b2)
    @eval @inline Base.$op(b1::Number, b2::SingleValIndicator)             = $op(b1,   b2.v)
end

Base.zero(::T) where {T<:SingleValIndicator} = T(0.0)
@inline Base.sqrt(b::T) where {T <: SingleValIndicator} = T(sqrt(b.v))
@inline Base.isless(b::SingleValIndicator, i) = b.v < i
@inline value(b::SingleValIndicator) = b.v
@inline Base.convert(::Type{T}, b::SingleValIndicator) where {T <: Number} = convert(T, b.v)

@assign SingleValIndicator with Is{Indicator}

@component struct TimeStamp
    t::TimeDate
end

TimeStamp() = TimeStamp(TimeDate(now()))

@pooled_component mutable struct Dataset
    ticker::String
    timeframe::String
    start::TimeDate
    stop::Union{TimeDate, Nothing}
    first_e::Entity
    last_e::Entity
end

Dataset(ticker, timeframe, start, stop=nothing) = Dataset(ticker, timeframe, start, stop, Entity(0), Entity(0))

@component struct TickerQueue
    q::SPMCQueue
end

@component struct TradeConnection
    websocket::HTTP.WebSockets.WebSocket
end

@component struct New end
