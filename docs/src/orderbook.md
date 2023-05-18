# OrderBook
```meta
CurrentModule = Trading
```
An [OrderBook](@ref) is a representation of the currently known [`Ask`](@ref) and [`Bid`](@ref) levels. Essentially, these are the quantities of a given [`Asset`](@ref) that people want to sell ([`Ask`](@ref)) or buy ([`Bid`](@ref)) at certain prices.

In `Trading.jl` they are implemented in the [`AssetLedger`](@ref) as 2 `TreeComponents`. These are standard `Components` that are also internally backed by a `Red-Black Tree` (facilitating easy _search_ type operations) of `LinkedLists` of individual [`Asks`](@ref Ask) and [`Bids`](@ref Bid).

By default, when starting a [`Trader`](@ref) it will listen to updates on new [`Bids`](@ref Bid) [`Asks`](@ref Ask), [`Trades`](@ref) and [`latest_quote`](@ref) updates.
The latter signifies the `L1` [OrderBook](@ref) updates. The former 3 are stored in a manner that facilitates `L3` [OrderBook](@ref) interactions (each ask/bid is stored individually in the linked lists). `sum(x -> x.quantity, limit)` can be used to extract `L2` type market data from the [OrderBook](@ref).

## Behavior
Currently, whenever a




## References

```@docs
Ask
Bid
Trade
latest_quote
```


