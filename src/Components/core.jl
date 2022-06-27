@pooled_component Base.@kwdef mutable struct TimingData
    time::DateTime     = now()
    dtime::Millisecond = Millisecond(0)
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
    
header(a::AccountInfo) = ["APCA-API-KEY-ID" => a.key_id, "APCA-API-SECRET-KEY" => a.secret_key]

@component struct Trade
    exchange::String
    price::Float64
    size::Int
    conditions::Vector{String}
end

function Base.show(io::IO, t::Trade)
    println(io,"""
   time:       $(t.time)
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

@component struct Bar
    open::Float64
    high::Float64
    low::Float64
    close::Float64
    volume::Int
end

Base.zero(::Bar) = Bar(0.0, 0.0, 0.0, 0.0, 0)
for op in (:+, :-)
    @eval Base.$op(b1::Bar, b2::Bar) = Bar($op(b1.open,   b2.open),
                                             $op(b1.high,   b2.high),
                                             $op(b1.low,    b2.low),
                                             $op(b1.close,  b2.close),
                                             $op(b1.volume, b2.volume))
end
Base.:(/)(b::Bar, i::Int) = Bar(b.open/i, b.high/i, b.low/i, b.close/i, div(b.volume,i))

@assign Bar with Is{Indicator}

function Base.show(io::IO, t::Bar)
    println(io,"""
    open:   $(t.open)
    high:   $(t.high)
    low:    $(t.low)
    close:  $(t.close)
    volume: $(t.volume)
    """)
end

MarketTechnicals.TimeSeries.TimeArray(times, bars::Vector{Bar}, colnames = [:Open, :High, :Low, :Close, :Volume]) =
    TimeArray(map(x -> DateTime(x.time), times), [map(x-> x.open, bars) map(x -> x.high, bars) map(x -> x.low, bars) map(x -> x.close, bars) map(x -> x.volume, bars)], colnames)


@component mutable struct Dataset
    ticker::String
    timeframe::String
    start::DateTime
    stop::Union{DateTime, Nothing}
    first_e::Entity
    last_e::Entity
end

Dataset(ticker, timeframe, start, stop=nothing) = Dataset(ticker, timeframe, start, stop, Entity(0), Entity(0))


    
