"""
Updates the [`Clock`](@ref) of the [`Trader`](@ref).
"""
struct Timer <: System end

Overseer.requested_components(::Timer) = (Clock,)

function Overseer.update(::Timer, l::AbstractLedger)
    for t in l[Clock]
        if t.dtime.value == 0
            t.time = current_time()
        end
    end
end

"""
Runs all the [`Strategies`](@ref Strategy).
"""
struct StrategyRunner <: System end

Overseer.requested_components(::Type{StrategyRunner}) = (Strategy,)

function Overseer.update(::StrategyRunner, t::Trader)
    inday = in_day(current_time(t))

    for e in t[Strategy]
        if e.only_day && !inday
            continue
        end
        if !isempty(e.assets)
            combined = typeof(e.assets[1])(join(e.assets, "_"))

            update(e.stage, t, [map(asset -> t[asset], e.assets); t[combined]])
        else
            update(e.stage, t, e.assets)
        end
            
    end
end
