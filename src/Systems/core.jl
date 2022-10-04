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
    for (d, es) in pools(l[Dataset])
        if length(es) > 1
            continue
        end
        parent = es[1]
            
        times, bars = query_bars(account, d.ticker, d.start, stop=d.stop, timeframe=d.timeframe)
            
        if !isempty(bars)
            for c in bars[1]
                l[parent] = c
            end
            l[parent] = times[1]
            for i in 2:length(bars)
                e = Entity(l, bars[i]..., times[i])
                l[Dataset][e] = parent
            end
        end
    end
end
        

