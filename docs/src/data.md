# Data
```@meta
CurrentModule=Trading
```

## Historical

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

```@docs
Trading.OrderStream
Trading.order_stream
```

## Ticker Ledgers
```@docs
Trading.TickerLedger
```

## Bar Components
Bars are represented internally by the following set of `Components`. Basically they are the standard `ohlc` and a `volume` components.
```@docs
Trading.Open
Trading.High
Trading.Low
Trading.Close
Trading.Volume
```

Bars are streamed by a [`BarStream`](@ref), either in realtime from a realtime broker (e.g. [`AlpacaBroker`](@ref)), or faked realtime when using a [`HistoricalBroker`](@ref).
```@docs
Trading.BarStream
Trading.bar_stream
Trading.HTTP.receive(b::Trading.BarStream)
Trading.register!(b::Trading.BarStream, ticker)
```


## [Indicators](@id Indicators)

Indicator data is generated from incoming `bar` data by the [`indicator systems`](@ref indicator_systems) as requested by the [`Strategy`](@ref Strategies) systems.
Most of them have two type parameters designating the `window` or `horizon` of the indicator. For example the [`SMA{20, Close}`](@ref SMA)
closing price simple moving average indicator shows at a given timestamp the average of the closing prices of the 20 previous bars.

Accessing this data can be done through a [`Trader`](@ref), e.g.:
```julia
trader = Trader(broker, tickers=["MSFT"])

trader["MSFT"][SMA{20, Close}]
```
provided that it was generated.
See [`Strategies`](@ref Strategies) for more information.

### Data

```@docs
Trading.SMA
Trading.MovingStdDev
Trading.EMA
Trading.RSI
Trading.Bollinger
Trading.Sharpe
```
### [Systems](@id indicator_systems)
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
Trading.SingleValIndicator
Trading.LogVal
Trading.Difference
Trading.RelativeDifference

Trading.LogValCalculator
Trading.DifferenceCalculator
Trading.RelativeDifferenceCalculator
```

```@docs
Trading.value
```

