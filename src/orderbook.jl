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
mutable struct OrderBookEntry{L}
    quantity::Int
    client::ClientID
    prev::OrderBookEntry{L}
    next::OrderBookEntry{L}
    limit::L

    function OrderBookEntry{L}() where {L}
        out = new{L}()
        out.prev = out
        out.next = out
        return out
    end
end

"""
Represents a price level in an [`OrderBook`](@ref) the `head` represents the first submitted order and the
tail the last one. These are stored in a [`LimitTree`](@ref).
"""
mutable struct Limit
    price::Float64
    head::OrderBookEntry{Limit}
    tail::OrderBookEntry{Limit}
end

const EMPTY_ORDERBOOK_ENTRY = OrderBookEntry{Limit}()

function OrderBookEntry(quantity::Int, client::ClientID, limit::Limit,
                        prev::OrderBookEntry{Limit} = EMPTY_ORDERBOOK_ENTRY,
                        next::OrderBookEntry{Limit} = EMPTY_ORDERBOOK_ENTRY)
                        
    out = OrderBookEntry{Limit}()
    out.quantity = quantity
    out.client   = client
    out.limit    = limit
    out.prev     = prev
    
    if prev !== EMPTY_ORDERBOOK_ENTRY
        out.prev.next = out
    end
        
    out.next = next
    if next !== EMPTY_ORDERBOOK_ENTRY
        out.next.prev = out
    end
        
    return out
end

function Base.delete!(o::OrderBookEntry)
    o.next.prev = o.prev
    o.prev.next = o.next
    return o
end

Limit(price::Float64) = Limit(price, EMPTY_ORDERBOOK_ENTRY, EMPTY_ORDERBOOK_ENTRY)

Base.convert(::Type{Limit}, price::Float64) = Limit(price)
Base.isempty(l::Limit) = l.head === EMPTY_ORDERBOOK_ENTRY

function Base.length(l::Limit)
    head = l.head
    count = 0
    while head !== EMPTY_ORDERBOOK_ENTRY
        count += 1
        head = head.next
    end
    return count
end

function Base.haskey(l::Limit, o::OrderBookEntry)
    return o.limit == l
end

function Base.delete!(l::Limit, o::OrderBookEntry)
    @assert haskey(l, o) ArgumentError("Limit doesn't contain OrderBookEntry")

    if l.head === o
        l.head = o.next
    end
    if l.tail === o
        l.tail = o.prev
    end
end

function Base.pop!(l::Limit)
    out = l.tail
    l.tail = out.prev
    return out
end

function Base.push!(l::Limit, o::OrderBookEntry)
    if isempty(l)
        return l.tail = l.head = o
    end
    o.prev = l.tail
    l.tail.next = o
    return l.tail = o
end

Base.:(<)(l1::Limit, l2::Limit) = l1.price < l2.price
Base.:(==)(l1::Limit, l2::Limit) = l1.price == l2.price

Base.:(<)(l1::Float64, l2::Limit) = l1 < l2.price
Base.:(==)(l1::Float64, l2::Limit) = l1 == l2.price

Base.:(<)(l1::Limit, l2::Float64) = l1.price < l2
Base.:(==)(l1::Limit, l2::Float64) = l1.price == l2

mutable struct LimitNode
    color::Bool
    data::Union{Limit,Nothing}
    left_child::Union{Nothing,LimitNode}
    right_child::Union{Nothing,LimitNode}
    parent::Union{Nothing,LimitNode}

    LimitNode() = new(true, nothing, nothing, nothing, nothing)

    LimitNode(d) = new(true, d, nothing, nothing, nothing)
end

function create_null_node()
    node = LimitNode()
    node.color = false
    return node
end

mutable struct LimitTree
    root::LimitNode
    nil::LimitNode
    count::Int

    function LimitTree()
        rb = new()
        rb.nil = create_null_node()
        rb.root = rb.nil
        rb.count = 0
        return rb
    end
end

Base.length(tree::LimitTree) = tree.count

"""
    search_node(tree, key)

Returns the last visited node, while traversing through in binary-search-tree fashion looking for `key`.
"""
function search_node(tree::LimitTree, d)
    node = tree.root
    while node !== tree.nil && d != node.data
        if d < node.data
            node = node.left_child
        else
            node = node.right_child
        end
    end
    return node
end

"""
    haskey(tree, key)

Returns true if `key` is present in the `tree`, else returns false.
"""
function Base.haskey(tree, d)
    node = search_node(tree, d)
    return node.data == d
end

