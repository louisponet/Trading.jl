const ClientID = Int
const OrderID = Int

"""
Represents an order in the [`OrderBook`](@ref). These are nodes in a doubly linked list that is held at a given price level
which itself is represented by `limit` (a [`Limit`](@ref)).

# Examples
```julia
l1 = Limit(0.1)
o1 = OrderBookEntry(100, 1, l1)
o2 = OrderBookEntry(100, 2, l1, o1)
# o2 will now have o1 as prev, and o1 will have o2 as next

# o1 and o2 will have EMPTY_ORDERBOOK_ENTRY as their next and prev fields

o3 = OrderBookEntry(100, 3, l1, o1, o2)
# o3 has o1 as prev, o2 as next, and o1 has o3 as next, o2 has o3 as prev now
"""
struct OrderBookEntry{L}
    quantity::Float64
    client::ClientID
    limit::L
end

"""
Represents the orderbook of an [`Asset`](@ref) with two red-black trees of [`Limit`](@ref) nodes representing the
bids and the asks.
It is kept in the [`AssetLedger`](@ref) of the [`Asset`](@ref)
"""
mutable struct OrderBook{T <: OrderBookEntry}
    bids::Tree{LinkedList{T}}
    asks::Tree{LinkedList{T}}
    order_count::Int
    order_id_to_entry::Dict{OrderID,T}

    function OrderBook()
        return new(Tree{Limit}(), Tree{Limit}(), 0,
                   Dict{OrderID,OrderBookEntry{Limit}}())
    end
end

function register!(ob::OrderBook, tree::Tree, price::Number,
                   quantity::Number, client::ClientID = 0)
    limit = search_node(tree, price).data

    if limit === nothing || limit.price != price
        limit = Limit(price)
        insert!(tree, limit, false)
    end

    order_id = ob.order_count

    o = OrderBookEntry(quantity, client, limit)
    push!(limit, o)
    ob.order_id_to_entry[order_id] = o

    ob.order_count += 1
    return order_id
end

register_ask!(ob::OrderBook, args...) = register!(ob, ob.asks, args...)
register_bid!(ob::OrderBook, args...) = register!(ob, ob.bids, args...)

function spread(ob::OrderBook)
    return isempty(ob.asks) || isempty(ob.bids) ? nothing :
           minimum_node(ob.asks).data.price - maximum_node(ob.bids).data.price
end

Base.in(oid::OrderID, ob::OrderBook) = haskey(ob.order_id_to_entry, oid)

Base.getindex(ob::OrderBook, oid::OrderID) = ob.order_id_to_entry[oid]

function Base.delete!(ob::OrderBook, order_id)
    if order_id in ob
        o = ob[order_id]
        limit = o.limit

        # Potentially set head and tail
        delete!(limit, o)

        # remove o from the linked list
        delete!(o)

        pop!(ob.order_id_to_entry, order_id)

        if isempty(limit)
            if haskey(ob.asks, limit)
                delete!(ob.asks, limit)
            else
                delete!(ob.bids, limit)
            end
        end

        return o.client
    end
end

function Base.empty!(ob::OrderBook)
    empty!(ob.asks)
    empty!(ob.bids)
    empty!(ob.order_id_to_entry)
    return ob
end


#TODO This is a non-mutable store so we should be using different Limits (since they can just be vectors rather than linked lists)
"""
Similar to [`OrderBook`](@ref) but stores all the trades.
"""
mutable struct TradeBook
    tree::Tree
    trades::Vector{OrderBookEntry{Limit}}
end

function Base.push!(tb::TradeBook, quantity::Float64, price::Float64, client_id::ClientID=0)
    limit = search_node(tb.tree, price).data

    if limit === nothing || limit.price != price
        limit = Limit(price)
        insert!(tb.tree, limit, false)
    end

    o = OrderBookEntry(quantity, client_id, limit)
    push!(limit, o)

    push!(trades, o)
    return length(trades)
end
