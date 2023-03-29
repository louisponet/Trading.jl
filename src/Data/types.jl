"""
    DataLedger

Represents the tick data of a given `ticker`. A `DataLedger` can be attached to a [`DataPipeline`](@ref) with [`attach!`](@ref), which will cause data to flow in as soon as it is available.
"""
mutable struct DataLedger <: AbstractLedger
    ticker::String
    l::Ledger
end 

DataLedger(ticker::String) = DataLedger(ticker, Ledger())

Overseer.ledger(d::DataLedger) = d.l

function loop(ch::Channel, d::DataLedger)
    while true
        try
            (time, (o, h, l, c, v))  = take!(ch)
            Entity(d, TimeStamp(time), Open(o), High(h), Low(l), Close(c), Volume(v), New())
            Overseer.update(d)
        catch e
            showerror(stdout, e, catch_backtrace())
        end
    end
end

# Broker Interface
"""
    AbstractBroker

Interface for external brokers.
"""
abstract type AbstractBroker end

#TODO cleanup interface 
# subscibe(::AbstractBroker, ::WebSocket, ::String) = throw(MethodError(subscribe))
# bars(::AbstractBroker, ::Vector)                  = throw(MethodError(bars))
# authenticate_data(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_data))
# authenticate_trading(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_trading))

struct AuthenticationException <: Exception
    e
end

function Base.showerror(io::IO, err::AuthenticationException, args...)
    println(io, "AuthenticationException:")
    showerror(io, err.e, args...)
end

"""
    AbstractDataSource

Interface for different datasources.
"""
abstract type AbstractDataSource end

current_price(link::AbstractDataSource, ticker) = nothing 
last_close(link::AbstractDataSource, ticker)    = nothing

const HistoricalTradeDataDict = Dict{String, TimeArray{Any, 2, TimeDate, Matrix{Any}}}
const HistoricalQuoteDataDict = Dict{String, TimeArray{Any, 2, TimeDate, Matrix{Any}}}
const HistoricalBarDataDict = Dict{Tuple{String, Period}, TimeArray{Float64, 2, TimeDate, Matrix{Float64}}}

"""
   HistoricalDataSource

Stores and provides data from historical datasets. Data can be streamed fashion by assigning a
[`Clock`](@ref) to the `clock` constructor kwarg, which will be used to determine the next bar to
stream when calling `receive` on this provider.
"""
Base.@kwdef mutable struct HistoricalDataSource{B <: AbstractBroker} <: AbstractDataSource
    broker::B
    
    bar_data::HistoricalBarDataDict     = HistoricalBarDataDict()
    trade_data::HistoricalTradeDataDict = HistoricalTradeDataDict()
    quote_data::HistoricalQuoteDataDict = HistoricalQuoteDataDict()
    
    clock::Clock = Clock(clock(), Millisecond(1))
    last::TimeDate = TimeDate(0)
end

HistoricalDataSource(b::AbstractBroker; kwargs...)  = HistoricalDataSource(; broker=b, kwargs...)

function retrieve_data(provider::HistoricalDataSource, set, key, start, stop, args...; kwargs...)
    ticker = key isa Tuple ? first(key) : key

    dt = key isa Tuple ? last(key) : Millisecond(1)
    @assert start <= stop ArgumentError("start should be <= stop")
    
    if haskey(set, key)

        data = set[key]
        timestamps = timestamp(data)

        if start <= stop < timestamps[1]
            new_data = stock_query(provider.broker, ticker, start, stop, args...; kwargs...)
            
            if new_data !== nothing
                set[key] = vcat(new_data, data)
            end
            
            return new_data
            
        elseif timestamps[end] < start <= stop
            new_data = stock_query(provider.broker, ticker, start, stop, args...; kwargs...)

            if new_data !== nothing
                set[key] = vcat(data, new_data)
            end
            
            return new_data
            
        end
            
        if timestamps[1] <= start 
            out_data = from(data, start)
        else
            next_stop = timestamps[1] - dt
            new_data = stock_query(provider.broker, ticker, start, next_stop, args...; kwargs...)
            
            if new_data !== nothing
                out_data = vcat(new_data, data)
                set[key] = out_data
            else
                out_data = data
            end

        end

        if timestamps[end] >= stop
            return to(out_data, stop)
        else
            next_start = timestamps[end] + dt
            
            new_data = stock_query(provider.broker, ticker, next_start, stop, args...; kwargs...)
            if new_data !== nothing
                out_data = vcat(out_data, new_data)
                set[key] = vcat(data, new_data)
            end

            return out_data
        end
    end

    data = stock_query(provider.broker, ticker, start, stop, args...; kwargs...)
    if data !== nothing
        set[key] = data
    end
    
    return data
