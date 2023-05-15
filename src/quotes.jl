"""
    quotes(broker, asset, start, stop)

Returns the quotes made for `asset` between `start` and `stop`.
When using [`AlpacaBroker`](@ref) see the [Quote Object](https://alpaca.markets/docs/api-references/market-data-api/stock-pricing-data/historical/#quotes)
documentation for further reference.

# Example
```julia
broker = AlpacaBroker(<key_id>, <secret_key>)

quotes(broker, "AAPL", DateTime("2022-01-01T14:30:00"), DateTime("2022-01-01T14:31:00"))
```
"""
quotes(b::AbstractBroker) = broker(b).cache.quotes_data
function quotes(broker::AbstractBroker, asset, args...; kwargs...)
    return retrieve_data(broker, quotes(broker), asset, args...; section = "quotes",
                         kwargs...)
end

function quotes(::Union{AlpacaBroker,MockBroker}, msg::AbstractVector)
    return map(filter(x -> x[:T] == "q", msg)) do q
        asset = q[:S]
        return asset, (parse_time(q[:t]), Ask(q[:ap], q[:as]), Bid(q[:bp], q[:bs]))
    end
end


function parse_quote(b::AlpacaBroker, q)
    return (ask_price = q[:ap], bid_price = q[:bp])
end

function latest_quote(b::AlpacaBroker, asset::Asset)
    if asset isa UnknownAsset
        return nothing
    end
    resp = HTTP.get(quote_url(b, asset), header(b))

    if resp.status != 200
        error("something went wrong while asking latest quote")
    end
    body = JSON3.read(resp.body)
    return haskey(body, :quote) ? parse_quote(b, body[:quote]) : parse_quote(b, body[:quotes][asset.ticker])
end

function latest_quote(broker::HistoricalBroker, asset)
    qs = retrieve_data(broker, quotes(broker), asset, broker.clock.time,
                       broker.clock.time + Second(1); section = "quotes")
    if isempty(qs)
        return nothing
    end
    q = qs[1]
    return parse_quote(broker.broker,
                       NamedTuple([s => v for (s, v) in zip(colnames(q), values(q))]))
end

"""
Returns the latest NBBO quote.
"""
function latest_quote(a::AssetLedger)
    return a.latest_quote
end

function subscribe_quotes(::AlpacaBroker, asset::Asset, ws::WebSocket)
    return send(ws, JSON3.write(Dict("action" => "subscribe",
                                     "quotes" => [asset.ticker])))
end
function subscribe_quotes(::HistoricalBroker, asset::Asset, ws)
    nothing
end


# TODO requires :c , :o etc
function price(broker::HistoricalBroker, price_t, asset)
    @assert haskey(bars(broker), (asset, broker.clock.dtime)) "Ticker $asset not in historical bar data"

    bars_ = bars(broker)[(asset, broker.clock.dtime)]

    if isempty(bars_)
        return nothing
    end

    first_t = timestamp(bars_)[1]

    price_t = broker.clock.time

    if price_t < first_t
        return values(bars_[1][:o])[1]
    end

    last_t = timestamp(bars_)[end]
    if price_t > last_t
        return values(bars_[end][:c])[1]
    end

    tdata = bars_[price_t]
    while tdata === nothing
        price_t -= broker.clock.dtime
        tdata = bars_[price_t]
    end
    return values(tdata[:o])[1]
end

"""
    current_price(broker, asset)
    current_price(trader, asset)

Return the current price of an asset.
"""
function current_price(broker::AbstractBroker, args...)
    return price(broker, current_time(broker), args...)
end

function current_price(broker::AlpacaBroker, asset)
    dat = latest_quote(broker, asset)
    return dat === nothing ? nothing : (dat[1] + dat[2]) / 2
end

function current_price(t::Trader, asset)
    l = get(t.asset_ledgers, asset, nothing)
    if l !== nothing && l.latest_quote[2].price != 0 
        q = l.latest_quote
        return (q[2].price + q[3].price) / 2
    else
        return current_price(t.broker, asset)
    end
end
