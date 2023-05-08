using Overseer: EntityState, AbstractEntity
using Base: RefArray

mutable struct EntityPtr{RT <: Ref}
    e::Entity
    ptr::RT
end
EntityPtr(e::AbstractEntity, c::AbstractComponent) = EntityPtr(Entity(e), Ref(c, e)) 

Base.:(<)(en1::EntityPtr, en2::EntityPtr) = en1.ptr[] < en2.ptr[]
Base.:(==)(en1::EntityPtr, en2::EntityPtr) = en1.ptr[] == en2.ptr[]

Base.:(<)(v, en1::EntityPtr) = v < en1.ptr[]

Base.:(==)(v, en1::EntityPtr) = en1.ptr[] == v

Base.:(==)(en1::EntityPtr, e::AbstractEntity) = en1.e == Entity(e)
Base.:(==)(e::AbstractEntity, e1::EntityPtr) = e1.e == Entity(e)

function Base.getproperty(e::EntityPtr, s::Symbol)
    if s in (:e, :ptr)
        return getfield(e, s)
    else
        return getproperty(e.ptr[], s)
    end
end

function Base.show(io::IO, m::MIME"text/plain", e::EntityPtr)
    print(io, "EntityPtr(")
    show(io, m, e.e)
    print(io, ", ")  
    show(io, m, e.ptr[])
    print(io, ")")
end

function Base.show(io::IO, e::EntityPtr)
    show(io,  e.e)
end
    
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
function Base.show(io::IO, node::ListNode)
    if isdefined(node, :data)
        print(io, "ListNode(", node.data, ")")
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
    
    function LinkedList(node::ListNode{T}) where {T}
        out = new{T}()
        out.nil = ListNode{T}()
        out.head = node
        out.tail = node
        node.prev = out.nil
        node.next = out.nil
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
    count = 0
    for node in l
        count += 1
    end
    return count
end

function Base.haskey(l::LinkedList, o)
    for node in l
        if node.data == o
            return true
        end
    end
    return false
end

function Base.getindex(l::LinkedList, d)
    for node in l
        if node.data == d
            return node
        end
    end
    return BoundsError(l, d)
end

Base.eltype(l::LinkedList{T}) where {T} = T

function Base.iterate(l::LinkedList, state = l.head)
    state === l.nil && return nothing
    return state, state.next
end

function Base.delete!(l::LinkedList{T}, o::ListNode{T}) where {T}
    if l.head === o
        l.head = o.next
    end
    if l.tail === o
        l.tail = o.prev
    end
end

function Base.delete!(l::LinkedList, d)
    node = l[d]
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
    d.next = l.nil
    
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

Base.:(<)(l1::LinkedList, l2::LinkedList) = l1.head < l2.head
Base.:(==)(l1::LinkedList, l2::LinkedList) = l1.head == l2.head

Base.:(<)(l1, l2::LinkedList) = l1 < l2.head
Base.:(==)(l1, l2::LinkedList) = l1 == l2.head

function Base.show(io::IO, m::MIME"text/plain", l::LinkedList{T}) where {T}
    if !isempty(l)
        node = l.head
        while true
            show(io, m, node)
            if node !== l.tail
                print(io, " -> ")
            else
                break
            end
            node = node.next
        end
    else
        println(io, "LinkedList()")
    end
end
function Base.show(io::IO, l::LinkedList{T}) where {T}
    if !isempty(l)
        node = l.head
        while true
            show(io, node)
            if node !== l.tail
                print(io, " -> ")
            else
                break
            end
            node = node.next
        end
    else
        println(io, "LinkedList()")
    end
end

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

function Base.empty!(t::TreeComponent)
    empty!(t.tree)
    empty!(t.c)
    return t
end

    
function Base.setindex!(t::TreeComponent{T}, v::T, e::Overseer.AbstractEntity) where {T}
    if e in t
        old_v = @inbounds t[e]
        
        old_v == v && return t
        
        old_entity_list = search_node(t.tree, old_v).data
        
        if length(old_entity_list) == 1
            delete!(t.tree, old_entity_list)
        end
        node = delete!(old_entity_list, e)
        
        @inbounds setindex!(t.c, v, e)
        
    else
        
        out = setindex!(t.c, v, e)
        node = ListNode(EntityPtr(Entity(e), Ref(t.c, e)))
        
    end
    new_entity_list = search_node(t.tree, v)

    if new_entity_list === nothing

        new_entity_list = LinkedList(node)
        push!(t.tree, new_entity_list)
    else
        push!(new_entity_list.data, node)
    end

    return t
end

function Base.getindex(t::TreeComponent{T}, v::T) where {T}
    node = search_node(t.tree, v)
    
    if node !== nothing && v == node.data
        return node.data
    end
    return nothing
end

function Base.ceil(t::TreeComponent, v)
    node = ceil(t.tree, v)
    
    node === nothing && return nothing
    
    return node.data
end

function Base.floor(t::TreeComponent, v)
    node = floor(t.tree, v)

    node === nothing && return nothing
    
    return node.data
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

Base.@propagate_inbounds function Base.pop!(t::TreeComponent, e::AbstractEntity;
                                            v = t.c[e],
                                            list = search_node(t.tree, v).data,
                                            list_len = length(list))
    
    # We need to set the ref of the current last entity to point to the position of the
    # one we're removing becuase that's how pop works
    if length(t.c) > 1
        curlast = last_entity(t.c)
        last_list = search_node(t.tree, t[curlast]).data
        entitynode = last_list[curlast]
        entitynode.ptr = Ref(t.c, e)
    end
    
    if list_len == 1
        delete!(t.tree, list)
    end
    
    pop!(t.c, e)
    node = delete!(list, e)

    return EntityState(Entity(e), v)
end

Base.@propagate_inbounds Base.pop!(t::TreeComponent) = pop!(t, last_entity(t))
