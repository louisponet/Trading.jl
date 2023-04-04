struct Timer <: System end

Overseer.requested_components(::Timer) = (Clock,)

function Overseer.update(::Timer, l::AbstractLedger)
    for t in l[Clock]
        if t.dtime.value == 0
            t.time = current_time()
        end
    end
end
