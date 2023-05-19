# OrderBook
```meta
CurrentModule = Trading
```
An [OrderBook](@ref) is a representation of the currently known [`Ask`](@ref) and [`Bid`](@ref) levels. Essentially, these are the quantities of a given [`Asset`](@ref) that people want to sell ([`Ask`](@ref)) or buy ([`Bid`](@ref)) at certain prices.

In `Trading.jl` they are implemented in the [`AssetLedger`](@ref) as 2 [`TreeComponents`](@ref TreeComponent). These are standard `Components` that are also internally backed by a `Red-Black Tree` (facilitating easy _search_ type operations, see [`ceil`](@ref Base.ceil(::TreeComponent, ::Any)), [`floor`](@ref Base.floor(::TreeComponent, ::Any)), [`maximum`](@ref Base.maximum(::TreeComponent)) and [`minimum`](@ref Base.minimum(::TreeComponent))) of `LinkedLists` of individual [`Asks`](@ref Ask) and [`Bids`](@ref Bid).

By default, when starting a [`Trader`](@ref) it will listen to updates on new [`Bids`](@ref Bid) [`Asks`](@ref Ask), [`Trades`](@ref) and [`latest_quote`](@ref) updates.
The latter signifies the `L1` [OrderBook](@ref) updates. The former 3 are stored in a manner that facilitates `L3` [OrderBook](@ref) interactions (each ask/bid is stored individually in the linked lists). `sum(x -> x.quantity, limit)` can be used to extract `L2` type market data from the [OrderBook](@ref).

## Behavior
While [`Ask`](@ref), [`Bid`](@ref), [`Trade`](@ref) and [`latest_quote`](@ref) data comes in, the [`Trades`](@ref Trade) are matched with the [`Ask`](@ref) and [`Bid`](@ref) levels and clear these.
The matching works as follows:
- we assume that we have incomplete [`Trade`](@ref) data, and no direct [`Bid`](@ref) or [`Ask`](@ref) canceling data
- a [`Trade`](@ref) is assumed to always happen on the best [`Bid`](@ref) or [`Ask`](@ref) price level
- if there exist [`Bid`](@ref) or [`Ask`](@ref) levels between the [`Trade`](@ref) and the [OrderBook](@ref) center, they will be cleared assuming they are stale
- if a level exists with the exact [`Trade`](@ref) price, it will be cleared until the cleared quantity matches the [`Trade`](@ref) quantity

This means that when a sell trade comes in at price `5.0` then all [`Bids`](@ref Bid) with a higher price than `5.0` will be assumed outdated and thus removed.

## Example
See [OrderBook Imbalance](@ref) for an example usecase in a simple [`Strategy`](@ref).

## References

```@docs
Ask
Bid
Trade
latest_quote
TreeComponent
Base.ceil(::TreeComponent, ::Any)
Base.floor(::TreeComponent, ::Any)
Base.maximum(::TreeComponent, ::Any)
Base.minimum(::TreeComponent, ::Any)
minimum_node
maximum_node
levels
LinkedList
EntityPtr
```
