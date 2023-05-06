using Overseer: EntityState
using Base: RefArray

struct EntityNode{RT <: Ref}
    e::Entity
    ptr::RT
    
end

Base.:(<)(en1::EntityNode, en2::EntityNode) = en1.ptr[] < en2.ptr[]
Base.:(==)(en1::EntityNode, en2::EntityNode) = en1.ptr[] == en2.ptr[]

Base.:(<)(en1::EntityNode, v) = en1.ptr[] < v
Base.:(<)(v, en1::EntityNode) = v < en1.ptr[]

Base.:(==)(en1::EntityNode, v) = en1.ptr[] == v
Base.:(==)(v, en1::EntityNode) = en1.ptr[] == v

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
    tree::Tree{EntityNode{RefArray{T, Component{T}, Nothing}}}
end
TreeComponent{T}() where {T} = TreeComponent{T}(Component{T}(), Tree{EntityNode{RefArray{T, Component{T}, Nothing}}}())
Overseer.component(t::TreeComponent) = t.c

function Base.setindex!(t::TreeComponent, v, e::Overseer.AbstractEntity)
    if e in t
        @inbounds setindex!(t.c, v, e)
    else
        out = setindex!(t.c, v, e)
        push!(t.tree, EntityNode(Entity(e), Ref(t.c, e)))
    end
    return t
end

function Base.getindex(t::TreeComponent, v)
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
