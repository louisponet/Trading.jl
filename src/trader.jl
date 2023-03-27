abstract type AbstractTrader <: AbstractLedger end

Entity(t::AbstractTrader, args...) = Entity(t.l, TimeStamp(t), args...)

function Overseer.update(trader::AbstractTrader)
    singleton(trader, PurchasePower).cash = singleton(trader, Cash).cash 
    ticker_ledgers = values(trader.ticker_ledgers)
    
    update(stage(trader, :main), trader)
    
    for s in stages(trader)
        s.name == :main && continue
        update(s, trader)
    end
    for tl in ticker_ledgers
        empty!(tl[New])
    end
end 

in_day(l::AbstractTrader) = in_day(current_time(l))

function current_position(t::AbstractLedger, ticker::String)
    pos_id = findfirst(x->x.ticker == ticker, t[Position])
    pos_id === nothing && return 0.0
    return t[Position][pos_id].quantity
end

TimeStamp(l::AbstractTrader) = TimeStamp(current_time(l))

function ensure_systems!(l::AbstractLedger)
    stageid = findfirst(x -> x.name == :indicators, stages(l))
    if stageid !== nothing
        ind_stage = stages(l)[stageid]
    else
        ind_stage = Stage(:indicators, System[])
    end

    for (T, c) in components(l)
        if T <: SMA                    && SMACalculator()                ∉ ind_stage
            push!(ind_stage,              SMACalculator())
        elseif T <: MovingStdDev       && MovingStdDevCalculator()       ∉ ind_stage
            push!(ind_stage,              MovingStdDevCalculator())
        elseif T <: EMA                && EMACalculator()                ∉ ind_stage
            push!(ind_stage,              EMACalculator())
        elseif T <: UpDown             && UpDownSeparator()              ∉ ind_stage
            push!(ind_stage,              UpDownSeparator())
        elseif T <: Difference         && DifferenceCalculator()         ∉ ind_stage
            push!(ind_stage,              DifferenceCalculator())
        elseif T <: RelativeDifference && RelativeDifferenceCalculator() ∉ ind_stage
            push!(ind_stage,              RelativeDifferenceCalculator())
        elseif T <: Sharpe             && SharpeCalculator()             ∉ ind_stage
            push!(ind_stage,              SharpeCalculator())
        elseif T <: LogVal             && LogValCalculator()             ∉ ind_stage
            push!(ind_stage,              LogValCalculator())
        elseif T <: RSI                && RSICalculator()                ∉ ind_stage
            push!(ind_stage,              RSICalculator())
        elseif T <: Bollinger          && BollingerCalculator()          ∉ ind_stage
            push!(ind_stage,              BollingerCalculator())
        end
    end

    mainid = findfirst(x -> x.name == :main, stages(l))
    if mainid === nothing
        push!(l, ind_stage)
    else
        insert!(stages(l), mainid + 1, ind_stage)
    end
end

function timestamps(l::AbstractLedger)
    unique(map(x->DateTime(x.t), l[Trading.TimeStamp]))
end

function TimeSeries.TimeArray(l::AbstractLedger, cols=keys(components(l)))

    out = nothing

    tcomp = l[TimeStamp]
    for T in cols
        T_comp = l[T]
        es_to_store = filter(e -> e in tcomp, @entities_in(l[T]))
        if length(es_to_store) < 2
            continue
        end
        timestamps = map(x->DateTime(tcomp[x].t), es_to_store)

        fields_to_store = filter(x -> fieldtype(T, x) <: Number, fieldnames(T))
        colnames = map(f -> "$(T)_$f", fields_to_store)
        if isempty(fields_to_store)
            continue
        end

        dat = map(fields_to_store) do field
            map(x->Float64(getfield(x[T], field)), es_to_store)
        end
        t = TimeArray(timestamps, hcat(dat...), String[colnames...])
        out = out === nothing ? t : merge(out, t, method=:outer)
    end
    return out
end

function TimeSeries.TimeArray(ticker, timeframe, start, stop, account)
    l = Ledger(Stage(:core, [Trading.DatasetAdder()]))
    Entity(l, account, Trading.Dataset(ticker, timeframe, start, stop))
    Trading.update(l)
    return TimeArray(l)
end
