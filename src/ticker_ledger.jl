@component struct Seen{S <: System} end
    
"""
    TickerLedger

A `TickerLedger` holds the data for a given `ticker` as it arrives. Currently this is bar data in the form of
[`Open`](@ref), [`High`](@ref), [`Low`](@ref), [`Close`](@ref) and [`Volume`](@ref), produced by a [`BarStream`](@ref).
If certain derived [`Indicator`](@ref Indicators) data is requested, it also holds this as it is produced by the different systems.
"""
mutable struct TickerLedger <: AbstractLedger
    ticker::String
    l::Ledger
end 

function TickerLedger(ticker::String)
    l = Ledger(Open, High, Low, Close, Volume, TimeStamp)
    TickerLedger(ticker, l)
end

# Overseer.Entity(tl::TickerLedger, args...) = error("You, my friend, are not allowed to add entities to a TickerLedger.")
_Entity(tl::TickerLedger, args...) = Entity(tl.l, args...)

Overseer.ledger(d::TickerLedger) = d.l

function register_strategy!(tl::TickerLedger, strategy::S) where {S<:System} 
    Overseer.ensure_component!(tl, Seen{S})
    for c in Overseer.requested_components(S)
        Overseer.ensure_component!(tl, c)
    end
    Overseer.prepare(tl)
    ensure_systems!(tl)
end

function register_strategy!(tl::TickerLedger, strategy::S) where {S<:Stage} 
    for s in strategy.steps
        register_strategy!(tl, s)
    end
end
register_strategy!(tl::TickerLedger, strategy::Strategy) = register_strategy!(tl, strategy.stage)

function reset!(tl::TickerLedger, strat::S) where {S}
    
    for CT in Overseer.requested_components(strat)
        
        CT in tl && empty!(tl[CT])
        etype = CT
        
        while eltype(etype) != etype
            etype = eltype(etype)
            
            if etype <: Number
                break
            end
            
            etype in tl && empty!(tl[etype])
        end
        
    end
    empty!(tl[Seen{S}])
end


"""
    NewEntitiesIterator

Iterates through all the entities in the requested components of a [`Strategy`](@ref Strategies) that were not yet seen.
"""
struct NewEntitiesIterator{S<:Seen, TT <: Tuple}
    shortest::Overseer.Indices
    seen_comp::Component{S}
    components::TT
end

Base.length(it::NewEntitiesIterator) = length(it.shortest) - length(it.seen_comp) - 1 

#TODO It's a bit slow on construction (150ns), Can't be generated due to worldage with user specified requested_components 
"""
    new_entities(ledger, strategy)

Returns a [`NewEntitiesIterator`](@ref) which iterates through the entities that have components that are requested by `strategy`,
and were not yet seen.
I.e. each entity in those components will be looped over once and only once when iteratively calling `new_entities`.
"""
function new_entities(tl::TickerLedger, strategy::S) where {S}
    comps = map(x -> tl[x], Overseer.requested_components(S))
    shortest = comps[findmin(x -> length(x.indices), comps)[2]].indices
    seen_comp = tl[Seen{S}]
    return NewEntitiesIterator(shortest, seen_comp, comps)
end

function Base.iterate(it::NewEntitiesIterator{S}, state=length(it.seen_comp)+1) where {S<:Seen}

    t = iterate(it.shortest, state)
    t === nothing && return nothing

    @inbounds e = Entity(t[1])
    
    it.seen_comp[e] = S()
    
    return EntityState(e, it.components), t[2]
end 

"""
    lag(entity, i)

Returns the entity that is `i` steps in the past.
"""
Base.@propagate_inbounds function TimeSeries.lag(e::EntityState, i::Int)
    te = Entity(Entity(e).id - i)
    @boundscheck for c in e.components
        if te ∉ c
            return nothing
        end
    end

    return EntityState(te, e.components)
end
