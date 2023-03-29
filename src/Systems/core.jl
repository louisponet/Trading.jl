struct DatasetAdder <: System end

Overseer.requested_components(::DatasetAdder) = (Dataset, )

struct SnapShotter <: System end

Overseer.requested_components(::SnapShotter) = (PortfolioSnapshot, TimeStamp)

function Overseer.update(::SnapShotter, l::AbstractLedger)
    curt = current_time(l)
    if !in_day(curt)
        return
    end
    
    if length(l[PortfolioSnapshot]) > 0
        last_snapshot_e = entity(l[PortfolioSnapshot], length(l[PortfolioSnapshot]))
        
        curt - l[TimeStamp][last_snapshot_e].t < Minute(1) && return
    end
        
    cash  = singleton(l, Cash)[Cash]
    totval = cash.cash
    positions = Position[]
    
    for e in @entities_in(l, Position)
        push!(positions, deepcopy(e[Position]))
        price = Data.current_price(l, e.ticker)
        totval += price * e.quantity
    end
    
    new_e = Entity(l, TimeStamp(current_time(l)), PortfolioSnapshot(positions, cash.cash, totval))
end

struct Timer <: System end

Overseer.requested_components(::Timer) = (Clock,)

function Overseer.update(::Timer, l::AbstractLedger)
    for t in l[Clock]
        t.time += t.dtime
    end
end
