struct OrderBookMaintainer <: System end

Overseer.requested_components(::OrderBookMaintainer) = (Trade,)

function Overseer.update(s::OrderBookMaintainer, l::AssetLedger)
    bids = l[Bid]
    asks = l[Ask]
    trades = l[Trade]
    seen = l[Seen{OrderBookMaintainer}]
    for i in length(seen)+1:length(trades)
        e = entity(trades, i)


        min_ask = minimum_node(asks.tree).data.head.price
        max_bid =  maximum_node(bids.tree).data.head.price
        @info "min_ask = $min_ask, max_bid = $max_bid"
        
        if e.side == Side.Buy
            if e.price < min_ask 
                if e.price > max_bid
                    @info "Buy price: $(e.price) in center"
                else
                    @error "Buy price: $(e.price) somehow in the bids range..."
                end
            else
                @info "Buy price: $(e.price) in asks range and should lead to some clearing"
            end
            process_trades!(l, asks, Ask(e.price, e.quantity))
        elseif e.side == Side.Sell
            if e.price > maximum_node(bids.tree).data.head.price
                if e.price < minimum_node(asks.tree).data.head.price
                    @info "Sell price: $(e.price) in center"
                else
                    @error "Sell price: $(e.price) somehow in the asks range..."
                end
            else
                @info "Sell price: $(e.price) in bid range and should lead to some clearing"
            end
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
    
    limit === nothing && return clear_till_center!(l, comp, v)

    q = v.quantity
    n = length(limit)

    node = limit.head
    
    while n > 0 && q > 0
        @info "trade $(v) connected with $(node.e)"
        if node.quantity <= q
            q -= node.quantity
            pop!(comp, node.e, v = node.ptr[], list = limit, list_len = n)
            delete!(l, node.e)
            n -= 1
            node = node.next
        else
            curval = node.ptr[]
            node.ptr[] = eltype(comp)(curval.price, curval.quantity - q)
            q = 0
        end
    end
    
    if q > 0
        clear_till_center!(l, comp, v)
    end
        
end

function clear_till_center!(l, comp::TreeComponent{Bid}, v::Bid)
    limit = ceil(comp, v)
    while limit !== nothing
        tv = limit.head.ptr[]
        n = length(limit)
        
        node = limit.head
        while node !== limit.nil
            @info "removed $(node.e) with price $(node.price) while clearing Bid till center on trade price $(v.price)"
            pop!(comp, node.e, list = limit, list_len = n, v=tv)
            delete!(l, node.e)
            node = node.next
            n -= 1
        end
        
        limit = ceil(comp, v)
    end
end

function clear_till_center!(l, comp::TreeComponent{Ask}, v::Ask)
    limit = floor(comp, v)
    
    while limit !== nothing
        tv = limit.head.ptr[]
        n = length(limit)
        
        node = limit.head
        while node !== limit.nil
            @info "removed $(node.e) with price $(node.price) while clearing Ask till center on trade price $(v.price)"
            pop!(comp, node.e, list = limit, list_len = n, v=tv)
            delete!(l, node.e)
            node = node.next
            n -= 1
        end
        
        limit = floor(comp, v)
    end
end

function limit_quantity(l::LinkedList{Union{Trade, Bid, Ask}})
    q = 0
    for node in l
        q += node.price
    end
    return l
end






