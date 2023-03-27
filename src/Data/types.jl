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

abstract type AbstractDataProvider end
abstract type AbstractTradingProvider end


# Broker Interface
abstract type AbstractBroker end

subscibe(::AbstractBroker, ::WebSocket, ::String) = throw(MethodError(subscribe))
bars(::AbstractBroker, ::Vector)                  = throw(MethodError(bars))
authenticate_data(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_data))

abstract type AbstractRealtimeDataProvider <: AbstractDataProvider end

struct AuthenticationException <: Exception
    e
end

function Base.showerror(io::IO, err::AuthenticationException, args...)
    println(io, "AuthenticationException:")
    showerror(io, err.e, args...)
end


const HistoricalTradeDataDict = Dict{String, TimeArray{Any, 2, TimeDate, Matrix{Any}}}
const HistoricalQuoteDataDict = Dict{String, TimeArray{Any, 2, TimeDate, Matrix{Any}}}
const HistoricalBarDataDict = Dict{Tuple{String, Period}, TimeArray{Float64, 2, TimeDate, Matrix{Float64}}}

"""
   HistoricalDataProvider

"""
Base.@kwdef mutable struct HistoricalDataProvider{B <: AbstractBroker} <: AbstractDataProvider
    broker::B
    
    bar_data::HistoricalBarDataDict     = HistoricalBarDataDict()
    trade_data::HistoricalTradeDataDict = HistoricalTradeDataDict()
    quote_data::HistoricalQuoteDataDict = HistoricalQuoteDataDict()
    
    clock::Clock = Clock(clock(), Millisecond(1))
    last::TimeDate = TimeDate(0)
end

HistoricalDataProvider(b::AbstractBroker; kwargs...)  = HistoricalDataProvider(; broker=b, kwargs...)

function retrieve_data(provider::HistoricalDataProvider, set, key, start, stop, args...; kwargs...)
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
    

function bars(provider::HistoricalDataProvider, ticker, start, stop=clock(); timeframe::Period, kwargs...)
    
    start = round(start, typeof(timeframe), RoundDown)
    stop  = round(stop, typeof(timeframe), RoundUp)

    retrieve_data(provider, provider.bar_data, (ticker, timeframe), start, stop, Float64; section="bars", timeframe=timeframe, kwargs...)
end

quotes(provider::HistoricalDataProvider, ticker, args...; kwargs...) =
    retrieve_data(provider, provider.quote_data, ticker, args...; section="quotes", kwargs...)
    
trades(provider::HistoricalDataProvider, ticker, args...; kwargs...) = 
    retrieve_data(provider, provider.trade_data, ticker, args...; section="trades", kwargs...)


function Base.open(func::Function, dataprovider::HistoricalDataProvider)
    try
        func(dataprovider)
    catch e
        if !(e isa InterruptException)
            rethrow(e)
        end
    end
end

function register!(dp::HistoricalDataProvider, ticker, start=nothing,stop=nothing; timeframe=nothing)
    if !any(x-> first(x) == ticker, keys(dp.bar_data))
        start     = start === nothing ? minimum(x->timestamp(x)[1],   values(dp.bar_data)) : start
        stop      = stop === nothing  ? maximum(x->timestamp(x)[end], values(dp.bar_data)) : stop
        timeframe = timeframe === nothing ? minimum(x->last(x), keys(dp.bar_data)) : timeframe
        bars(dp, ticker, start, stop, timeframe=timeframe)
    end
end

#TODO Not Broker Agnostic
function HTTP.receive(dp::HistoricalDataProvider)
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
   RealtimeDataProvider

"""
Base.@kwdef mutable struct RealtimeDataProvider{B <: AbstractBroker} <: AbstractDataProvider
    broker::B
    ws::Union{Nothing, WebSocket} = nothing
end

RealtimeDataProvider(b::AbstractBroker; kwargs...) = RealtimeDataProvider(;broker=b, kwargs...)

function Base.open(func::Function, dataprovider::RealtimeDataProvider)
    HTTP.open(data_stream_url(dataprovider.broker)) do ws
        
        if !authenticate_data(dataprovider.broker, ws)
            error("couldn't authenticate")
        end
        
        try
            dataprovider.ws = ws
            func(dataprovider)
        catch e
            showerror(stdout, e, catch_backtrace())
            if !(e isa InterruptException)
                rethrow(e)
            end
        finally
            dataprovider.ws=nothing
        end
        
    end
end

function register!(dp::RealtimeDataProvider, ticker, args...; kwargs...)
    if dp.ws !== nothing
        subscribe(dp.broker, dp.ws, ticker)
    end
end

function HTTP.receive(dp::RealtimeDataProvider)
    msg = JSON3.read(receive(dp.ws))
    return bars(dp.broker, msg)
end
                         
Base.@kwdef struct DataDistributor{DP <: AbstractDataProvider}
    provider::DP
    queues::Dict{String, Channel} = Dict{String,Channel}()
end

DataDistributor(provider::AbstractDataProvider; kwargs...) = DataDistributor(;provider=provider, kwargs...)

function register!(ds::DataDistributor, queue::Channel, ticker::String, args...; kwargs...)
    ds.queues[ticker] = queue
    register!(ds.provider, ticker, args...; kwargs...)
end

function register!(ds::DataDistributor, l::DataLedger, args...; kwargs...)
    ch = Channel{Tuple{TimeDate, Tuple{Float64, Float64, Float64, Float64, Int}}}(c -> loop(c, l), spawn=true)
    register!(ds, ch, l.ticker, args...; kwargs...)
end

function loop(ds::DataDistributor)
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





















