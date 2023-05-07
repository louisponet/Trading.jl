@tree_component struct Trade
    price::Float64
    quantity::Float64
end

"""
    trades(broker, asset, start, stop)

Returns the trades made for `asset` between `start` and `stop`.
When using [`AlpacaBroker`](@ref) see the [Trade Object](https://alpaca.markets/docs/api-references/market-data-api/stock-pricing-data/historical/#trades)
documentation for further reference.

# Example
```julia
broker = AlpacaBroker(<key_id>, <secret_key>)

trades(broker, "AAPL", DateTime("2022-01-01T14:30:00"), DateTime("2022-01-01T14:31:00"))
```
"""
trades(b::AbstractBroker) = broker(b).cache.trade_data
function trades(broker::AbstractBroker, asset, args...; kwargs...)
    return retrieve_data(broker, trades(broker), asset, args...; section = "trades",
                         kwargs...)
end
function trades(::Union{AlpacaBroker,MockBroker}, msg::AbstractVector)
    return map(filter(x -> x[:T] == "t", msg)) do t
        asset = t[:S]
        return asset, (parse_time(t[:t]), Trade(t[:p], t[:s]))
    end
end


function subscribe_trades(::AlpacaBroker, asset::Asset, ws::WebSocket)
    return send(ws, JSON3.write(Dict("action" => "subscribe",
                                     "trades" => [asset.ticker])))
end

function subscribe_trades(::HistoricalBroker, asset::Asset, ws)
    nothing
end

