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

## Bars

```@docs
Trading.Open
Trading.High
Trading.Low
Trading.Close
Trading.Volume
```

## Indicators

Indicator data is generated from incoming `bar` data by the [`indicator systems`](@ref indicator_systems) as requested by the [`Strategy`](@ref) systems.
Most of them have two type parameters designating the `window` or `horizon` of the indicator. For example the [`SMA{20, Close}`](@ref SMA)
closing price simple moving average indicator shows at a given timestamp the average of the closing prices of the 20 previous bars.

Accessing this data can be done through a [`Trader`](@ref), e.g.:
```julia
trader = Trader(broker, tickers=["MSFT"])

trader["MSFT"][Trading.SMA{20, Trading.Close}]
```
provided that it was generated.
See [`Strategies`](@ref) for more information.

### Data

```@docs
Trading.SMA
Trading.MovingStdDev
Trading.EMA
Trading.RSI
Trading.Bollinger
Trading.Sharpe
```
### Systems (@id indicator_systems)
```@docs
Trading.SMACalculator
Trading.MovingStdDevCalculator
Trading.EMACalculator
Trading.RSICalculator
Trading.BollingerCalculator
Trading.SharpeCalculator
```

## General Data

```@docs
Trading.LogVal
Trading.Difference
Trading.RelativeDifference

Trading.LogValCalculator
Trading.DifferenceCalculator
Trading.RelativeDifferenceCalculator
```

