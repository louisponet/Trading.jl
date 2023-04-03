@component Base.@kwdef mutable struct Clock
    time::TimeDate = TimeDate(now())
    dtime::Period  = Minute(1)
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
@inline value(b::SingleValIndicator) = value(b.v)
@inline value(b::Number) = b
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
