# Strategies

As with any other functionality in `Trading`, `Strategies` are represented by `Systems` and thus are treated on completely equal footing with the core functionality.
There are three main parts that need to be implemented for a `Strategy` to be used: the `struct`, the `Overseer.update` function, and the `Overseer.requested_components` function.
This latter one will be used to determine which [`Indicator`](@ref Indicators) systems need to be running on the [`TickerLedgers`](@ref TickerLedger) in order to produce
the [`Indicators`](@ref) that are used by the `Strategy`.
The `update` function of a `Strategy` `System` is ran periodically after the `update` functions for the other `Systems` that make the rest of the [`Trader`](@ref) tick.

## Example
As an example we will implement a very simple slow/fast moving average strategy, i.e. `SowFast`.
The goal is that we can later use it in our [`Trader`](@ref) in to following way:

```julia
trader = Trader(broker; strategies = [Strategy(:slowfast, [SlowFast()]) => ["stock1", "stock2"]),

```julia
struct SlowFast <: System end

Overseer.requested_components(::SlowFast) = (Trading.SMA{50, Trading.Close}, Trading.SMA{200, Trading.Close})
```

These two lines define the `Strategy` type and signals that we want the `Trading.SMA{50, Trading.Close}, Trading.SMA{200, Trading.Close}` [`Indicators`](@ref) to be present in the [`TickerLedgers`](@ref).

We then implement the following `update` function that will be executed periodically:
```julia
function Overseer.update(s::SlowFast, t::Trader, ticker_ledgers::TickerLedger)
    for ticker_ledger in ticker_ledgers
        for e in new_entities(ticker_ledger, s)
            lag_e = lag(e, 1)
            
            if lag_e === nothing
                continue
            end
            curpos = current_position(t, ticker)

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

For each of the
