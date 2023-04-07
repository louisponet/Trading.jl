"""
    bars(broker, ticker, start, stop; timeframe, kwargs...)

Retrieve the bar data for `ticker` from `start` to `stop` and with an interval of `timeframe`.
When using [`AlpacaBroker`](@ref) see the [Bar Object](https://alpaca.markets/docs/api-references/market-data-api/stock-pricing-data/historical/#bars)
documentation for further reference.

# Example
```julia
broker = AlpacaBroker(<key_id>, <secret_key>)

bars(broker, "AAPL", DateTime("2022-01-01T00:00:00"), DateTime("2023-01-01T00:00:00")l timeframe = Minute(1))
```

The above will retrieve 2022 bar data "AAPL" on a Minute resolution. 
"""
bars(b::AbstractBroker) = broker(b).cache.bar_data

function bars(broker::AbstractBroker, ticker, start, stop=current_time(); timeframe::Period, kwargs...)
    
    start = round(start, typeof(timeframe), RoundDown)
    stop  = round(stop, typeof(timeframe), RoundUp)

    t = retrieve_data(broker, bars(broker), (ticker, timeframe), start, stop, Float64; section="bars", timeframe=timeframe, kwargs...)
end

function bars(::Union{AlpacaBroker, MockBroker}, msg::AbstractVector)
    return map(filter(x->x[:T] == "b", msg)) do bar
        ticker = bar[:S]
        ticker, (parse_time(bar[:t]), (bar[:o], bar[:h], bar[:l], bar[:c], bar[:v]))
    end
end

function subscribe_bars(::AlpacaBroker, ticker::String, ws::WebSocket)
    send(ws, JSON3.write(Dict("action" => "subscribe",
                              "bars"  => [ticker])))
end

function subscribe_bars(dp::HistoricalBroker, ticker::String, start=nothing,stop=nothing; timeframe=nothing)
    if !any(x-> first(x) == ticker, keys(bars(dp)))
        start     = start === nothing ? minimum(x->timestamp(x)[1],   values(bars(dp))) : start
        stop      = stop === nothing  ? maximum(x->timestamp(x)[end], values(bars(dp))) : stop
        timeframe = timeframe === nothing ? minimum(x->last(x), keys(bars(dp))) : timeframe
        bars(dp, ticker, start, stop, timeframe=timeframe)
    end
    return nothing
end

function receive_bars(b::AlpacaBroker, ws)
    bars(b, JSON3.read(receive(ws)))
end

last_time(dp::HistoricalBroker) = maximum(x->timestamp(x)[end], values(bars(dp)))

function receive_bars(dp::HistoricalBroker, args...)
    wait(dp.send_bars)
    reset(dp.send_bars)
    curt = dp.clock.time
    msg = Tuple{String, Tuple{DateTime, NTuple{5,Float64}}}[]
    while isempty(msg) && dp.clock.time <= last_time(dp) 
        dp.clock.time += dp.clock.dtime
        for (ticker, frame) in bars(dp)
            
            dat = frame[dp.clock.time]
            
            dat === nothing && continue
            
            vals = values(dat)
            push!(msg, (first(ticker), (timestamp(dat)[1], (view(vals, 1:5)...,))))
        end
    end
    dp.last = dp.clock.time
    return msg
end
            
"""
    BarStream

Supplies a stream of bars from a broker.
Can be created by calling [`bar_stream`](@ref) on an [`AbstractBroker`](@ref).
See [`receive`](@ref) and [`register!`](@ref) for more information.
"""
struct BarStream{B<:AbstractBroker, W}
    broker::B
    ws::W
end
HTTP.receive(b::BarStream) = receive_bars(b.broker, b.ws)

WebSockets.isclosed(b::BarStream) = WebSockets.isclosed(b.ws)
WebSockets.isclosed(b::BarStream{<:HistoricalBroker}) = b.broker.clock.time > last_time(b.broker)

register!(b::BarStream, ticker) = subscribe_bars(b.broker, ticker, b.ws)

function bar_stream(func::Function, broker::AlpacaBroker)
    HTTP.open(data_stream_url(broker)) do ws
        
        if !authenticate_data(broker, ws)
            error("couldn't authenticate")
        end
        
        try
            return func(BarStream(broker, ws))
        catch e
            showerror(stdout, e, catch_backtrace())
            if !(e isa InterruptException)
                rethrow(e)
            end
        end
        
    end
end

function bar_stream(func::Function, broker::HistoricalBroker)
    try
        return func(BarStream(broker, nothing))
    catch e
        if !(e isa InterruptException)
            rethrow(e)
        end
    end
end
