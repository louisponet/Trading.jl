"""
    AbstractBroker

Interface for external brokers.
"""
abstract type AbstractBroker end

include("brokers/alpaca.jl")
include("brokers/historical.jl")
include("brokers/mock.jl")

# Broker Interface
#TODO cleanup interface 
# subscibe(::AbstractBroker, ::WebSocket, ::String) = throw(MethodError(subscribe))
# bars(::AbstractBroker, ::Vector)                  = throw(MethodError(bars))
# authenticate_data(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_data))
# authenticate_trading(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_trading))
# latest_quote(::AbstractBroker, asset::String)
# asset_type(::AbstractBroker, position_data)
broker(b::AbstractBroker) = b
function data_query(b::AbstractBroker, args...; kwargs...)
    return data_query(broker(b), args...; kwargs...)
end

"""
    AuthenticationException

Use when throwing a failed authentication to a broker.
"""
struct AuthenticationException <: Exception
    e::Any
end

function Base.showerror(io::IO, err::AuthenticationException, args...)
    println(io, "AuthenticationException:")
    return showerror(io, err.e, args...)
end

# TODO not great
function retrieve_data(broker::AbstractBroker, set, key, start, stop, args...;
                       normalize = false, kwargs...)
    asset = key isa Tuple ? first(key) : key

    dt = key isa Tuple ? last(key) : Millisecond(1)
    @assert stop === nothing || start <= stop ArgumentError("start should be <= stop")

    if haskey(set, key) && !isempty(set[key])
        data = set[key]
        timestamps = timestamp(data)
        if stop !== nothing
            if start <= stop < timestamps[1]
                new_data = data_query(broker, asset, start, stop, args...; kwargs...)

                if new_data !== nothing
                    new_data = normalize ? interpolate_timearray(new_data; kwargs...) :
                               new_data
                    set[key] = vcat(new_data, data)
                end

                return new_data

            elseif timestamps[end] < start <= stop
                new_data = data_query(broker, asset, start, stop, args...; kwargs...)

                if new_data !== nothing
                    new_data = normalize ? interpolate_timearray(new_data; kwargs...) :
                               new_data
                    set[key] = vcat(data, new_data)
                end

                return new_data
            end
        end

        if timestamps[1] <= start
            out_data = from(data, start)
        else
            next_stop = timestamps[1] - dt
            new_data = data_query(broker, asset, start, next_stop, args...; kwargs...)

            if new_data !== nothing
                new_data = normalize ? interpolate_timearray(new_data; kwargs...) : new_data
                out_data = vcat(new_data, data)
                set[key] = out_data
            else
                out_data = data
            end
        end

        if stop === nothing
            return normalize ? interpolate_timearray(out_data; kwargs...) : out_data
        end

        if timestamps[end] >= stop
            tout = to(out_data, stop)
            return normalize ? interpolate_timearray(tout) : tout
        else
            next_start = timestamps[end] + dt
            
            if next_start < stop
                new_data = data_query(broker, asset, next_start, stop, args...; kwargs...)
                if new_data !== nothing
                    new_data = normalize ? interpolate_timearray(new_data; kwargs...) : new_data
                    out_data = vcat(out_data, new_data)
                    set[key] = vcat(set[key], new_data)
                end
            end

            return normalize ? interpolate_timearray(out_data; kwargs...) : out_data
        end
    end
    data = data_query(broker, asset, start, stop, args...; kwargs...)
    if data !== nothing
        data = normalize ? interpolate_timearray(data; kwargs...) : data
        set[key] = data
    end

    return data
end

function receive_data(b::AbstractBroker, ws)
    msg = JSON3.read(receive(ws))
    return (bars = bars(b, msg), quotes = quotes(b,msg), trades=trades(b,msg), orderbook(b, msg)...) 
end


