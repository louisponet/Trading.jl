# Orderbook Imbalance

This strategy revolves around the idea that if there is a lot more pressure (i.e. quantity to be traded) of limits on either end of the [OrderBook](@ref), the price will most likely move in the opposite direction.

## Strategy
As usual we import start by defining a `System` that represents the core of our strategy.

```julia
using Trading
using Trading.Portfolio
using Trading.Strategies

struct OrderImbalance <: System
    trigger_min_size::Float64
    trigger_imbalance_ratio::Float64
end
```
`trigger_min_size` defines how large the largest limit quantity has to be, e.g. `5.0` would mean that the largest of the highest bid or lowest ask levels needs to at least have a quantity to be traded of `5.0`.
`trigger_imbalance_ratio` defines the imbalance between the best bid and ask quantities.

!!! note
    In general one should be careful in associating too much "data" with a `System` since it violates to some degree the ECS paradigm. `settings` type data _may_ be considered an exemption

```julia
function Overseer.update(o::OrderImbalance, t::Trader, asset_ledgers)
    l = asset_ledgers[1]
    asset = l.asset
    s = spread(l)
    if s == 0
        # No quotes received yet
        return
    end

    q = latest_quote(l)

    # If a limit level exists with the best ask or bid we take
    # the total quantities from those, otherwise we simply take the
    # quantities in the latest quote
    ask_level = l[Ask][q.ask]
    if ask_level !== nothing
        ask_size = sum(x->x.quantity, ask_level)
        ask_price = ask_level.price
    else
        ask_size = q.ask.quantity
        ask_price = q.ask.price
    end

    bid_level = l[Bid][q.bid]
    if bid_level !== nothing
        bid_size = sum(x->x.quantity, bid_level)
        bid_price = bid_level.price
    else
        bid_size = q.bid.quantity
        bid_price = q.bid.price
    end


    smaller = min(ask_size, bid_size)
    larger  = max(ask_size, bid_size)

    ratio = smaller / larger

    if larger > o.trigger_min_size && ratio < o.trigger_imbalance_ratio
        orders = pending_orders(t, asset)
        if !isempty(orders.purchases) || !isempty(orders.sales)
            return
        end
        if bid_size > ask_size
            @info "Making purchase of $(ask_size) @ $(ask_price)"
            Entity(t, Purchase(asset,
                               ask_size,
                               OrderType.Limit,
                               TimeInForce.IOC,
                               ask_price,
                               0.0))
        else
            @info "Making sale of $(bid_size) @ $(bid_price)"
            Entity(t, Sale(asset,
                           bid_size,
                           OrderType.Limit,
                           TimeInForce.IOC,
                           bid_price,
                           0.0))
        end
    end
end
```

## Possible Improvements

This strategy by itself is very unsuccessful and thus shouldn't be used in isolation.
The clearest improvement lies in determining a valid exit strategy, which it lacks completely.
Secondly, instead of using only the first level of price information, considering the further levels in the [OrderBook](@ref) could prove useful (see [`ceil`](@ref ceil(::TreeComponent)) and [`floor`](@ref floor(::TreeComponent))).