end

function bars(provider::HistoricalDataSource, ticker, start, stop=clock(); timeframe::Period, kwargs...)
    
    start = round(start, typeof(timeframe), RoundDown)
    stop  = round(stop, typeof(timeframe), RoundUp)

    retrieve_data(provider, provider.bar_data, (ticker, timeframe), start, stop, Float64; section="bars", timeframe=timeframe, kwargs...)
end

quotes(provider::HistoricalDataSource, ticker, args...; kwargs...) =
    retrieve_data(provider, provider.quote_data, ticker, args...; section="quotes", kwargs...)
    
trades(provider::HistoricalDataSource, ticker, args...; kwargs...) = 
    retrieve_data(provider, provider.trade_data, ticker, args...; section="trades", kwargs...)


function Base.open(func::Function, dataprovider::HistoricalDataSource)
    try
        func(dataprovider)
    catch e
        if !(e isa InterruptException)
            rethrow(e)
        end
    end
end


function register!(dp::HistoricalDataSource, ticker, start=nothing,stop=nothing; timeframe=nothing)
    if !any(x-> first(x) == ticker, keys(dp.bar_data))
        start     = start === nothing ? minimum(x->timestamp(x)[1],   values(dp.bar_data)) : start
        stop      = stop === nothing  ? maximum(x->timestamp(x)[end], values(dp.bar_data)) : stop
        timeframe = timeframe === nothing ? minimum(x->last(x), keys(dp.bar_data)) : timeframe
        bars(dp, ticker, start, stop, timeframe=timeframe)
    end
end

#TODO Not Broker Agnostic
function HTTP.receive(dp::HistoricalDataSource)
    curt = dp.clock.time
    
    msg = NamedTuple{(:T, :S, :t, :o, :h, :l, :c, :v), Tuple{String, String, String, Float64, Float64, Float64, Float64, Int}}[]
    while isempty(msg)
        for (ticker, frame) in dp.bar_data
            
            dat = when(frame, x -> dp.last < x <= dp.clock.time, 1)[:o, :h, :l, :c, :v]
            for (time, vals) in dat
                push!(msg, (T="b", S=first(ticker), t=string(time)*"Z", o = vals[1], h=vals[2], l=vals[3], c=vals[4], v=Int(vals[5])))
            end
        end
        yield()
    end
    dp.last = curt
    return bars(dp.broker, msg)
end
            
"""
   RealtimeDataSource

Provides a realtime data feed through a connection with an external broker such as [`AlpacaBroker`](@ref).
"""
Base.@kwdef mutable struct RealtimeDataSource{B <: AbstractBroker} <: AbstractDataSource
    broker::B
    ws::Union{Nothing, WebSocket} = nothing
end

RealtimeDataSource(b::AbstractBroker; kwargs...) = RealtimeDataSource(;broker=b, kwargs...)

function Base.open(func::Function, data_source::RealtimeDataSource)
    HTTP.open(data_stream_url(data_source.broker)) do ws
        
        if !authenticate_data(data_source.broker, ws)
            error("couldn't authenticate")
        end
        
        try
            data_source.ws = ws
            func(data_source)
        catch e
            showerror(stdout, e, catch_backtrace())
            if !(e isa InterruptException)
                rethrow(e)
            end
        finally
            data_source.ws=nothing
        end
        
    end
end

function register!(dp::RealtimeDataSource, ticker, args...; kwargs...)
    if dp.ws !== nothing
        subscribe(dp.broker, dp.ws, ticker)
    end
end

function HTTP.receive(dp::RealtimeDataSource)
    msg = JSON3.read(receive(dp.ws))
    return bars(dp.broker, msg)
end

