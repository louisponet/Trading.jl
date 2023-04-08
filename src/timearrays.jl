"""
    interpolate_timearray

Interpolates missing values on a timeframe basis.
"""
function interpolate_timearray(tf::TimeArray{T}; timeframe::Period = Minute(1), daily=false, kwargs...) where {T}
    tstamps = timestamp(tf)
    vals  = values(tf) 
    start = tstamps[1]
    stop = tstamps[end]
    out_times = TimeDate[start]
    ncols = size(vals, 2)
    out_vals = [[vals[1, i]] for i in 1:ncols]

    for i in 2:length(tf)
        prev_i = i - 1
        
        curt = tstamps[i]
        prevt = tstamps[prev_i]

        dt = curt - prevt

        if dt == timeframe || (daily && day(curt) != day(prevt))
            push!(out_times, curt)
            for ic in 1:ncols
                push!(out_vals[ic], vals[i, ic])
            end
            continue
        end
        nsteps = dt / timeframe
        for j in 1:nsteps
            push!(out_times, prevt + timeframe * j)
            for ic in 1:ncols
                vp = vals[prev_i, ic]
                push!(out_vals[ic], vp + (vals[i, ic] - vp)/nsteps * j)
            end
            
        end
    end
    TimeArray(out_times, hcat(out_vals...), colnames(tf))
end

only_trading(bars::TimeArray) =
    bars[findall(x->in_trading(x), timestamp(bars))]

function split_days(ta::T) where {T <: TimeArray}
    tstamps = timestamp(ta)
    day_change_ids = [1; findall(x-> day(tstamps[x-1]) != day(tstamps[x]), 2:length(ta)) .+ 1; length(ta)+1]

    out = Vector{T}(undef, length(day_change_ids)-1)
    Threads.@threads for i = 1:length(day_change_ids)-1
        out[i] = ta[day_change_ids[i]:day_change_ids[i+1]-1]
    end
    return out
end

TimeSeries.timestamp(l::AbstractLedger) = 
    unique(map(x->DateTime(x.t), l[Trading.TimeStamp]))

function TimeSeries.TimeArray(c::AbstractComponent{PortfolioSnapshot}, tcomp)
    es_to_store = filter(e -> e in tcomp, @entities_in(c))
    
    tstamps = map(x->DateTime(tcomp[x].t), es_to_store)
    
    pos_dict = Dict{String, Vector{Float64}}()

    pos_dict["value"] = Float64[]

    for e in es_to_store
        for p in e.positions
            arr = get!(pos_dict, p.ticker * "_position", Float64[])
            push!(arr, p.quantity)
        end
        push!(pos_dict["value"], e.value) 
    end
    
    return TimeArray(tstamps, hcat(values(pos_dict)...), collect(keys(pos_dict)))
end

function TimeSeries.TimeArray(c::AbstractComponent{T}, tcomp) where {T}
    
    es_to_store = filter(e -> e in tcomp, @entities_in(c))
    tstamps = map(x->DateTime(tcomp[x].t), es_to_store)
    
    colname = replace("$(T)", "Trading." => "")
    
    return TimeArray(tstamps, map(x-> value(c[x]), es_to_store), String[colname])
end

function TimeSeries.TimeArray(l::AbstractLedger, cols=keys(components(l)))
    
    if TimeStamp ∉ l
        return nothing
    end
    
    out = nothing
    
    tcomp = l[TimeStamp]
    for T in cols

        T == TimeStamp && continue
        
        !hasmethod(value, (T,)) && continue

        comp = l[T]
        isempty(comp) && continue
        
        t = TimeArray(l[T], tcomp)
        out = out === nothing ? t : merge(out, t, method=:outer)
    end

    if l isa Trader
        for (ticker, ledger) in l.ticker_ledgers
            ta = TimeArray(ledger)

            ta === nothing && continue
            
            colnames(ta) .= Symbol.((ticker * "_",) .* string.(colnames(ta)))
            
            out = out === nothing ? ta : merge(out, ta, method=:outer)
        end
    end
    
    return out
end

function relative(ta::TimeArray)
    out = nothing
    for c in colnames(ta)
        vals = values(ta[c])
        rel_col = ta[c]./vals[findfirst(!isnan, vals)]
        out = out === nothing ? rel_col : merge(out, rel_col, method=:outer)
    end
    return out
end