"""
    insert_node!(tree::LimitTree, node::LimitTreeNode)

Inserts `node` at proper location by traversing through the `tree` in a binary-search-tree fashion.
"""
function insert_node!(tree::LimitTree, node::LimitNode)
    y = nothing
    x = tree.root

    while x !== tree.nil
        y = x
        if node.data < x.data
            x = x.left_child
        else
            x = x.right_child
        end
    end

    node.parent = y
    if y === nothing
        tree.root = node
    elseif node.data < y.data
        y.left_child = node
    else
        y.right_child = node
    end
end

"""
    left_rotate!(tree::LimitTree, node_x::LimitTreeNode)

Performs a left-rotation on `node_x` and updates `tree.root`, if required.
"""
function left_rotate!(tree::LimitTree, x::LimitNode)
    y = x.right_child
    x.right_child = y.left_child
    if y.left_child !== tree.nil
        y.left_child.parent = x
    end
    y.parent = x.parent
    if x.parent === nothing
        tree.root = y
    elseif x == x.parent.left_child
        x.parent.left_child = y
    else
        x.parent.right_child = y
    end
    y.left_child = x
    return x.parent = y
end

"""
    right_rotate!(tree::LimitTree, node_x::LimitTreeNode)

Performs a right-rotation on `node_x` and updates `tree.root`, if required.
"""
function right_rotate!(tree::LimitTree, x::LimitNode)
    y = x.left_child
    x.left_child = y.right_child
    if y.right_child !== tree.nil
        y.right_child.parent = x
    end
    y.parent = x.parent
    if x.parent === nothing
        tree.root = y
    elseif x == x.parent.left_child
        x.parent.left_child = y
    else
        x.parent.right_child = y
    end
    y.right_child = x
    return x.parent = y
end

"""
   fix_insert!(tree::LimitTree, node::LimitTreeNode)

This method is called to fix the property of having no two adjacent nodes of red color in the `tree`.
"""
function fix_insert!(tree::LimitTree, node::LimitNode)
    parent = nothing
    grand_parent = nothing
    # for root node, we need to change the color to black
    # other nodes, we need to maintain the property such that
    # no two adjacent nodes are red in color
    while node != tree.root && node.parent.color
        parent = node.parent
        grand_parent = parent.parent

        if (parent == grand_parent.left_child) # parent is the leftChild of grand_parent
            uncle = grand_parent.right_child

            if uncle.color # uncle is red in color
                grand_parent.color = true
                parent.color = false
                uncle.color = false
                node = grand_parent
            else  # uncle is black in color
                if node == parent.right_child # node is right_child of its parent
                    node = parent
                    left_rotate!(tree, node)
                end
                # node is left_child of its parent
                node.parent.color = false
                node.parent.parent.color = true
                right_rotate!(tree, node.parent.parent)
            end
        else # parent is the right_child of grand_parent
            uncle = grand_parent.left_child

            if uncle.color # uncle is red in color
                grand_parent.color = true
                parent.color = false
                uncle.color = false
                node = grand_parent
            else  # uncle is black in color
                if node == parent.left_child # node is leftChild of its parent
                    node = parent
                    right_rotate!(tree, node)
                end
                # node is right_child of its parent
                node.parent.color = false
                node.parent.parent.color = true
                left_rotate!(tree, node.parent.parent)
            end
        end
    end
    return tree.root.color = false
end

"""
    insert!(tree, key)

Inserts `key` in the `tree` if it is not present.
"""
function Base.insert!(tree::LimitTree, d, check_key = true)
    # if the key exists in the tree, no need to insert
    check_key && haskey(tree, d) && return tree

    # insert, if not present in the tree
    node = LimitNode(d)
    node.left_child = node.right_child = tree.nil

    insert_node!(tree, node)

    if node.parent === nothing
        node.color = false
    elseif node.parent.parent === nothing

    else
        fix_insert!(tree, node)
    end
    tree.count += 1
    return tree
end

"""
    push!(tree, key)

Inserts `key` in the `tree` if it is not present.
"""
function Base.push!(tree::LimitTree, key, args...)
    return insert!(tree, key, args...)
end

