struct Purchaser <: System end

Overseer.requested_components(::Purchaser) = (Purchase, Order, PurchasePower)

function Overseer.update(::Purchaser, l::AbstractLedger)
    cash = singleton(l, PurchasePower)
    for e in @entities_in(l, Purchase && !Order)

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

        cash.cash -= tot_cost
        l[e] = submit_order(l, e; quantity=quantity)
    end
end

struct Filler <: System end

Overseer.requested_components(::Filler) = (Filled,Cash, Position)

function Overseer.update(::Filler, l::AbstractLedger)
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
            
            id = findfirst(x->x.ticker == ticker, l[Position])
            if id === nothing
                Entity(l, Position(ticker, quantity_filled))
            else
                l[Position][id].quantity += quantity_filled
            end
        end
    end
end

struct Seller <: System end

Overseer.requested_components(::Seller) = (Sale,)

function Overseer.update(::Seller, l::AbstractLedger)
    for e in @safe_entities_in(l, Sale && !Order)
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
            quantity = position.quantity
        else
            quantity = e.quantity
        end

        l[e] = submit_order(l, e; quantity=quantity)
    end
end
        
