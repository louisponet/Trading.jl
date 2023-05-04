# Ticker Ledgers
```@meta
CurrentModule = Trading
```

```@docs
Trading.AssetLedger
Trading.Asset
```

## Bar Components
Bars are represented internally by the following set of `Components`, basically standard `ohlc` and `volume`:
- [`Open`](@ref)
- [`Close`](@ref)
- [`High`](@ref)
- [`Low`](@ref)
- [`Volume`](@ref)

Their differences (i.e. from one period to the next), and logarithms are represented by:
- [`Difference`](@ref)
- [`RelativeDifference`](@ref)
- [`LogVal`](@ref)

Each of these, and some derived quantities, can be requested by a [`Strategy`](@ref) as discussed in [Indicators](@ref) and demonstrated in more detail in
the [Strategies](@ref) tutorial.

## Reference
```@docs
Trading.Open
Trading.High
Trading.Low
Trading.Close
Trading.Volume
Trading.Difference
Trading.RelativeDifference
Trading.LogVal
Trading.value
```
