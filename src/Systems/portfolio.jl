"""
    Purchaser

Handles [`Purchases`](@ref Purchase). Mainly verifies prices and quantities to be purchased.
"""
struct Purchaser <: System end

Overseer.requested_components(::Purchaser) = (Purchase, Order, PurchasePower)

function Overseer.update(::Purchaser, l::AbstractLedger)
    cash = singleton(l, PurchasePower)
    purchase_comp = l[Purchase]
    order_comp = l[Order]
    
    for ie in length(purchase_comp):-1:1
        e = @inbounds entity(purchase_comp, ie)

        if e in order_comp
            return
        end

        if e.type == OrderType.Market
            cur_price = current_price(l, e.ticker)
            cur_price == nothing && continue
        elseif e.type == OrderType.Limit
            cur_price = e.limit_price
        end

        if e.quantity === Inf
            tot_cost = cash.cash
            quantity = round(cash.cash/cur_price)
        else
            tot_cost = cur_price * e.quantity
            if cash.cash - tot_cost < 0
                continue
            end
            quantity = e.quantity
        end

        e.quantity = round(quantity)
        
        cash.cash -= tot_cost
    
        submit_order(l, e)
    end
end


"""
    Seller

Handles [`Sales`](@ref Sale).
"""
struct Seller <: System end

Overseer.requested_components(::Seller) = (Sale, Position, Order)

function Overseer.update(::Seller, l::AbstractLedger)
    sale_comp = l[Sale]
    order_comp = l[Order]
    
    for ie in length(sale_comp):-1:1
        e = @inbounds entity(sale_comp, ie)

        if e in order_comp
            return
        end
        
        if e.quantity === Inf
            posid = findfirst(x -> x.ticker == e.ticker, l[Position])
            
            if posid === nothing
                pop!(l[Sale], e)
                continue
            end

            position = l[Position][posid]
            
            if position.quantity == 0.0
                pop!(l[Sale], e)
                continue
            end
        
            if position.quantity < e.quantity
                e.quantity = position.quantity
            end
        end
        e.quantity = round(e.quantity)
        submit_order(l, e)
    end
end

"""
    Filler

When the status of an [`Order`](@ref) changes to `"filled"`, the filled quantity and average fill price is 
registered in a [`Filled`](@ref) `Component`.
"""
struct Filler <: System end

Overseer.requested_components(::Filler) = (Filled,Cash, Position)

function Overseer.update(::Filler, l::AbstractLedger)
    
    if length(l[Order]) == length(l[Filled])
        return
    end
    
    cash = singleton(l, Cash)
    
    for e in @entities_in(l, Order && !Filled)
        
        if e.status == "filled"
            l[e] = Filled(e.filled_avg_price, e.filled_qty)

            if e in l[Purchase]
                ticker = l[Purchase][e].ticker
                quantity_filled = e.filled_qty
            else
                ticker = l[Sale][e].ticker
                quantity_filled = -e.filled_qty
            end
            
            cash.cash -= e.filled_avg_price * quantity_filled
            cash.cash -= e.fee
            
            id = findfirst(x->x.ticker == ticker, l[Position])
            
            if id === nothing
                Entity(l, Position(ticker, quantity_filled))
            else
                l[Position][id].quantity += quantity_filled
            end
            
        end
    end
end

"""
    DayCloser([interval::Period = Minute(1)])

Closes the day. Will run during the time interval `[market_close - interval, market_close]`.
Currently it just removes pending trades.
"""
Base.@kwdef struct DayCloser <: System
    interval::Period=Minute(1)
end

Overseer.requested_components(::DayCloser) = (Sale, Position,Strategy)

function Overseer.update(::DayCloser, l::AbstractLedger)
    cur_t   = current_time(l)
    close_t = market_open_close(cur_t)[2]

    if abs(close_t - cur_t) > Minute(1)
        return
    end

    if length(l[Purchase]) + length(l[Sale]) == length(l[Filled])
        return
    end
    for e in @safe_entities_in(l, (Purchase || Sale) && !Filled)
        delete!(l, e)
    end
    # TODO cancel orders
    
    # for e in @entities_in(l, Position)
    #     if e.quantity > 0
    #         Entity(l, Sale(e.ticker, Inf, OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
    #     elseif e.quantity < 0 
    #         Entity(l, Purchase(e.ticker, -e.quantity, OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
    #     end
    # end
    # update(Purchaser(), l)
    # update(Seller(), l)
    # for ledger in values(l.ticker_ledgers)
    #     empty_entities!(ledger)
    # end
end

"""
    SnapShotter([interval::Period = Minute(1)])

Takes a [`PortfolioSnapshot`](@ref) after each `interval`, storing [`Positions`](@ref Position), [`Cash`](@ref), and total value.
"""
Base.@kwdef struct SnapShotter <: System
    interval::Period = Minute(1)
end

Overseer.requested_components(::SnapShotter) = (PortfolioSnapshot, TimeStamp)

function Overseer.update(s::SnapShotter, l::AbstractLedger)
    curt = current_time(l)

    if length(l[PortfolioSnapshot]) > 0
        last_snapshot_e = last_entity(l[PortfolioSnapshot])

        prev_t = l[TimeStamp][last_snapshot_e].t
        
        curt - prev_t < s.interval && return
    end
        
    cash  = singleton(l, Cash)[Cash]
    totval = cash.cash
    positions = Position[]
    
    for e in @entities_in(l, Position)
        push!(positions, deepcopy(e[Position]))
        price = current_price(l, e.ticker)
        if price === nothing
            return
        end
        totval += price * e.quantity
    end
    
    new_e = Entity(l, TimeStamp(current_time(l)), PortfolioSnapshot(positions, cash.cash, totval))
end

