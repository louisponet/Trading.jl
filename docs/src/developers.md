# Developers
```@meta
CurrentModule = Trading
```
## Implementing a new [`AbstractBroker`](@ref)

We will use [`AlpacaBroker`](@ref) as an example for how to implement the [`AbstractBroker`](@ref) interface.

```julia
Base.@kwdef mutable struct AlpacaBroker <: AbstractBroker
    key_id::String
    secret_key::String
    cache::DataCache = DataCache()
    rate::Int = 200
    last::TimeDate = current_time()
    @atomic nrequests::Int

    function AlpacaBroker(key_id, secret_key, cache, rate, last, nrequests)
        try
            header = ["APCA-API-KEY-ID" => key_id, "APCA-API-SECRET-KEY" => secret_key]
            testurl = URI("https://paper-api.alpaca.markets/v2/clock")
            resp = HTTP.get(testurl, header)
        catch e
            throw(AuthenticationException(e))
        end
        return new(key_id, secret_key, cache, rate, last, nrequests)
    end
end
```
`key_id` and `secret_key` are used in the constructor for authentication verification, and later on for making api calls.
However, these are not assumed to be present and are thus not part of the interface.

### `.cache` [`DataCache`](@ref)
The functions:
- `bars(broker)`
- `quotes(broker)`
- `trades(broker)`
are defined for an `AbstractBroker`, but assume that the `AbstractBroker` has a field `.cache` which is a [`DataCache`](@ref) so
it is advised for any `AbstractBroker` to follow the convention that it has a `.cache` field.

### Wrapper Broker
If you would want to construct a "wrapper" broker, i.e. wrapping the `broker` which supplies the actual API to alter its default behavior
([`HistoricalBroker`](@ref) is an example of this), you should overload the `broker(broker)` function to return the "actual" broker:

```julia
broker(b::HistoricalBroker) = b.broker
broker(b::AlpacaBroker) = b
```

### `data_query`
Next up is the `data_query(broker, ticker, start, stop, args...; section = ["bars" or "quotes" or"trades"], [timeframe=DateTime if section == "bars"])` function,
which performs the actual api calls to retrieve either `bars`, `quotes` or `trades` from the `broker`. What to retrieve is communicated through the `section` kwarg, and in the case of `bars` it will be called using the `timeframe` kwarg.
This should return a `TimeFrame`.

### Bars
The `bars(broker, msg::Vector)` function should be overloaded to be used in [`BarStream`](@ref) to parse incoming bar updates. It should return
a `Vector` of `(ticker, (datetime, (bar_open, bar_high, bar_low, bar_close, bar_volume)))`:
```julia
function bars(::Union{AlpacaBroker,MockBroker}, msg::AbstractVector)
    return map(filter(x -> x[:T] == "b", msg)) do bar
        ticker = bar[:S]
        return ticker, (parse_time(bar[:t]), (bar[:o], bar[:h], bar[:l], bar[:c], bar[:v]))
    end
end
```

The function `subscribe_bars(broker, ticker, websocket)` should be overloaded in order to communicate to a [`BarStream`](@ref) which `tickers` we want to receive updates for.

`data_stream_url(broker)` should point to a url from which we can stream bar update data.
`authenticate_data(broker)` is called just after opening the stream.

### Orders
The first function to overload is [`submit_order(broker, order::EntityState{Purchase or Sale})`](@ref submit_order) which actually submites the orders.
I think the `AlpacaBroker` one can be used with other Brokers, given that a couple of overloads are defined, but I'm not sure if the structure
would always be the same.

Next up is `receive_order(broker, websocket)` which is called by the `trading_task` to listen to Order updates and thus potentially portfolio updates (when filled).
It should return an [`Order`](@ref).

To be able to open the [`OrderStream`](@ref) `trading_stream_url(broker)` should be overloaded and `authenticate_trading(broker, websocket)` which also sends
the right message to start listening to the updates.

### Account Details
Upon construction a [`Trader`](@ref) will fill out the current portfolio by calling `account_details(broker)` which should return `(cash, positions)` where
`positions = [(ticker, quantity), (ticker, quantity), ...]`.

## References
```@docs
DataCache
```
