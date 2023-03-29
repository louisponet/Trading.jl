struct Purchaser <: System end

Overseer.requested_components(::Purchaser) = (Purchase, Order, PurchasePower)

function Overseer.update(::Purchaser, l::AbstractLedger)
    cash = singleton(l, PurchasePower)
    for e in @entities_in(l, Purchase && !Order)

        if e.type == OrderType.Market
            cur_price = Data.current_price(l, e.ticker)
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
    
        Data.submit_order(l, e)
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

Overseer.requested_components(::Seller) = (Sale, Position, Order)

function Overseer.update(::Seller, l::AbstractLedger)
    for e in @safe_entities_in(l, Sale && !Order)
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
        Data.submit_order(l, e)
    end
end

struct DayCloser <: System end

Overseer.requested_components(::DayCloser) = (Sale, Position,Strategy)

function Overseer.update(::DayCloser, l::AbstractLedger)
    cur_t   = current_time(l)
    close_t = market_open_close(cur_t)[2]

    if close_t - cur_t > Minute(1)
        return
    end

    for e in @entities_in(l, Position)
        if e.quantity > 0
            Entity(l, Sale(e.ticker, Inf, OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
        elseif e.quantity < 0 
            Entity(l, Purchase(e.ticker, -e.quantity, OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
        end
    end
    update(Purchaser(), l)
    update(Seller(), l)
    
    empty!(stages(l))
    stage = main_stage()
    push!(stage.steps, DayOpener())
    push!(l, stage)

    for e in @entities_in(l, Strategy)
        if !e.only_day
            push!(l, e.stage)
        end
    end
    
    ensure_systems!(l)
end

struct DayOpener <: System end

Overseer.requested_components(::DayOpener) = (Strategy,)

function Overseer.update(::DayOpener, l::AbstractLedger)
    cur_t   = current_time(l)
    open_t, close_t = market_open_close(cur_t)

    if cur_t > close_t || open_t > cur_t 
        return
    end

    empty!(stages(l))
    stage = main_stage()
    push!(stage.steps, DayCloser())
    push!(l, stage)

    for e in @entities_in(l, Strategy)
        push!(l, e.stage)
    end
    
    ensure_systems!(l)
end
