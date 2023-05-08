"""
    bars(broker, asset, start, stop; timeframe, kwargs...)

Retrieve the bar data for `asset` from `start` to `stop` and with an interval of `timeframe`.
When using [`AlpacaBroker`](@ref) see the [Bar Object](https://alpaca.markets/docs/api-references/market-data-api/stock-pricing-data/historical/#bars)
documentation for further reference.

# Example
```julia
broker = AlpacaBroker(<key_id>, <secret_key>)

bars(broker, "AAPL",
     DateTime("2022-01-01T00:00:00"),
     DateTime("2023-01-01T00:00:00"),
     timeframe = Minute(1))
```

The above will retrieve 2022 bar data "AAPL" on a Minute resolution. 
"""
bars(b::AbstractBroker) = broker(b).cache.bar_data

function bars(broker::AbstractBroker, asset::Asset, start, stop = current_time();
              timeframe::Period, kwargs...)
    start = round(start, typeof(timeframe), RoundDown)
    stop  = round(stop, typeof(timeframe), RoundUp)

    return t = retrieve_data(broker, bars(broker), (asset, timeframe), start, stop,
                             Float64; section = "bars", timeframe = timeframe, kwargs...)
end

function bars(::Union{AlpacaBroker,MockBroker}, msg::AbstractVector)
    return map(filter(x -> x[:T] == "b", msg)) do bar
        asset = bar[:S]
        return asset, (parse_time(bar[:t]), (bar[:o], bar[:h], bar[:l], bar[:c], bar[:v]))
    end
end

function subscribe_bars(::AlpacaBroker, asset::Asset, ws::WebSocket)
    return send(ws, JSON3.write(Dict("action" => "subscribe",
                                     "bars" => [asset.ticker])))
end

function subscribe_bars(dp::HistoricalBroker, asset::Asset, start = nothing,
                        stop = nothing; timeframe = nothing)
    if !any(x -> first(x) == asset, keys(bars(dp)))
        start     = start === nothing ? minimum(x -> timestamp(x)[1], values(bars(dp))) : start
        stop      = stop === nothing ? maximum(x -> timestamp(x)[end], values(bars(dp))) : stop
        timeframe = timeframe === nothing ? minimum(x -> last(x), keys(bars(dp))) : timeframe

        bars(dp, asset, start, stop; timeframe = timeframe)
    end
    return nothing
end

function receive_data(b::AbstractBroker, ws)
    msg = JSON3.read(receive(ws))
    return (bars = bars(b, msg), quotes = quotes(b,msg), trades=trades(b,msg))
end

last_time(dp::HistoricalBroker) = maximum(x -> timestamp(x)[end], values(bars(dp)))

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
    
    return (bars = msg, quotes = Tuple{String,Tuple{DateTime,Ask, Bid}}[], trades = Tuple{String, Tuple{DateTime, Trade}}[])
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
end

"""
    data_stream(f::Function, broker)

Open a bar stream, calls function `f` with a [`DataStream`](@ref) object.
Call [`receive`](@ref) on the [`DataStream`](@ref) to get new bars streamed in,
and [`register!`](@ref) to register assets for which to receive bar updates for.
"""
function data_stream(func::Function, broker::AbstractBroker, ::Type{T}) where {T<:Asset}
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

function data_stream(func::Function, broker::HistoricalBroker, ::Type{<:Asset})
    try
        return func(DataStream(broker, nothing))
    catch e
        if !(e isa InterruptException)
            rethrow()
        end
    end
end