"""
    DataPipeline

Handles distribution of data to the different [`DataLedgers`](@ref DataLedger) through the associated
`queues`.
By using either a [`HistoricalDataSource`](@ref) or [`RealtimeDataSource`](@ref) one can exchange
whether data is streamed from a historical dataset or streamed realtime through a connection to
an external data broker.
"""
Base.@kwdef struct DataPipeline{DP <: AbstractDataSource}
    provider::DP
    queues::Dict{String, Channel} = Dict{String,Channel}()
end

DataPipeline(provider::AbstractDataSource; kwargs...) = DataPipeline(;provider=provider, kwargs...)

function attach!(ds::DataPipeline, queue::Channel, ticker::String, args...; kwargs...)
    ds.queues[ticker] = queue
    register!(ds.provider, ticker, args...; kwargs...)
end

"""
    attach!(ds::DataDistributor, l::DataLedger, args...; kwargs...)

Registers a [`DataLedger`](@ref) to `ds`. This creates a `Channel` through which the correct tick data
flows into `l`.
"""
function attach!(ds::DataPipeline, l::DataLedger, args...; kwargs...)
    ch = Channel{Tuple{TimeDate, Tuple{Float64, Float64, Float64, Float64, Int}}}(c -> loop(c, l), spawn=true)
    attach!(ds, ch, l.ticker, args...; kwargs...)
end

function start_stream(ds::DataPipeline)
    open(ds.provider) do bar_stream
    
        for (ticker, q) in ds.queues
            register!(bar_stream, ticker)
        end
        
        while true
            bars = receive(bar_stream)
            for (ticker, bar) in bars
                put!(ds.queues[ticker], bar)
            end
        end
    end
end

"""
    TradingLink

Interface to support executing trades and retrieving account updates.
"""
Base.@kwdef struct TradingLink{B <: AbstractBroker}
    broker::B
    submission_queue::Channel
    ws::Union{Nothing, WebSocket} = nothing
end

submit_order(link::TradingLink, o) = nothing

function Base.open(f::Function, trading_link::TradingLink)
    HTTP.open(trading_stream_url(trading_link.broker)) do ws
        if !authenticate_trading(trading_link.broker, ws)
            error("couldn't authenticate")
        end
        @info "Authenticated trading"
        send(ws, JSON3.write(Dict("action" => "listen",
                                  "data"  => Dict("streams" => ["trade_updates"]))))
        try
            trading_link.ws = ws
            f(trading_link)
        catch e
            showerror(stdout, e, catch_backtrace())
            if !(e isa InterruptException)
                rethrow(e)
            end
        finally
            trading_link.ws = nothing
        end
    end
end

# TODO not broker agnotistic
function receive(trading_link::TradingLink)
    msg = JSON3.read(receive(trading_link.ws))
    if msg[:stream] == "trade_updates" && msg[:data][:event] == "fill"
        return msg[:data][:order]
    end
end

function order_stream(trading_link::TradingLink, order_comp)
    open(trading_link) do link

        broker = trading_link.broker
    
        trading_link.submission_queue = Channel{EntityState}() do channel
        
            while true
                order = take!(channel)
                
                side = Purchase ∈ order ? "buy" : "sell"
                body = Dict("symbol"        => string(order.ticker),
                            "qty"           => string(order.quantity),
                            "side"          => side,
                            "type"          => string(order.type),
                            "time_in_force" => string(order.time_in_force))
                
                if order.type == OrderType.Limit
                    body["limit_price"] = string(order.price)
                end
                
                uri  = URI(trading_url(broker), path="/v2/orders")
                h    = header(broker)
                
                resp = HTTP.post(uri, h, JSON3.write(body))
                
                if resp.status != 200
                    error("something went wrong")
                end

                order_comp[order] = parse_order(broker, JSON3.read(resp.body))
            end
        while true
            order = receive(trading_link)
            
            uid = UUID(order[:id])
               
            id = nothing
            #TODO dangerous when an order would come from somewhere else
            while id === nothing
                id = findlast(x->x.id == uid, order_comp.data)
            end

            order = trader[Order].data[id]

            order.status           = order[:status]
            order.updated_at       = TimeDate(order[:updated_at][1:end-1])
            order.filled_at        = TimeDate(order[:filled_at][1:end-1])
            order.submitted_at     = TimeDate(order[:submitted_at][1:end-1])
            order.filled_qty       = parse(Int, order[:filled_qty])
            order.filled_avg_price = parse(Float64, order[:filled_avg_price])
        end
    end
end
