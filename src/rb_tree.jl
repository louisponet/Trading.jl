#TODO the nothings here make stuff type unstable
mutable struct TreeNode{T}
    _color::Bool
    _data::Union{T,Nothing}
    _left_child::Union{Nothing,TreeNode{T}}
    _right_child::Union{Nothing,TreeNode{T}}
    _parent::Union{Nothing,TreeNode{T}}

    TreeNode{T}() where {T} = new{T}(true, nothing, nothing, nothing, nothing)

    TreeNode(d::T) where {T} = new{T}(true, d, nothing, nothing, nothing)
end

function create_null_node(::Type{T}) where {T}
    node = TreeNode{T}()
    node._color = false
    return node
end

function Base.getproperty(n::TreeNode, s::Symbol)
    if s in (:_color, :_data, :_left_child, :_right_child, :_parent)
        return getfield(n, s)
    else
        return getproperty(getfield(n, :_data), s)
    end
end
function Base.setproperty!(n::TreeNode, v, s::Symbol)
    if s in (:_color, :_data, :_left_child, :_right_child, :_parent)
        return setfield!(n, v, s)
    else
        return setproperty!(getfield(n, :_data), v, s)
    end
end

# TODO figure out if == or === is better
is_left_child(node::TreeNode) =
    node == node._parent._left_child
    
is_right_child(node::TreeNode) =
    node == node._parent._right_child

mutable struct Tree{T}
    root::TreeNode{T}
    nil::TreeNode{T}
    count::Int
    function Tree{T}() where {T}
        rb = new{T}()
        rb.nil = create_null_node(T)
        rb.root = rb.nil
        rb.count = 0
        return rb
    end
end

Base.length(tree::Tree) = tree.count

"""
    search_node(tree, key)

Returns the last visited node, while traversing through in binary-search-tree fashion looking for `key`.
"""
function search_node(tree::Tree, d)
    node = tree.root
    while node !== tree.nil
        
        if d == node._data
            return node
        end
        
        if d < node._data
            node = node._left_child
        else
            node = node._right_child
        end
        
    end
    return nothing
end

"""
    haskey(tree, key)

Returns true if `key` is present in the `tree`, else returns false.
"""
function Base.haskey(tree::Tree, d)
    return search_node(tree, d) !== nothing
end

"""
    insert_node!(tree::Tree, node::TreeNode)

Inserts `node` at proper location by traversing through the `tree` in a binary-search-tree fashion.
"""
function insert_node!(tree::Tree, node::TreeNode)
    y = nothing
    x = tree.root

    while x !== tree.nil
        y = x
        if node._data < x._data
            x = x._left_child
        else
            x = x._right_child
        end
    end

    node._parent = y
    if y === nothing
        tree.root = node
    elseif node._data < y._data
        y._left_child = node
    else
        y._right_child = node
    end
end

"""
    left_rotate!(tree::Tree, node_x::TreeNode)

Performs a left-rotation on `node_x` and updates `tree.root`, if required.
"""
function left_rotate!(tree::Tree, x::TreeNode)
    y = x._right_child
    x._right_child = y._left_child
    if y._left_child !== tree.nil
        y._left_child._parent = x
    end
    y._parent = x._parent
    if x._parent === nothing
        tree.root = y
    elseif x == x._parent._left_child
        x._parent._left_child = y
    else
        x._parent._right_child = y
    end
    y._left_child = x
    return x._parent = y
end

"""
    right_rotate!(tree::Tree, node_x::TreeNode)

Performs a right-rotation on `node_x` and updates `tree.root`, if required.
"""
function right_rotate!(tree::Tree, x::TreeNode)
    y = x._left_child
    x._left_child = y._right_child
    if y._right_child !== tree.nil
        y._right_child._parent = x
    end
    y._parent = x._parent
    if x._parent === nothing
        tree.root = y
    elseif x == x._parent._left_child
        x._parent._left_child = y
    else
        x._parent._right_child = y
    end
    y._right_child = x
    return x._parent = y
end

