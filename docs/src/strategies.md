# Strategies

As with any other functionality in `Trading`, `Strategies` are represented by `Systems` and thus are treated on completely equal footing with the core functionality.
There are three main parts that need to be implemented for a `Strategy` to be used: the `struct`, the `Overseer.update` function, and the `Overseer.requested_components` function.
This latter one will be used to determine which [`Indicator`](@ref Indicators) systems need to be running on the [`TickerLedgers`](@ref TickerLedger) in order to produce
the [`Indicators`](@ref) that are used by the `Strategy`.
The `update` function of a `Strategy` `System` is ran periodically after the `update` functions for the other `Systems` that make the rest of the [`Trader`](@ref) tick.

## Strategy Definition
As an example we will implement a very simple slow/fast moving average strategy, i.e. `SlowFast`.
The goal is that we can later use it in our [`Trader`](@ref) in to following way:

```julia
trader = Trader(broker; strategies = [Strategy(:slowfast, [SlowFast()], tickers=["stock1", "stock2"])])
```

We begin by defining the `SlowFast` `System` and the components that it requests to be present in [`TickerLedgers`](@ref TickerLedger).
They will be automatically created as tick data arrives.
```@example strategy
using Trading#hide
using Trading.Strategies#hide
using Trading.Basic#hide
using Trading.Indicators#hide
using Trading.Portfolio#hide
struct SlowFast <: System end

Overseer.requested_components(::SlowFast) = (SMA{50, Close}, SMA{200, Close})
```
We here request the slow and fast sma components of the closing price ([`SMA{200, Trading.Close}`](@ref Indicators), [`SMA{50, Trading.Close}`](@ref Indicators)).

We then implement the following `update` function that will be executed periodically:
```@example strategy
function Overseer.update(s::SlowFast, t::Trader, ticker_ledgers)
    for ticker_ledger in ticker_ledgers

        ticker = ticker_ledger.ticker

        for e in new_entities(ticker_ledger, s)
            lag_e = lag(e, 1)

            if lag_e === nothing
                continue
            end

            sma_50  = e[SMA{50, Close}].sma
            sma_200 = e[SMA{200, Close}].sma
            
            lag_sma_50 = lag_e[SMA{50, Close}].sma
            lag_sma_200 = lag_e[SMA{200, Close}].sma

            if sma_50 > sma_200 && lag_sma_50 < lag_sma_200
                Entity(t, Sale(ticker, 1.0))
            elseif sma_50 < sma_200 && lag_sma_50 > lag_sma_200
                Entity(t, Purchase(ticker, 1.0))
            end

        end
    end
end
```

Let's go through this line by line:
```julia
for ticker_ledger in ticker_ledgers
```
We loop through each of the ticker ledgers that this strategy was created for (i.e. `stock1`, `stock2`).

```julia
for e in new_entities(ticker_ledger, s)
```
Then, we ask for the [`new_entities`](@ref) in the [`TickerLedger`](@ref) that have
in this case both the `SMA{200, Close}` and `SMA{50,Close}` components. Each of these entities will be touched once and only once.

```julia
lag_e = lag(e, 1)
```
Since we are looking for crossings between the two moving averages, we ask for the entity of the previous time. If there was none, i.e. `e` is the very
first entity, `lag(e, 1)` will return `nothing` and so we don't do anything.

```julia
sma_50  = e[SMA{50, Close}].sma
sma_200 = e[SMA{200, Close}].sma

lag_sma_50 = lag_e[SMA{50, Close}].sma
lag_sma_200 = lag_e[SMA{200, Close}].sma
```
We retrieve the sma's for both the current and lagged `entity`.

```julia
if sma_50 > sma_200 && lag_sma_50 < lag_sma_200
    Entity(t, Sale(ticker, 1.0))
elseif sma_50 < sma_200 && lag_sma_50 > lag_sma_200
    Entity(t, Purchase(ticker, 1.0))
end
```
If the fast sma crosses above the slow sma, we assume the stock is overbought and we sell it by creating an `Entity` with a  [`Sale`](@ref) component.
Vice versa, If the fast sma crosses below the slow sma, we assume the stock is oversold and we buy it by creating an `Entity` with a  [`Buy`](@ref) component.

## BackTesting

The framework is set up to treat backtesting and realtime trading in completely identical ways, and we can therefore backtest
our strategy on some historical data.

We first define the broker from which to pull the historical data, in this case we use [`AlpacaBroker`](@ref) with our `key_id` and `secret`.
We then use it in the [`HistoricalBroker`](@ref) which supplies data in the same way of a realtime broker would.

We then set up the strategy for the `MSFT` and `AAPL` tickers, define our `BackTester` with our data range and interval `dt`.

!!! note

    When using daily data (e.g. `dt=Day(1)`), it is important to specify `only_day=false`, otherwise nothing will happen since our strategy will only run during trading hours, and no daily bars will have a timestamp inside those hours.

Finally we use [`start`](@ref) to loop through all the days and execute the strategy, possible trades, and any other behavior as if it is realtime.

```@example strategy
broker = HistoricalBroker(AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"]))

strategy = Strategy(:slowfast, [SlowFast()], tickers=["MSFT", "AAPL"])

trader = BackTester(broker, start = DateTime("2015-01-01T00:00:00"),
                            stop = DateTime("2020-01-01T00:00:00"),
                            dt = Day(1),
                            strategies = [strategy],
                            cash = 1000,
                            only_day=false)
start(trader)
```

To perform further analysis we can transform the `trader` data into a standard `TimeArray` as:
```@example strategy
ta = TimeArray(trader)
```
by using [`Plots`](https://juliaplots.org) we can then plot certain columns in the `TimeArray`, e.g. the portfolio value:
```@example strategy
using Plots
plot(ta[:value])
```

We can see that this strategy is not particularly succesful.

See [`Slow Fast Strategy`](@ref slow_fast_id) for a full runnable version of this strategy.
