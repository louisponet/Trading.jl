struct Timer <: System end

Overseer.requested_components(::Timer) = (TimingData,)

function Overseer.update(::Timer, l::AbstractLedger)
    for t in l[TimingData]
        nt = now()
        t.dtime = t.reversed ? -nt + t.time : nt - t.time
        t.time = nt
    end
end

struct DatasetAdder <: System end

Overseer.requested_components(::DatasetAdder) = (TimingData, Dataset, AccountInfo)

function Overseer.update(::DatasetAdder, l::AbstractLedger)
    account = singleton(l, AccountInfo)
    for d in l[Dataset]
        if d.first_e == Entity(0)
            
            times, bars = query_bars(account, d.ticker, d.start, stop=d.stop, timeframe=d.timeframe)
            
            if !isempty(bars)
                d.first_e = Entity(l, bars[1], times[1]) 
                for (b, t) in zip(view(bars, 2:length(bars)-1), view(times, 2:length(times)-1))
                    Entity(l, b, t)
                end
                d.last_e = Entity(l, bars[end], times[end])
            end
        end
    end
end
        