"""
   fix_insert!(tree::Tree, node::TreeNode)

This method is called to fix the property of having no two adjacent nodes of red color in the `tree`.
"""
function fix_insert!(tree::Tree, node::TreeNode)
    _parent = nothing
    grand_parent = nothing
    # for root node, we need to change the color to black
    # other nodes, we need to maintain the property such that
    # no two adjacent nodes are red in color
    while node != tree.root && node._parent._color
        _parent = node._parent
        grand_parent = _parent._parent

        if (_parent == grand_parent._left_child) # _parent is the leftChild of grand_parent
            uncle = grand_parent._right_child

            if uncle._color # uncle is red in color
                grand_parent._color = true
                _parent._color = false
                uncle._color = false
                node = grand_parent
            else  # uncle is black in color
                if node == _parent._right_child # node is _right_child of its _parent
                    node = _parent
                    left_rotate!(tree, node)
                end
                # node is _left_child of its _parent
                node._parent._color = false
                node._parent._parent._color = true
                right_rotate!(tree, node._parent._parent)
            end
        else # _parent is the _right_child of grand_parent
            uncle = grand_parent._left_child

            if uncle._color # uncle is red in color
                grand_parent._color = true
                _parent._color = false
                uncle._color = false
                node = grand_parent
            else  # uncle is black in color
                if node == _parent._left_child # node is leftChild of its _parent
                    node = _parent
                    right_rotate!(tree, node)
                end
                # node is _right_child of its _parent
                node._parent._color = false
                node._parent._parent._color = true
                left_rotate!(tree, node._parent._parent)
            end
        end
    end
    return tree.root._color = false
end

"""
    insert!(tree, key)

Inserts `key` in the `tree` if it is not present.
"""
function Base.insert!(tree::Tree, d, check_key = true)
    # if the key exists in the tree, no need to insert
    check_key && haskey(tree, d) && return tree

    # insert, if not present in the tree
    node = TreeNode(d)
    node._left_child = node._right_child = tree.nil

    insert_node!(tree, node)

    if node._parent === nothing
        node._color = false
    elseif node._parent._parent === nothing

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
function Base.push!(tree::Tree, key, args...)
    return insert!(tree, key, args...)
end

"""
    delete_fix(tree::Tree, node::Union{TreeNode, Nothing})

This method is called when a black node is deleted because it violates the black depth property of the Tree.
"""
function delete_fix(tree::Tree, node::Union{TreeNode,Nothing})
    while node != tree.root && !node._color
        if is_left_child(node)
            sibling = node._parent._right_child
            if sibling._color
                sibling._color = false
                node._parent._color = true
                left_rotate!(tree, node._parent)
                sibling = node._parent._right_child
            end

            if !sibling._right_child._color && !sibling._left_child._color
                sibling._color = true
                node = node._parent
            else
                if !sibling._right_child._color
                    sibling._left_child._color = false
                    sibling._color = true
                    right_rotate!(tree, sibling)
                    sibling = node._parent._right_child
                end

                sibling._color = node._parent._color
                node._parent._color = false
                sibling._right_child._color = false
                left_rotate!(tree, node._parent)
                node = tree.root
            end
        else
            sibling = node._parent._left_child
            if sibling._color
                sibling._color = false
                node._parent._color = true
                right_rotate!(tree, node._parent)
                sibling = node._parent._left_child
            end

            if !sibling._right_child._color && !sibling._left_child._color
                sibling._color = true
                node = node._parent
            else
                if !sibling._left_child._color
                    sibling._right_child._color = false
                    sibling._color = true
                    left_rotate!(tree, sibling)
                    sibling = node._parent._left_child
                end

                sibling._color = node._parent._color
                node._parent._color = false
                sibling._left_child._color = false
                right_rotate!(tree, node._parent)
                node = tree.root
            end
        end
    end
    node._color = false
    return nothing
end

"""
    swap(tree::Tree, u::Union{TreeNode, Nothing}, v::Union{TreeNode, Nothing})

Replaces `u` by `v` in the `tree` and updates the `tree` accordingly.
"""
function swap(tree::Tree, u::Union{TreeNode,Nothing}, v::Union{TreeNode,Nothing})
    if u._parent === nothing
        tree.root = v
    elseif u == u._parent._left_child
        u._parent._left_child = v
    else
        u._parent._right_child = v
    end
    return v._parent = u._parent
end