"""
    delete_fix(tree::LimitTree, node::Union{LimitTreeNode, Nothing})

This method is called when a black node is deleted because it violates the black depth property of the LimitTree.
"""
function delete_fix(tree::LimitTree, node::Union{LimitNode,Nothing})
    while node != tree.root && !node.color
        if node == node.parent.left_child
            sibling = node.parent.right_child
            if sibling.color
                sibling.color = false
                node.parent.color = true
                left_rotate!(tree, node.parent)
                sibling = node.parent.right_child
            end

            if !sibling.right_child.color && !sibling.left_child.color
                sibling.color = true
                node = node.parent
            else
                if !sibling.right_child.color
                    sibling.left_child.color = false
                    sibling.color = true
                    right_rotate!(tree, sibling)
                    sibling = node.parent.right_child
                end

                sibling.color = node.parent.color
                node.parent.color = false
                sibling.right_child.color = false
                left_rotate!(tree, node.parent)
                node = tree.root
            end
        else
            sibling = node.parent.left_child
            if sibling.color
                sibling.color = false
                node.parent.color = true
                right_rotate!(tree, node.parent)
                sibling = node.parent.left_child
            end

            if !sibling.right_child.color && !sibling.left_child.color
                sibling.color = true
                node = node.parent
            else
                if !sibling.left_child.color
                    sibling.right_child.color = false
                    sibling.color = true
                    left_rotate!(tree, sibling)
                    sibling = node.parent.left_child
                end

                sibling.color = node.parent.color
                node.parent.color = false
                sibling.left_child.color = false
                right_rotate!(tree, node.parent)
                node = tree.root
            end
        end
    end
    node.color = false
    return nothing
end

"""
    swap(tree::LimitTree, u::Union{LimitTreeNode, Nothing}, v::Union{LimitTreeNode, Nothing})

Replaces `u` by `v` in the `tree` and updates the `tree` accordingly.
"""
function swap(tree::LimitTree, u::Union{LimitNode,Nothing}, v::Union{LimitNode,Nothing})
    if u.parent === nothing
        tree.root = v
    elseif u == u.parent.left_child
        u.parent.left_child = v
    else
        u.parent.right_child = v
    end
    return v.parent = u.parent
end

"""
   minimum_node(tree::LimitTree, node::LimitTreeNode)

Returns the LimitTreeNode with minimum value in subtree of `node`.
"""
function minimum_node(tree::LimitTree, node::LimitNode = tree.root)
    node === tree.nil && return node
    while node.left_child !== tree.nil
        node = node.left_child
    end
    return node
end

"""
   maximum_node(tree::LimitTree, node::LimitTreeNode)

Returns the LimitTreeNode with maximum value in subtree of `node`.
"""
function maximum_node(tree::LimitTree, node::LimitNode = tree.root)
    node === tree.nil && return node
    while node.right_child !== tree.nil
        node = node.right_child
    end
    return node
end

"""
    delete!(tree::LimitTree, key)

Deletes `key` from `tree`, if present, else returns the unmodified tree.
"""
function Base.delete!(tree::LimitTree, d)
    z = tree.nil
    node = tree.root

    while node !== tree.nil
        if node.data == d
            z = node
        end

        if d < node.data
            node = node.left_child
        else
            node = node.right_child
        end
    end

    z === tree.nil && return tree

    y = z
    y_original_color = y.color
    if z.left_child === tree.nil
        x = z.right_child
        swap(tree, z, z.right_child)
    elseif z.right_child === tree.nil
        x = z.left_child
        swap(tree, z, z.left_child)
    else
        y = minimum_node(tree, z.right_child)
        y_original_color = y.color
        x = y.right_child

        if y.parent == z
            x.parent = y
        else
            swap(tree, y, y.right_child)
            y.right_child = z.right_child
            y.right_child.parent = y
        end

        swap(tree, z, y)
        y.left_child = z.left_child
        y.left_child.parent = y
        y.color = z.color
    end

    !y_original_color && delete_fix(tree, x)
    tree.count -= 1
    return tree
end

Base.in(key, tree::LimitTree) = haskey(tree, key)

"""
    getindex(tree, ind)

Gets the key present at index `ind` of the tree. Indexing is done in increasing order of key.
"""
function Base.getindex(tree::LimitTree, ind)
    @boundscheck (1 <= ind <= tree.count) ||
                 throw(ArgumentError("$ind should be in between 1 and $(tree.count)"))
    function traverse_tree_inorder(node::LimitNode)
        if node !== tree.nil
            left = traverse_tree_inorder(node.left_child)
            right = traverse_tree_inorder(node.right_child)
            append!(push!(left, node.data), right)
        else
            return Limit[]
        end
    end
    arr = traverse_tree_inorder(tree.root)
    return @inbounds arr[ind]
end

"""
Represents the orderbook of an asset with two red-black trees of [`Limit`](@ref) nodes representing the
bids and the asks.
"""
mutable struct OrderBook
    asset::String
    bids::LimitTree
    asks::LimitTree
    order_count::Int
    order_id_to_entry::Dict{OrderID,OrderBookEntry{Limit}}

    function OrderBook(asset::String)
        return new(asset, LimitTree(), LimitTree(), 0,
                   Dict{OrderID,OrderBookEntry{Limit}}())
    end
end

function register!(ob::OrderBook, tree::LimitTree, client::ClientID, price::Float64,
                   quantity::Int)
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
