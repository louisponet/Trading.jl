# [Tutorial](@id Strategies)
```@meta
CurrentModule = Trading
```

```@docs
Strategy
```
There are three main parts that need to be implemented for a [`Strategy`](@ref) to be used:
- a `System`
- the `Overseer.update` function
- the `Overseer.requested_components` function

This latter one will be used to determine which [`Indicator`](@ref Indicators) systems need to be executed on the data inside each [`AssetLedger`](@ref) in order to produce
the [`Indicators`](@ref Indicators) that are used by the [`Strategy`](@ref).

## Strategy Definition
As an example we will implement a very simple slow/fast moving average strategy, i.e. `SlowFast`.
The goal is that we can later use it in our [`Trader`](@ref) in to following way:

```julia
trader = Trader(broker; strategies = [Strategy(:slowfast, [SlowFast()], assets=[Stock("stock1")])])
```

We begin by defining the `SlowFast` `System` and the components that it requests to be present in [`AssetLedgers`](@ref AssetLedger).
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
function Overseer.update(s::SlowFast, t::Trader, asset_ledgers)
    for asset_ledger in asset_ledgers

        asset = asset_ledger.asset

        for e in new_entities(asset_ledger, s)
            prev_e = prev(e, 1)

            if prev_e === nothing
                continue
            end

            sma_50  = e[SMA{50, Close}].sma
            sma_200 = e[SMA{200, Close}].sma
            
            prev_sma_50 = prev_e[SMA{50, Close}].sma
            prev_sma_200 = prev_e[SMA{200, Close}].sma

            if sma_50 > sma_200 && prev_sma_50 < prev_sma_200
                Entity(t, Sale(asset, 1.0))
            elseif sma_50 < sma_200 && prev_sma_50 > prev_sma_200
                Entity(t, Purchase(asset, 1.0))
            end

        end
    end
end
```

Let's go through this line by line:
```julia
for asset_ledger in asset_ledgers
```
We loop through each of the asset ledgers that this strategy was created for (i.e. `stock1`, `stock2`).

```julia
for e in new_entities(asset_ledger, s)
```
Then, we ask for the [`new_entities`](@ref) in the [`AssetLedger`](@ref) that have
in this case both the `SMA{200, Close}` and `SMA{50,Close}` components. Each of these entities will be touched once and only once.

```julia
prev_e = prev(e, 1)
```
Since we are looking for crossings between the two moving averages, we ask for the entity of the previous time. If there was none, i.e. `e` is the very
first entity, `prev(e, 1)` will return `nothing` and so we don't do anything.

```julia
sma_50  = e[SMA{50, Close}].sma
sma_200 = e[SMA{200, Close}].sma

prev_sma_50 = prev_e[SMA{50, Close}].sma
prev_sma_200 = prev_e[SMA{200, Close}].sma
```
We retrieve the sma's for both the current and previous `entity`.

```julia
if sma_50 > sma_200 && prev_sma_50 < prev_sma_200
    Entity(t, Sale(asset, 1.0))
elseif sma_50 < sma_200 && prev_sma_50 > prev_sma_200
    Entity(t, Purchase(asset, 1.0))
end
```
If the fast sma crosses above the slow sma, we assume the stock is overbought and we sell it by creating an `Entity` with a  [`Sale`](@ref) component.
Vice versa, If the fast sma crosses below the slow sma, we assume the stock is oversold and we buy it by creating an `Entity` with a  [`Purchase`](@ref) component.

## BackTesting

The framework is set up to treat backtesting and realtime trading in completely identical ways, and we can therefore backtest
our strategy on some historical data.

We first define the broker from which to pull the historical data, in this case we use [`AlpacaBroker`](@ref) with our `key_id` and `secret`.
We then use it in the [`HistoricalBroker`](@ref) which supplies data in the same way of a realtime broker would.

We then set up the strategy for the `MSFT` and `AAPL` assets, define our `BackTester` with our data range and interval `dt`.

!!! note

    When using daily data (e.g. `dt=Day(1)`), it is important to specify `only_day=false`, otherwise nothing will happen since our strategy will only run during trading hours, and no daily bars will have a timestamp inside those hours.

Finally we use [`start`](@ref) to loop through all the days and execute the strategy, possible trades, and any other behavior as if it is realtime.

```@example strategy
broker = HistoricalBroker(AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"]))

strategy = Strategy(:slowfast, [SlowFast()], assets=[Stock("MSFT"), Stock("AAPL")])

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
plot(ta[:portfolio_value])
```

We can see that this strategy is not particularly succesful.

See [`Slow Fast Strategy`](@ref slow_fast_id) for a full runnable version of this strategy.

## References
```@docs
Trading.relative
NewEntitiesIterator
```
