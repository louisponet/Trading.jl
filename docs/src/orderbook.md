# OrderBook
```meta
CurrentModule = Trading
```
An [OrderBook](@ref) is a representation of  the currently known [`Ask`](@ref) and [`Bid`](@ref) levels. Essentially, these are the quantities of a given [`Asset`](@ref) that people want to sell ([`Ask`](@ref)) or buy ([`Bid`](@ref)) at certain prices.

In `Trading.jl` they are implemented in the [`AssetLedger`](@ref) as 2 `TreeComponents`. These are standard `Components` that are also internally backed by a `Red-Black Tree` (facilitating easy _search_ type operations).


