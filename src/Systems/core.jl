struct Timer <: System end

Overseer.requested_components(::Timer) = (Clock,)

function Overseer.update(::Timer, l::AbstractLedger)
    for t in l[Clock]
        if t.dtime.value == 0
            t.time = current_time()
        end
    end
end

struct StrategyRunner <: System end
    
Overseer.requested_components(::Type{StrategyRunner}) = (Strategy,)

function Overseer.update(::StrategyRunner, t::Trader)
    inday = in_day(current_time(t))
    
    for e in t[Strategy]
        
        if e.only_day && !inday
            continue
        end

        update(e.stage, t)
    end
end
