# Strategies

As with any other functionality in `Trading`, `Strategies` are represented by `Systems` and thus are treated on completely equal footing with the core functionality.
There are three main parts that need to be implemented for a `Strategy` to be used: the `struct`, the `Overseer.update` function, and the `Overseer.requested_components` function.
This latter one will be used to determine which [`Indicator`](@ref Indicators) systems need to be running on the [`TickerLedgers`](@ref TickerLedger) in order to produce
the [`Indicators`](@ref) that are used by the `Strategy`.
The `update` function of a `Strategy` `System` is ran periodically after the `update` functions for the other `Systems` that make the rest of the [`Trader`](@ref) tick.

## Example
As an example we will implement a very simple slow/fast moving average strategy.

```julia
struct SlowFast <: System end

Overseer.requested_components(::SlowFast) = (Trading.SMA{50, Trading.Close}, Trading.SMA{200, Trading.Close})
```

These two lines define the `Strategy` type and signals that we want the `Trading.SMA{50, Trading.Close}, Trading.SMA{200, Trading.Close}` [`Indicators`](@ref) to be present in the [`TickerLedgers`](@ref).

We then implement the following `update` function that will be executed periodically:
```julia
function Overseer.update(::SlowFast, t::Trader)

    for (ticker, ticker_ledger) in t.ticker_ledgers
        for 
    end
end
```
