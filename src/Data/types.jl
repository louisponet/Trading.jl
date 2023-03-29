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

delete_all_orders!(b::AbstractBroker) = HTTP.delete(order_url(b), header(b))
#TODO cleanup interface 
# subscibe(::AbstractBroker, ::WebSocket, ::String) = throw(MethodError(subscribe))
# bars(::AbstractBroker, ::Vector)                  = throw(MethodError(bars))
# authenticate_data(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_data))
# authenticate_trading(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_trading))
# latest_quote(::AbstractBroker, ticker::String)

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

broker(b::AbstractBroker) = b
stock_query(b::AbstractBroker, args...; kwargs...) = stock_query(broker(b), args...; kwargs...)

function retrieve_data(provider::AbstractBroker, set, key, start, stop, args...; kwargs...)
    ticker = key isa Tuple ? first(key) : key

    dt = key isa Tuple ? last(key) : Millisecond(1)
    @assert stop === nothing || start <= stop ArgumentError("start should be <= stop")
    
    if haskey(set, key)

        data = set[key]
        timestamps = timestamp(data)
        if stop !== nothing
            if start <= stop < timestamps[1]
                new_data = stock_query(provider, ticker, start, stop, args...; kwargs...)
                
                if new_data !== nothing
                    set[key] = vcat(new_data, data)
                end
                
                return new_data
                
            elseif timestamps[end] < start <= stop
                new_data = stock_query(provider, ticker, start, stop, args...; kwargs...)

                if new_data !== nothing
                    set[key] = vcat(data, new_data)
                end
                
                return new_data
                
            end
        end
            
        if timestamps[1] <= start 
            out_data = from(data, start)
        else
            next_stop = timestamps[1] - dt
            new_data = stock_query(provider, ticker, start, next_stop, args...; kwargs...)
            
            if new_data !== nothing
                out_data = vcat(new_data, data)
                set[key] = out_data
            else
                out_data = data
            end

        end
        
        if stop === nothing
            return out_data
        end
        
        if timestamps[end] >= stop
            return to(out_data, stop)
        else
            next_start = timestamps[end] + dt
            
            new_data = stock_query(provider, ticker, next_start, stop, args...; kwargs...)
            if new_data !== nothing
                out_data = vcat(out_data, new_data)
                set[key] = vcat(data, new_data)
            end

            return out_data
        end
    end
    data = stock_query(provider, ticker, start, stop, args...; kwargs...)
    if data !== nothing
        set[key] = data
    end
    
    return data
end

function bars(provider::AbstractBroker, ticker, start, stop=clock(); timeframe::Period, kwargs...)
    
    start = round(start, typeof(timeframe), RoundDown)
    stop  = round(stop, typeof(timeframe), RoundUp)

    retrieve_data(provider, provider.bar_data, (ticker, timeframe), start, stop, Float64; section="bars", timeframe=timeframe, kwargs...)
end

quotes(provider::AbstractBroker, ticker, args...; kwargs...) =
    retrieve_data(provider, provider.quote_data, ticker, args...; section="quotes", kwargs...)
    
trades(provider::AbstractBroker, ticker, args...; kwargs...) = 
    retrieve_data(provider, provider.trade_data, ticker, args...; section="trades", kwargs...)

function current_price(provider::AbstractBroker, ticker)
    dat = latest_quote(provider, ticker)
    return (dat[1] + dat[2])/2
end

struct BarStream{B<:AbstractBroker, W}
    broker::B
    ws::W
end
HTTP.receive(b::BarStream) = receive_bars(b.broker, b.ws)

register!(b::BarStream, ticker) = subscribe_bars(b.broker, ticker, b.ws)

"""
    DataPipeline

Handles distribution of data to the different [`DataLedgers`](@ref DataLedger) through the associated
`queues`.
By using either a [`HistoricalDataSource`](@ref) or [`RealtimeDataSource`](@ref) one can exchange
whether data is streamed from a historical dataset or streamed realtime through a connection to
an external data broker.
"""
Base.@kwdef struct DataPipeline{B <: AbstractBroker}
    broker::B
    queues::Dict{String, Channel} = Dict{String,Channel}()
end

DataPipeline(broker::AbstractBroker; kwargs...) = DataPipeline(;broker=broker, kwargs...)

function attach!(ds::DataPipeline, queue::Channel, ticker::String, args...; kwargs...)
    ds.queues[ticker] = queue
end

"""
    attach!(ds::DataDistributor, l::DataLedger, args...; kwargs...)

Registers a [`DataLedger`](@ref) to `ds`. This creates a `Channel` through which the correct tick data
flows into `l`.
"""
function attach!(ds::DataPipeline, l::DataLedger, args...; kwargs...)
    ch = Channel{Tuple{TimeDate, Tuple{Float64, Float64, Float64, Float64, Int}}}(c -> loop(c, l), 10, spawn=true)
    attach!(ds, ch, l.ticker, args...; kwargs...)
end

function start_stream(ds::DataPipeline, stopevent)
    bar_stream(ds.broker) do stream

        stop = false
        
        registered_tickers = Set{String}()
        
        t1 = @async @stoppable stop while !stop
            for (ticker, q) in ds.queues
                if ticker in registered_tickers
                    continue
                end
                @show ticker
                register!(stream, ticker)
                push!(registered_tickers, ticker)
            end
            sleep(1)
        end
        
        t2 = @async @stoppable stop while !stop
            try
                bars = receive(stream)
                for (ticker, bar) in bars
                    put!(ds.queues[ticker], bar)
                end
            catch e
                if !(e isa InvalidStateException) && !(e isa EOFError)
                    showerror(stdout, e, catch_backtrace())
                end
            end
        end
        stop_task = @async begin
            lock(stopevent)
            try
                while !stop
                    stop = wait(stopevent)
                end
            finally
                unlock(stopevent)
            end
            stream.ws !== nothing && close(stream.ws)
            stop=true
            @info "Closing Data Stream"
        end
        fetch(t1)
        fetch(t2)
        fetch(stop_task)
        @info "Closed Data Stream"
    end
end

"""
    TradingLink

Interface to support executing trades and retrieving account updates.
"""
Base.@kwdef struct TradingLink{B <: AbstractBroker}
    broker::B
    ws::Union{Nothing, WebSocket} = nothing
end

TradingLink(b::AbstractBroker; kwargs...) = TradingLink(;broker=b, kwargs...)

HTTP.receive(trading_link::TradingLink) = receive_order(trading_link.broker, trading_link.ws)

function start_trading(channel::Channel, broker::AbstractBroker, order_comp)
    trading_link(broker) do link

        broker = link.broker

        stop = false
        t1 = @async while true
            try
                order = take!(channel)

                order_comp[order] = submit_order(broker, order)
            catch e
                if !(e isa InvalidStateException)
                    showerror(stdout, e, catch_backtrace())
                else
                    link.ws !== nothing && close(link.ws)
                    stop=true
                    break
                end
            end
        end
        
        t = @async while !stop
            try
                received = receive(link)
                if received === nothing
                    continue
                end
                
                uid = received.id
                   
                id = nothing
                #TODO dangerous when an order would come from somewhere else
                while id === nothing
                    id = findlast(x->x.id == uid, order_comp.data)
                end

                order_comp[id] = received
            catch e
                if !(e isa InvalidStateException) && !(e isa EOFError)
                    showerror(stdout, e, catch_backtrace())
                end
                break
            end
                    
        end
        fetch(t)
        fetch(t1)
        @info "Closed Trading Stream"
    end
end
