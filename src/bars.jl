"""
    bars(broker, asset, start, stop; timeframe, kwargs...)

Retrieve the bar data for `asset` from `start` to `stop` and with an interval of `timeframe`.
When using [`AlpacaBroker`](@ref) see the [Bar Object](https://alpaca.markets/docs/api-references/market-data-api/stock-pricing-data/historical/#bars)
documentation for further reference.

# Example
```julia
broker = AlpacaBroker(<key_id>, <secret_key>)

bars(broker, Stock("AAPL"),
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

last_time(dp::HistoricalBroker) = maximum(x -> timestamp(x)[end], values(bars(dp)))
