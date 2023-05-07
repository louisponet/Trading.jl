using Overseer: EntityState, AbstractEntity
using Base: RefArray

struct EntityPtr{RT <: Ref}
    e::Entity
    ptr::RT
end
EntityPtr(e::AbstractEntity, c::AbstractComponent) = EntityPtr(Entity(e), Ref(c, e)) 

Base.:(<)(en1::EntityPtr, en2::EntityPtr) = en1.ptr[] < en2.ptr[]
Base.:(==)(en1::EntityPtr, en2::EntityPtr) = en1.ptr[] == en2.ptr[]

Base.:(<)(en1::EntityPtr, v) = en1.ptr[] < v
Base.:(<)(v, en1::EntityPtr) = v < en1.ptr[]

Base.:(==)(en1::EntityPtr, v) = en1.ptr[] == v
Base.:(==)(v, en1::EntityPtr) = en1.ptr[] == v

mutable struct ListNode{T}
    data::T
    next::ListNode{T}
    prev::ListNode{T}

    function ListNode{T}() where {T}
        out = new{T}()
        out.next = out
        out.prev = out
        return out
    end
    
    function ListNode(data::T) where {T}
        out = new{T}()
        out.data = data
        out.next = out
        out.prev = out
        return out
    end
end

function Base.getproperty(node::ListNode, s::Symbol)
    if s in (:next, :prev, :data)
        return getfield(node, s)
    else
        return getproperty(node.data, s)
    end
end

function Base.setproperty!(node::ListNode, s::Symbol, v)
    if s in (:next, :prev, :data)
        return setfield!(node, s, v)
    else
        return setproperty!(node.data, s, v)
    end
end

function Base.delete!(node::ListNode)
    node.next.prev = node.prev
    node.prev.next = node.next
    return node
end

Base.:(<)(l1::ListNode, l2::ListNode) = l1.data < l2.data
Base.:(==)(l1::ListNode, l2::ListNode) = l1.data == l2.data

Base.:(<)(l1, l2::ListNode) = l1 < l2.data
Base.:(==)(l1, l2::ListNode) = l1 == l2.data

Base.:(<)(l1::ListNode, l2) = l1.data < l2
Base.:(==)(l1::ListNode, l2) = l1.data == l2

mutable struct LinkedList{T}
    head::ListNode{T}
    tail::ListNode{T}
    nil::ListNode{T}
    
    function LinkedList{T}() where {T}
        out = new{T}()
        out.nil = ListNode{T}()
        out.head = out.nil
        out.tail = out.nil
        return out
    end
end

function LinkedList(vals::T...) where {T}
    out = LinkedList{T}()
    for v in vals
        push!(out, v)
    end
    return out
end

Base.isempty(l::LinkedList) = l.head === l.nil

function Base.length(l::LinkedList)
    head = l.head
    count = 0
    while head !== l.nil
        count += 1
        head = head.next
    end
    return count
end

function Base.haskey(l::LinkedList, o)
    node = l.head
    while node !== l.tail && node.data != o
        if node.data == o
            return true
        end
        node = node.next
    end
    
    return false 
end

function Base.delete!(l::LinkedList, o::ListNode)
    if l.head === o
        l.head = o.next
    end
    if l.tail === o
        l.tail = o.prev
    end
end

function Base.delete!(l::LinkedList{T}, d::T) where {T}
    node = l.head
    while node != d
        
        if node === l.nil
            return
        end
            
        node = node.next
    end

    delete!(node)
    delete!(l, node)
    return node
end

function Base.pop!(l::LinkedList)
    out = l.tail
    l.tail = out.prev
    return out
end

function Base.popfirst!(l::LinkedList)
    out = l.head
    l.head = out.next
    return out
end

function Base.push!(l::LinkedList, d::ListNode)
    if isempty(l)
        l.tail = l.head = d
        d.prev = l.nil
        d.next = l.nil
        return 
    end
    d.prev = l.tail
    l.tail.next = d
    l.tail = d
    return l
end

Base.push!(l::LinkedList{T}, d::T) where {T} = push!(l, ListNode(d))

function Base.pushfirst!(l::LinkedList, d::ListNode)
    if isempty(l)
        l.tail = l.head = d
        d.prev = l.nil
        d.next = l.nil
        return 
    end
    d.next = l.head
    l.head.prev = d
    l.head = d
    return l
end
Base.pushfirst!(l::LinkedList{T}, d::T) where {T} = pushfirst!(l, ListNode(d))

function Base.iterate(l::LinkedList, state=l.head)
    state === l.nil && return nothing
    return state, state.next
end

Base.:(<)(l1::LinkedList, l2::LinkedList) = l1.head < l2.head
Base.:(==)(l1::LinkedList, l2::LinkedList) = l1.head == l2.head

Base.:(<)(l1, l2::LinkedList) = l1 < l2.head
Base.:(==)(l1, l2::LinkedList) = l1 == l2.head

Base.:(<)(l1::LinkedList, l2) = l1.head < l2
Base.:(==)(l1::LinkedList, l2) = l1.head == l2

const ComponentRef{T} = RefArray{T, Component{T}, Nothing}
const PooledComponentRef{T} = RefArray{T, PooledComponent{T}, Nothing}

"""
A Component backed by a red-black tree.

Indexing into a component with an [`Entity`](@ref) will return the data linked to that entity,
indexing with a regular `Int` will return directly the data that is stored in the data
vector at that index, i.e. generally not the storage linked to the [`Entity`](@ref) with that `Int` as id.

To register a `Type` to be stored in a [`TreeComponent`](@ref) see [`@tree_component`](@ref).
Every `Type` needs to define `<` and `==` operators.
"""
mutable struct TreeComponent{T} <: AbstractComponent{T}
    c::Component{T}
    tree::Tree{LinkedList{EntityPtr{ComponentRef{T}}}}
end
TreeComponent{T}() where {T} = TreeComponent{T}(Component{T}(), Tree{LinkedList{EntityPtr{ComponentRef{T}}}}())
Overseer.component(t::TreeComponent) = t.c

function Base.setindex!(t::TreeComponent, v, e::Overseer.AbstractEntity)
    if e in t
        @inbounds setindex!(t.c, v, e)
    else
        out = setindex!(t.c, v, e)
        push!(t.tree, LinkedList(EntityPtr(Entity(e), Ref(t.c, e))))
    end
    return t
end

function Base.getindex(t::TreeComponent{T}, v::T) where {T}
    node = search_node(t.tree, v)
    if node.data == v
        return EntityState(node.data.e, node.data.ptr[])
    end
    return nothing
end

function Base.ceil(t::TreeComponent, v)
    node = ceil(t.tree, v)
    
    node.data === nothing && return nothing
    
    return EntityState(node.data.e, node.data.ptr[])
end

function Base.floor(t::TreeComponent, v)
    node = floor(t.tree, v)
    
    node.data === nothing && return nothing
    
    return EntityState(node.data.e, node.data.ptr[])
end
macro tree_component(typedef)
    return esc(Trading._tree_component(typedef, __module__))
end

function _tree_component(typedef, mod)
    tn = Overseer.process_typedef(typedef, mod)
    return quote
        Base.@__doc__($typedef)
        Overseer.component_type(::Type{T}) where {T<:$tn} = Trading.TreeComponent{T}
    end
end