"""
   minimum_node(tree::Tree, node::TreeNode)

Returns the TreeNode with minimum value in subtree of `node`.
"""
function minimum_node(tree::Tree, node::TreeNode = tree.root)
    node === tree.nil && return node
    while node._left_child !== tree.nil
        node = node._left_child
    end
    return node
end

"""
   maximum_node(tree::Tree, node::TreeNode)

Returns the TreeNode with maximum value in subtree of `node`.
"""
function maximum_node(tree::Tree, node::TreeNode = tree.root)
    node === tree.nil && return node
    while node._right_child !== tree.nil
        node = node._right_child
    end
    return node
end

function Base.ceil(tree::Tree, d, node=tree.root)
    best_node = nothing
    while true
        if node === tree.nil
            return best_node
        elseif d == node._data
            return node
        elseif d < node._data
            best_node = node
            node = node._left_child
        else
            node = node._right_child
        end
    end
end

function Base.floor(tree::Tree, d, node=tree.root)
    best_node = nothing
    while true
        if node === tree.nil
            return best_node
        elseif d == node._data
            return node
        elseif d < node._data
            node = node._left_child
        else
            best_node = node
            node = node._right_child
        end
    end
end

"""
    delete!(tree::Tree, key)

Deletes `key` from `tree`, if present, else returns the unmodified tree.
"""
function Base.delete!(tree::Tree, d)
    z = tree.nil
    node = tree.root

    while node !== tree.nil
        if d == node._data
            z = node
        end

        if d < node._data
            node = node._left_child
        else
            node = node._right_child
        end
    end

    z === tree.nil && return tree

    y = z
    y_original_color = y._color
    if z._left_child === tree.nil
        x = z._right_child
        swap(tree, z, z._right_child)
    elseif z._right_child === tree.nil
        x = z._left_child
        swap(tree, z, z._left_child)
    else
        y = minimum_node(tree, z._right_child)
        y_original_color = y._color
        x = y._right_child

        if y._parent == z
            x._parent = y
        else
            swap(tree, y, y._right_child)
            y._right_child = z._right_child
            y._right_child._parent = y
        end

        swap(tree, z, y)
        y._left_child = z._left_child
        y._left_child._parent = y
        y._color = z._color
    end

    !y_original_color && delete_fix(tree, x)
    tree.count -= 1
    return tree
end

Base.in(key, tree::Tree) = haskey(tree, key)

function Base.empty!(tree::Tree)
    tree.root=tree.nil
    tree.count = 0
end

Base.isempty(tree::Tree) = tree.root === tree.nil

function Base.show(io::IO, m::MIME"text/plain", node::TreeNode, space = 0)
    if node._data !== nothing
        space = space + 10;
        show(io, m, node._right_child, space)
        println(io)
        for  i = 11:space
            print(io, " ")
        end
        println(io, "$(node._data) $(node._color ? "R" : "B")")
        show(io, m, node._left_child, space)
    end
end
    
function Base.show(io::IO, m::MIME"text/plain", tree::Tree)
    show(io, m, tree.root)
end

# Does Not work yet
function Base.iterate(it::Tree, state = minimum_node(it))
    state === nothing && return nothing
    if state._right_child !== it.nil
        next = minimum_node(it, state._right_child)
    elseif state === it.root
        # No valid right child and root -> done
        return state, nothing
    elseif is_left_child(state)
        next = state._parent
    else
        next = state._parent
        while is_right_child(next)
            if next._parent === it.root
                return state, nothing
            end
            next = next._parent
        end
        # Here we know that it's a left child and so necessarily has been
        # done already so we call the parent
        next = next._parent
    end
    return state, next
end

"""
    getindex(tree, ind)

Gets the key present at index `ind` of the tree. Indexing is done in increasing order of key.
"""
function Base.getindex(tree::Tree{T}, ind) where {T}
    @boundscheck (1 <= ind <= tree.count) ||
                 throw(ArgumentError("$ind should be in between 1 and $(tree.count)"))
    function traverse_tree_inorder(node::TreeNode)
        if node !== tree.nil
            left = traverse_tree_inorder(node._left_child)
            right = traverse_tree_inorder(node._right_child)
            append!(push!(left, node._data), right)
        else
            return T[]
        end
    end
    arr = traverse_tree_inorder(tree.root)
    return @inbounds arr[ind]
end