function receive_data(dp::HistoricalBroker, args...)
    wait(dp.send_bars)
    reset(dp.send_bars)
    curt = dp.clock.time
    msg = Tuple{String,Tuple{DateTime,NTuple{5,Float64}}}[]

    while isempty(msg) && dp.clock.time <= last_time(dp)
        dp.clock.time += dp.clock.dtime

        for (asset, frame) in bars(dp)
            dat = frame[dp.clock.time]

            dat === nothing && continue

            vals = values(dat)
            push!(msg, (first(asset).ticker, (timestamp(dat)[1], (view(vals, 1:5)...,))))
        end
    end
    dp.last = dp.clock.time
    
    return (bars = msg,
            quotes = Tuple{String,Tuple{DateTime, Ask, Bid}}[],
            trades = Tuple{String, Tuple{DateTime, Trade}}[],
            bids = Tuple{String, Tuple{DateTime, Bid}}[],
            asks = Tuple{String, Tuple{DateTime, Ask}}[])
end

"""
    DataStream

Supplies a stream of bars from a broker.
Can be created by calling [`data_stream`](@ref) on an [`AbstractBroker`](@ref).
See [`receive`](@ref) and [`register!`](@ref) for more information.
"""
struct DataStream{B<:AbstractBroker,W}
    broker::B
    ws::W
end

"""
    receive(barstream)

Blocking function which will return new bars as soon as they are available.
"""
HTTP.receive(b::DataStream) = receive_data(b.broker, b.ws)

WebSockets.isclosed(b::DataStream) = b.ws === nothing || b.ws.readclosed || b.ws.writeclosed
function WebSockets.isclosed(b::DataStream{<:HistoricalBroker})
    return b.broker.clock.time > last_time(b.broker)
end

"""
    register!(barstream, asset)

Register a asset to the [`DataStream`](@ref) so that [`receive`](@ref) will also
return updates with new bars for `asset`.
"""
function register!(b::DataStream, asset)
    subscribe_bars(b.broker, asset, b.ws)
    subscribe_trades(b.broker, asset, b.ws)
    subscribe_quotes(b.broker, asset, b.ws)
    subscribe_orderbook(b.broker, asset, b.ws)
end

"""
    data_stream(f::Function, broker, a)

Open a bar stream, calls function `f` with a [`DataStream`](@ref) object.
Call [`receive`](@ref) on the [`DataStream`](@ref) to get new bars streamed in,
and [`register!`](@ref) to register assets for which to receive bar updates for.
"""
function data_stream(func::Function, broker::AbstractBroker, T::AssetType.T) 
    HTTP.open(data_stream_url(broker, T)) do ws
        if !authenticate_data(broker, ws)
            error("couldn't authenticate")
        end

        try
            return func(DataStream(broker, ws))
        catch e
            showerror(stdout, e, catch_backtrace())
            if !(e isa InterruptException)
                rethrow()
            end
        end
    end
end

function data_stream(func::Function, broker::HistoricalBroker, ::AssetType.T)
    try
        return func(DataStream(broker, nothing))
    catch e
        if !(e isa InterruptException)
            rethrow()
        end
    end
end

"""
Interface to support executing trades and retrieving account updates. Opened with [`trading_stream`](@ref)
"""
Base.@kwdef struct TradingStream{B<:AbstractBroker}
    broker::B
    ws::Union{Nothing,WebSocket} = nothing
end

TradingStream(b::AbstractBroker; kwargs...) = TradingStream(; broker = b, kwargs...)

HTTP.receive(trading_link::TradingStream) = receive_trades(trading_link.broker, trading_link.ws)
WebSockets.isclosed(trading_link::TradingStream) = trading_link.ws === nothing || trading_link.ws.readclosed || trading_link.ws.writeclosed
WebSockets.isclosed(trading_link::TradingStream{<:HistoricalBroker}) = false

"""
    trading_stream(f::Function, broker::AbstractBroker)

Creates an [`TradingStream`](@ref) to stream order data.
Uses the same semantics as a standard `HTTP.WebSocket`.

# Example
```julia
broker = AlpacaBroker(<key_id>, <secret_key>)

trading_stream(broker) do stream
    order = receive(stream)
end
```
"""
function trading_stream(f::Function, broker::AbstractBroker)
    HTTP.open(trading_stream_url(broker)) do ws
        authenticate_trading(broker, ws)
        @info "Authenticated trading"
        try
            f(TradingStream(broker, ws))
        catch e
            showerror(stdout, e, catch_backtrace())
            if !(e isa InterruptException)
                rethrow()
            end
        end
    end
end

trading_stream(f::Function, broker::HistoricalBroker) = f(TradingStream(broker, nothing))

