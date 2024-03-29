"""
    interpolate_timearray

Interpolates missing values on a timeframe basis.
"""
function interpolate_timearray(tf::TimeArray{T}; timeframe::Period = Minute(1),
                               daily = false, kwargs...) where {T}
    tstamps = timestamp(tf)
    vals = values(tf)
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
                push!(out_vals[ic], vp + (vals[i, ic] - vp) / nsteps * j)
            end
        end
    end
    return TimeArray(out_times, hcat(out_vals...), colnames(tf))
end

"""
    only_trading(ta::TimeArray)

Filters for data in `ta` during trading sessions. Uses [`in_day`](@ref).
"""
only_trading(ta::TimeArray) = ta[findall(x -> in_day(x), timestamp(ta))]

function Base.split(ta::T, f=day) where {T<:TimeArray}
    tstamps = timestamp(ta)
    change_ids = [1;
                  findall(x -> f(tstamps[x-1]) != f(tstamps[x]), 2:length(ta)) .+ 1;
                  length(ta) + 1]

    out = Vector{T}(undef, length(change_ids) - 1)
    Threads.@threads for i in 1:length(change_ids)-1
        out[i] = ta[change_ids[i]:change_ids[i+1]-1]
    end
    return out
end

function TimeSeries.timestamp(l::AbstractLedger)
    return unique(map(x -> DateTime(x.t), l[Trading.TimeStamp]))
end

function TimeSeries.TimeArray(c::AbstractComponent{PortfolioSnapshot}, tcomp)
    es_to_store = filter(e -> e in tcomp, @entities_in(c))

    pos_dict = Dict{String,Vector{Float64}}()
    pos_timestamps = Dict{String,Vector{DateTime}}()
    pos_dict["portfolio_value"] = Float64[]
    pos_timestamps["portfolio_value"] = DateTime[]

    for e in es_to_store
        tstamp = tcomp[e].t
        for p in e.positions
            arr = get!(pos_dict, p.asset.ticker * "_position", Float64[])
            push!(arr, p.quantity)

            tstamp_arr = get!(pos_timestamps, p.asset.ticker * "_position", DateTime[])
            push!(tstamp_arr, tstamp)
        end

        push!(pos_dict["portfolio_value"], e.value)
        push!(pos_timestamps["portfolio_value"], tstamp)
    end

    out = nothing
    for (colname, positions) in pos_dict
        ta = TimeArray(pos_timestamps[colname], positions, [colname])
        out = out === nothing ? ta : merge(out, ta; method = :outer)
    end

    return out
end

function TimeSeries.TimeArray(c::AbstractComponent{T}, tcomp) where {T}
    es_to_store = filter(e -> e in tcomp, @entities_in(c))
    
    tstamps = map(x -> DateTime(tcomp[x].t), es_to_store)
    vals = map(x -> value(c[x]), es_to_store)

    mat = reduce(hcat, getindex.(vals,i) for i in eachindex(vals[1]))

    return TimeArray(tstamps, mat, colnames(T))
end

function TimeSeries.TimeArray(l::AbstractLedger, cols = keys(components(l)))
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
        eltype(T) <: Union{UpDown, Bollinger, Order} && continue
        
        try
            t = TimeArray(l[T], tcomp)

            if eltype(eltype(t).parameters[2]) != Float64
                continue
            end
            
            out = out === nothing ? t : merge(out, t; method = :outer)
        catch e
            @warn "Method to convert $T into TimeArray not implemented yet."
            showerror(stdout, e)
        end
    end

    if l isa Trader
        for (asset, ledger) in l.asset_ledgers
            ta = TimeArray(ledger)

            ta === nothing && continue

            colnames(ta) .= Symbol.((asset.ticker * "_",) .* string.(colnames(ta)))

            out = out === nothing ? ta : merge(out, ta; method = :outer)
        end
    end

    return out
end

"""
    relative(ta::TimeArray)

Rescales all values in the columns of `ta` with the first value.
"""
function relative(ta::TimeArray)
    out = nothing
    for c in colnames(ta)
        vals = values(ta[c])
        rel_col = ta[c] ./ vals[findfirst(!isnan, vals)]
        out = out === nothing ? rel_col : merge(out, rel_col; method = :outer)
    end
    return out
end
