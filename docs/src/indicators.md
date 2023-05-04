# Indicators

```@meta
CurrentModule = Trading
```

The basic `Components` like [`Open`](@ref), [`Close`](@ref), [`High`](@ref), [`Low`](@ref), [`Volume`](@ref) and their [`Difference`](@ref) or [`RelativeDifference`](@ref) components can be used
to generate derived `Components` like:
- [`SMA{horizon, base_T}`](@ref SMA): simple moving average over a window/horizon
- [`EMA{horizon, base_T}`](@ref EMA): exponential moving average over a window/horizon
- [`MovingStdDev{horizon, base_T}`](@ref MovingStdDev): moving standard deviation over a window/horizon
- [`RSI{horizon, base_T}`](@ref RSI): moving relative strength index over a window/horizon
- [`Bollinger{horizon, base_T}`](@ref Bollinger): Up and Down Bollinger bands

These indicators can be requested by [`Strategy`](@ref) systems for example:
```julia
struct TestStrat <: System

Overseer.requested_components(::TestStrat) = (SMA{20, Close}, RSI{14, Open})
```
This leads that for any asset that `TestStrat` should be used on will automatically generate these derived `Indicators` as the data flows in.
It is also used by [`new_entities`](@ref) to iterate over the new entities in a [`AssetLedger`](@ref) that hold the requested components for a given [`Strategy`](@ref).
[`reset!`](@ref) on the other hand clears all the data for the requested components of a strategy in a [`AssetLedger`](@ref).
This is useful for example to not use the data of the previous day when calculating moving averages etc.

```julia
function update(s::TestStrat, trader, asset_ledgers)
    curt = current_time(trader)
    if is_market_open(curt)
        for l in asset_ledgers
            # This clears the SMA{20, Close} and RSI{14, Open} Components from l
            reset!(l, s)
        end
    end
    for l in asset_ledgers
        for e in new_entities(l, s)
            # do something with e

            # e[SMA{20, Close}] accesses the SMA
            # e[RSI{14, Open}] accesses the RSI
        end
    end
end
```
Each `e` in the above example will be seen **only once**. See the [Strategies](@ref) tutorial for more info.

## Reference
```@docs
Trading.SMA
Trading.MovingStdDev
Trading.EMA
Trading.RSI
Trading.Bollinger
Trading.Sharpe
Trading.new_entities
Trading.reset!(::Trading.AssetLedger, ::Any)
```
## [Systems](@id indicator_systems)
```@docs
Trading.SMACalculator
Trading.MovingStdDevCalculator
Trading.EMACalculator
Trading.RSICalculator
Trading.BollingerCalculator
Trading.SharpeCalculator
```

