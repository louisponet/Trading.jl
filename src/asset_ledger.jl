@component struct Seen{S <: System} end
    
"""
    AssetLedger

A `AssetLedger` holds the data for a given `ticker` as it arrives. Currently this is bar data in the form of
[`Open`](@ref), [`High`](@ref), [`Low`](@ref), [`Close`](@ref) and [`Volume`](@ref), produced by a [`DataStream`](@ref).
If certain derived [`Indicator`](@ref Indicators) data is requested, it also holds this as it is produced by the different systems.
"""
mutable struct AssetLedger <: AbstractLedger
    asset::Asset
    l::Ledger
    latest_quote::Tuple{TimeStamp, Ask, Bid}
end

function Base.getproperty(t::AssetLedger, s::Symbol)
    if s == :ticker
        return t.asset.ticker
    else
        return getfield(t, s)
    end
end

function AssetLedger(asset::Asset)
    l = Ledger(Open, High, Low, Close, Volume, TimeStamp, Ask, Bid, Trade)
    return AssetLedger(asset, l, (TimeStamp(), Ask(0,0), Bid(0,0)))
end

# Overseer.Entity(tl::AssetLedger, args...) = error("You, my friend, are not allowed to add entities to a AssetLedger.")
_Entity(tl::AssetLedger, args...) = Entity(tl.l, args...)

function new_bar!(tl::AssetLedger, time::TimeStamp, open::Open, high::High, low::Low, close::Close, volume::Volume; interval=Minute(1))
    tcomp = tl[TimeStamp]
    intval = Millisecond(interval) 
    if length(tl[Open]) > 1
        
        last_t = tcomp[end].t
        cur_dt =  time.t - last_t
        if abs(intval - cur_dt) > Millisecond(50)
            nsteps = div(cur_dt, interval)

            last_open = tl[Open][end]
            last_high = tl[High][end]
            last_low = tl[Low][end]
            last_close = tl[Close][end]

            for i = 1:nsteps-1
                Entity(tl.l,
                       TimeStamp(last_t + intval),
                       last_open + (open - last_open)/nsteps * i,
                       last_high + (high - last_high)/nsteps * i,
                       last_low + (low - last_low)/nsteps * i,
                       last_close + (close - last_close)/nsteps * i,
                       Volume(0))
            end
        end
    end
    Entity(tl.l, time, open, high, low, close, volume)
end

Overseer.ledger(d::AssetLedger) = d.l

function register_strategy!(tl::AssetLedger, strategy::S) where {S<:System} 
    ensure_component!(tl, Seen{S})
    for c in Overseer.requested_components(strategy)
        ensure_component!(tl, c)
    end
    Overseer.prepare(tl)
    ensure_systems!(tl)
end

function register_strategy!(tl::AssetLedger, strategy::S) where {S<:Stage} 
    for s in strategy.steps
        register_strategy!(tl, s)
    end
end
register_strategy!(tl::AssetLedger, strategy::Strategy) = register_strategy!(tl, strategy.stage)

function reset!(tl::AssetLedger, strat::S) where {S}
    
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

Base.length(it::NewEntitiesIterator) = length(it.shortest) - length(it.seen_comp)

#TODO It's a bit slow on construction (150ns), Can't be generated due to worldage with user specified requested_components 
"""
    new_entities(ledger, strategy)

Returns a [`NewEntitiesIterator`](@ref) which iterates through the entities that have components that are requested by `strategy`,
and were not yet seen.
I.e. each entity in those components will be looped over once and only once when iteratively calling `new_entities`.
"""
function new_entities(tl::AssetLedger, strategy::S) where {S}
    comps = map(x -> tl[x], Overseer.requested_components(strategy))
    shortest = comps[findmin(x -> length(x.indices), comps)[2]].indices
    seen_comp = tl[Seen{S}]
    return NewEntitiesIterator(shortest, seen_comp, comps)
end

function Base.iterate(it::NewEntitiesIterator{S}, state=length(it.seen_comp)+1) where {S<:Seen}

    t = iterate(it.shortest, state)
    t === nothing && return nothing

    @inbounds e = Entity(t[1])
    
    it.seen_comp[e] = S()
    
    return EntityState(e, it.components...), t[2]
end 

"""
    prev(entity, i)

Returns the entity that is `i` steps in the past.
"""
Base.@propagate_inbounds function prev(e::EntityState, i::Int)
    c = e.components[1]
    
    curid = c.indices[Entity(e).id]
    
    found_entities = 0
    while curid > 1
        curid -= 1
        
        te = Entity(c, curid)
        
        if all(comp -> te in comp, e.components)
            found_entities += 1
            
            if found_entities == i
                return EntityState(te, e.components...)
            end
            
        end
    end
end
