# Data

## Historical Acquisition

The current suggested method of historical data acquisition is through the [`AlpacaBroker`](@ref).
There are three types of data that can be retrieved: [`bars`](@ref), [`quotes`](@ref) and [`trades`](@ref).
```@docs
bars
quotes
trades
```

Each of these will return a [`TimeArray`](https://juliastats.org/TimeSeries.jl/dev/timearray/), which can be used e.g. with
[`MarketTechnicals`](https://juliaquant.github.io/MarketTechnicals.jl/stable/) for specialized analysis.
An [`AbstractBroker`](@ref) has an internal cache that will retain previously requested data.

## Data Stream

There are realtime data streams for bars and portfolio/order updates. They follow the same semantics as the standard
[`HTTP.WebSockets.WebSocket`](https://juliaweb.github.io/HTTP.jl/dev/websockets/).

```@docs
Trading.BarStream
Trading.bar_stream
```

```@docs
Trading.OrderStream
Trading.order_stream
```

## Ticker Ledgers
```@docs
Trading.TickerLedger
```
