# Portfolio
```@meta
CurrentModule=Trading
```
The functionality here can be pulled into the namespace by
```julia
using Trading.Portfolio
```

## State
The state of a portfolio is represented by a combination of components:
- [`Cash`](@ref): the real cash balance of the portfolio, updated as [`Orders`](@ref Order) get filled, see [`current_cash`](@ref)
- [`Position`](@ref): represents a held quantity of an asset. [`current_position`](@ref) can be used as an easy way to retrieve the position size.
- [`PurchasePower`](@ref): can be used to determine whether certain orders can be made, see [`current_purchasepower`](@ref).
  At the start of every cycle this gets equalized with the current [`Cash`](@ref), can be used as an estimation of "future" cash if
  certain orders would get executed.
- [`PortfolioSnapshot`](@ref): a periodical snapshot of the portfolio

## Changing/Orders
The state of the portfolio can be changed by using:
- [`Purchase`](@ref): communicates to the system that a purchase order should be made. Will be executed by the [`Seller`](@ref) system.
- [`Sale`](@ref): communicates that a sale order should be made. Will be executed by the [`Purchaser`](@ref) system.

Each order can have an [`OrderType`](@ref), which defaults to `OrderType.Market` and a [`TimeInForce`](@ref) which defaults to `TimeInForce.GTC` (good till canceled).
A price can be specified for orders that are not a `Market` order.

## Example

We first construct a [`Trader`](@ref) which we [`start`](@ref) without any strategies.
```julia
broker = AlpacaBroker("<key_id>", "<secret>")

trader = Trader(broker)

start(trader)
```
Now we can interact with it and do some basic trades. First we ask for a `Market` order on *AAPL*
```julia
e = Entity(trader, Purchase("AAPL", 1))
```
After a while `e` will have a [`Filled`](@ref) component, signalling that the order was executed succesfully, and by asking
```julia
current_position(trader, "AAPL")
```
will return `1.0`.

We can do the exact same to make a [`Sale`](@ref).

!!! note

    Shorting is allowed

A `LimitOrder` can be made as
```julia
Entity(trader, Purchase("AAPL", 1, type=OrderType.Limit, price = 156.0))
```

## References

```@docs
Trading.current_position
Trading.current_cash
Trading.current_purchasepower
Trading.Cash
Trading.PurchasePower
Trading.Position
Trading.Purchase
Trading.Sale
Trading.Order
Trading.Filled
Trading.PortfolioSnapshot
Trading.OrderType
Trading.TimeInForce
Trading.Purchaser
Trading.Seller
Trading.Filler
Trading.DayCloser
Trading.SnapShotter
```
