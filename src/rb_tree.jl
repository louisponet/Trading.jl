mutable struct TreeNode{T}
    color::Bool
    data::Union{T,Nothing}
    left_child::Union{Nothing,TreeNode{T}}
    right_child::Union{Nothing,TreeNode{T}}
    parent::Union{Nothing,TreeNode{T}}

    TreeNode{T}() where {T} = new{T}(true, nothing, nothing, nothing, nothing)

    TreeNode(d::T) where {T} = new{T}(true, d, nothing, nothing, nothing)
end

function create_null_node(::Type{T}) where {T}
    node = TreeNode{T}()
    node.color = false
    return node
end

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
function Base.haskey(tree::Tree, d)
    node = search_node(tree, d)
    return node.data == d
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
    left_rotate!(tree::Tree, node_x::TreeNode)

Performs a left-rotation on `node_x` and updates `tree.root`, if required.
"""
function left_rotate!(tree::Tree, x::TreeNode)
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
    right_rotate!(tree::Tree, node_x::TreeNode)

Performs a right-rotation on `node_x` and updates `tree.root`, if required.
"""
function right_rotate!(tree::Tree, x::TreeNode)
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
   fix_insert!(tree::Tree, node::TreeNode)

This method is called to fix the property of having no two adjacent nodes of red color in the `tree`.
"""
function fix_insert!(tree::Tree, node::TreeNode)
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
function Base.insert!(tree::Tree, d, check_key = true)
    # if the key exists in the tree, no need to insert
    check_key && haskey(tree, d) && return tree

    # insert, if not present in the tree
    node = TreeNode(d)
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
function Base.push!(tree::Tree, key, args...)
    return insert!(tree, key, args...)
end

"""
    delete_fix(tree::Tree, node::Union{TreeNode, Nothing})

This method is called when a black node is deleted because it violates the black depth property of the Tree.
"""
function delete_fix(tree::Tree, node::Union{TreeNode,Nothing})
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
    swap(tree::Tree, u::Union{TreeNode, Nothing}, v::Union{TreeNode, Nothing})

Replaces `u` by `v` in the `tree` and updates the `tree` accordingly.
"""
function swap(tree::Tree, u::Union{TreeNode,Nothing}, v::Union{TreeNode,Nothing})
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
   minimum_node(tree::Tree, node::TreeNode)

Returns the TreeNode with minimum value in subtree of `node`.
"""
function minimum_node(tree::Tree, node::TreeNode = tree.root)
    node === tree.nil && return node
    while node.left_child !== tree.nil
        node = node.left_child
    end
    return node
end

"""
   maximum_node(tree::Tree, node::TreeNode)

Returns the TreeNode with maximum value in subtree of `node`.
"""
function maximum_node(tree::Tree, node::TreeNode = tree.root)
    node === tree.nil && return node
    while node.right_child !== tree.nil
        node = node.right_child
    end
    return node
end

function Base.ceil(tree::Tree, d)
    node = tree.root
    while node !== tree.nil
        if node.data < d
            node = node.right_child
        else
            if node.left_child === tree.nil
                return node
            end
            node = node.left_child
        end
    end
    return node
end

function Base.floor(tree::Tree, d)
    node = tree.root
    while node !== tree.nil
        if node.data > d
            node = node.left_child
        else
            if node.right_child === tree.nil
                return node
            end
            node = node.right_child
        end
    end
    return node
end

"""
    delete!(tree::Tree, key)

Deletes `key` from `tree`, if present, else returns the unmodified tree.
"""
function Base.delete!(tree::Tree, d)
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

Base.in(key, tree::Tree) = haskey(tree, key)

"""
    getindex(tree, ind)

Gets the key present at index `ind` of the tree. Indexing is done in increasing order of key.
"""
function Base.getindex(tree::Tree, ind)
    @boundscheck (1 <= ind <= tree.count) ||
                 throw(ArgumentError("$ind should be in between 1 and $(tree.count)"))
    function traverse_tree_inorder(node::TreeNode)
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

