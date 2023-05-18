struct OrderBookMaintainer <: System end

Overseer.requested_components(::OrderBookMaintainer) = (Trade,)

function Overseer.update(s::OrderBookMaintainer, l::AssetLedger)
    bids = l[Bid]
    asks = l[Ask]
    trades = l[Trade]
    seen = l[Seen{OrderBookMaintainer}]

    # First we handle clearing to center from last quote
    q = latest_quote(l)
    clear_to_center!(l, asks, Ask(q.ask.price-0.001, 0.0))
    clear_to_center!(l, bids, Bid(q.bid.price+0.001, 0.0))
    
    for i in length(seen)+1:length(trades)
        e = entity(trades, i)

        min_ask = minimum(asks).price
        max_bid =  maximum(bids).price
        
        if e.side == Side.Buy
            process_trades!(l, asks, Ask(e.price, e.quantity))
        elseif e.side == Side.Sell
            process_trades!(l, bids, Bid(e.price, e.quantity))
        else
            process_trades!(l, asks, Ask(e.price, e.quantity))
            process_trades!(l, bids, Bid(e.price, e.quantity))
        end
        seen[e] = Seen{OrderBookMaintainer}()
    end

end

# TODO I guess we should first walk the tree from center up or down while reducing the
# quantity
function process_trades!(l, comp, v)
    limit = comp[v]
    
    limit === nothing && return clear_to_center!(l, comp, v)

    q = v.quantity
    n = length(limit)

    node = limit._head
    
    while n > 0 && q > 0
        if node.quantity <= q
            q -= node.quantity
            pop!(comp, node.e, v = node.ptr[], list = limit, list_len = n)
            delete!(l, node.e)
            n -= 1
            node = node._next
        else
            curval = node.ptr[]
            node.ptr[] = eltype(comp)(curval.price, curval.quantity - q)
            q = 0
        end
    end
    
    if q > 0
        clear_to_center!(l, comp, v)
    end
        
end

function clear_to_center!(l, comp::TreeComponent{Bid}, v::Bid)
    limit = ceil(comp, v)
    while limit !== nothing
        tv = limit.ptr[]
        n = length(limit)
        
        node = limit._head
        while true
            pop!(comp, node.e, list = limit, list_len = n, v=tv)
            delete!(l, node.e)
            
            n -= 1
            if n == 0
                break
            end
            
            node = node._next
        end
        
        limit = ceil(comp, v)
    end
end

function clear_to_center!(l, comp::TreeComponent{Ask}, v::Ask)
    limit = floor(comp, v)
    
    while limit !== nothing
        tv = limit.ptr[]
        n = length(limit)
        
        node = limit._head
        while true
            pop!(comp, node.e; list = limit, list_len = n, v=tv)
            delete!(l, node.e)
            
            n -= 1
            if n == 0
                break
            end
            
            node = node._next
        end
        
        limit = floor(comp, v)
    end
end

