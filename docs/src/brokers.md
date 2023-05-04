# Brokers
```@meta
CurrentModule=Trading
```
An [`AbstractBroker`](@ref) signifies the interface between the local [`Trader`](@ref) and an external party that supplies data, and potentially executes orders and holds the user's portfolio.
The current brokers are:
- [`AlpacaBroker`](@ref): the main "real" broker
- [`MockBroker`](@ref): behaves similarly to a real broker but with random data
- [`HistoricalBroker`](@ref): wraps another broker to supply historical data when [`BackTesting`](@ref BackTester)

## Data
### [Historical](@id historical_data)
A slew of historical data can be requested through a broker e.g
```@example
using Trading#hide
broker = AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"])
bars(broker, Stock("AAPL"), DateTime("2023-04-05T00:00:00"), DateTime("2023-04-05T22:00:00"), timeframe=Minute(1))
```

There are so far three such functions:
- [`bars`](@ref): retrieve historical bar data
- [`trades`](@ref): retrieve historical data on trades
- [`quotes`](@ref): retrieve historical data on quotes

### Realtime
The [Broker](@ref Brokers) can be queried for the [`current_price`](@ref) of an asset, and `bar` data can be streamed in 
by calling [`bar_stream`](@ref), either in realtime from a realtime broker (e.g. [`AlpacaBroker`](@ref)), or faked realtime when using a [`HistoricalBroker`](@ref).

For example, internally [`start_data`](@ref) essentially looks like:
```julia
bar_stream(trader.broker) do stream
    for (asset, q) in trader.asset_ledgers
        register!(stream, asset)
    end
    while !trader.stop_data
        bars = receive(stream)
        # distribute bars to asset ledgers
    end
end
```
See [`register!`](@ref) and [`receive`](@ref) for further information.

## Orders
Orders can be submitted with [`submit_order`](@ref) and updates to them can be streamed in with [`order_stream`](@ref).
Similarly to [`start_data`](@ref), [`start_trading`](@ref) opens an order stream so order updates can be passed along to the
[`Order`](@ref) `Component`:
```julia
order_stream(trader.broker) do stream
    while !trader.stop_trading
        order = receive(stream)
        # update Order component
    end
end
```
In general, however, these functions should not be used and one should rely on the core systems of the [`Trader`](@ref) to submit and handle orders through [`Purchase`](@ref) and [`Sale`](@ref) `Components`.
See [Portfolio](@ref) for more info.

## References

```@docs
Trading.AbstractBroker
Trading.AlpacaBroker
Trading.HistoricalBroker
Trading.MockBroker
bars
trades
quotes
current_price
Trading.BarStream
Trading.bar_stream
Trading.HTTP.receive(b::Trading.BarStream)
Trading.register!(b::Trading.BarStream, asset)
Trading.submit_order
Trading.OrderStream
Trading.order_stream
```
