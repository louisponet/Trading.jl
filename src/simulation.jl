mutable struct SimulatedTrader <: AbstractTrader
    l::Ledger
    loop::Union{Task, Nothing}
    ticker_ledgers::Dict{String, Ledger}
    historical_ledgers::Dict{String, Ledger}
    last_order_ids::Dict{String, Int}
    cur_bar_ids::Dict{String, Int}
    done::Bool
    cur_order_id ::Int
end

Overseer.ledger(trader::SimulatedTrader) = trader.l

in_session_stage(::Type{SimulatedTrader}) = Stage(:main, [Purchaser(), Seller(), Filler(), SnapShotter(), Timer(), BarUpdater(), OrderUpdater(), DayCloser()])
end_of_day_stage(::Type{SimulatedTrader}) = Stage(:main, [Seller(), Filler(), SnapShotter(), Timer(), BarUpdater(), OrderUpdater(), DayOpener()])

function SimulatedTrader(account::AccountInfo, tickers::Vector{String}, strategies; dt=Minute(1), start=now() - dt*1000, stop = now(), cash = 1_000_000)

    stages = Stage[]
    inday = in_day(start)
    
    if inday 
        push!(stages, in_session_stage(SimulatedTrader))
    else
        push!(stages, end_of_day_stage(SimulatedTrader))
    end

    for s in strategies
        if !s.only_day
            push!(stages, s.stage)
        elseif inday
            push!(stages, s.stage)
        end
    end
        
    l = Ledger(stages...)
    
    ensure_systems!(l)

    if dt == Minute(1)
        timeframe = "1Min"
    elseif dt == Minute(5)
        timeframe = "5Min"
    elseif dt == Minute(10)
        timeframe = "10Min"
    elseif dt == Minute(15)
        timeframe = "15Min"
    elseif dt == Minute(30)
        timeframe = "15Min"
    elseif dt == Hour(1)
        timeframe = "1H"
    elseif dt == Day(1)
        timeframe = "1Day"
    else
        throw(ArgumentError("$dt is not a supported timeframe."))
    end

    historical_ledgers = Dict{String, Ledger}()
    ticker_ledgers     = Dict{String, Ledger}()
    
    last_order_ids  = Dict{String, Int}()
    cur_bar_ids     = Dict{String, Int}()

    @info "Fetching historical data"
    Threads.@threads for ticker in tickers
        
        historical = Ledger(Stage(:main, [DatasetAdder()]))
        
        Entity(historical, Dataset(ticker, timeframe, TimeDate(start), TimeDate(stop)), account)
        update(historical)
        
        historical_ledgers[ticker] = historical

        ticker_ledger = Ledger()
        for s in strategies
            for c in Overseer.requested_components(s.stage)
                Overseer.ensure_component!(ticker_ledger, c)
            end
        end

        ensure_systems!(ticker_ledger)
        ticker_ledgers[ticker] = ticker_ledger
        
        last_order_ids[ticker] = 1
        cur_bar_ids[ticker]    = 1
    end

    Entity(l, Clock(TimeDate(start), dt), Cash(cash), PurchasePower(cash))
    for s in strategies
        Entity(l, s)
    end
    
    return SimulatedTrader(l, nothing, ticker_ledgers, historical_ledgers, last_order_ids, cur_bar_ids, false, 1)
end

function reset!(trader::SimulatedTrader)
    
    for (ticker, l) in trader.ticker_ledgers
        
        empty_entities!(l)
        trader.last_order_ids[ticker] = 1
        trader.cur_bar_ids[ticker] = 1
        
    end
    dt = trader[Clock][1].dtime
    cash = isempty(trader[PortfolioSnapshot]) ? trader[Cash][1].cash : trader[PortfolioSnapshot][1].cash

    start = minimum(x->x[Dataset][1].start, values(trader.historical_ledgers))

    empty_entities!(trader)
    Entity(trader.l, Clock(start, dt), Cash(cash), PurchasePower(cash))
    trader.cur_order_id = 1
    return trader
end


current_time(trader::SimulatedTrader) = trader[Clock][1].time

function current_price(trader::SimulatedTrader, ticker::String, curt=current_time(trader))

    tl   = trader.historical_ledgers[ticker]

    last_id = trader.last_order_ids[ticker]
    order_id = findnext(x -> x.t >= curt, tl[TimeStamp], last_id)

    order_id === nothing && return nothing
    
    trader.last_order_ids[ticker] = order_id

    return tl[Open][order_id].v
end


function start(trader::SimulatedTrader; sleep_time = 0.001)

    last = trader[Clock][1].time
    for (ticker, ledger) in trader.historical_ledgers
        tstop = ledger[Dataset][1].stop === nothing ? TimeDate(now()) : ledger[Dataset][1].stop
        last = max(tstop, last)
    end

    p = ProgressMeter.ProgressUnknown("Simulating..."; spinner = true) 
    while current_time(trader) < last && !trader.done
        update(trader)
        showvalues = isempty(trader[PortfolioSnapshot]) ?
                     [(:t, trader[Clock][1].time), (:value, trader[Cash][1].cash)] :
                     [(:t, trader[Clock][1].time), (:value, trader[PortfolioSnapshot][end].value)]
        ProgressMeter.next!(p; spinner = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏", showvalues = showvalues)
    end
    ProgressMeter.finish!(p)
    
    trader.done=false
end

struct BarUpdater <: System end

function Overseer.update(::BarUpdater, trader::SimulatedTrader)
    curt = current_time(trader)

    if !in_day(curt)
        return
    end
    
    for (ticker, ledger) in trader.historical_ledgers
        
        ticker_ledger = trader.ticker_ledgers[ticker]
        cur_bar_id = trader.cur_bar_ids[ticker]
        
        tstampcomp = ledger[TimeStamp]

        if cur_bar_id + 1 > length(tstampcomp)
            continue
        end
        
        last_t = TimeStamp in ticker_ledger && length(ticker_ledger[TimeStamp]) > 0 ? ticker_ledger[TimeStamp][end].t : TimeDate(0)
        if curt <= last_t
            continue
        end

        tid = findnext(x->x.t > curt, tstampcomp, cur_bar_id + 1)
        if tid !== nothing && tstampcomp[tid-1].t > last_t 
            bar_e = entity(tstampcomp, tid-1)
            tl = trader.ticker_ledgers[ticker]
            bar = ledger[bar_e]
            new_e = Entity(tl, bar..., New())
            
            trader.cur_bar_ids[ticker] = tid-1
        end
    end
end

struct OrderUpdater <: System end

function Overseer.update(::OrderUpdater, trader::SimulatedTrader)
    cash = copy(singleton(trader, Cash).cash)
    if length(trader[Order]) >= trader.cur_order_id
        filled = 0
        for id in trader.cur_order_id:length(trader[Order])
            order = trader[Order][id]
            e = entity(trader[Order], id)

            price = current_price(trader, order.ticker, order.created_at)
            price === nothing && continue

            order.filled_at = current_time(trader)
            order.updated_at = order.filled_at
            
            if e in trader[Purchase]
                filled_quantity = round(min(cash/price, order.requested_quantity), RoundDown)
                cash -= filled_quantity * price
            elseif e in trader[Sale]
                filled_quantity = min(current_position(trader, order.ticker), order.requested_quantity)
                cash += filled_quantity * price
            end
            
            order.filled_qty = filled_quantity
            order.status = "filled"
            order.filled_avg_price = price
            
            filled += 1
        end
        trader.cur_order_id += filled
    end
end

function submit_order(trader::SimulatedTrader, e; quantity = e.quantity)
    return Order(e.ticker,
                 UUIDs.uuid1(),
                 UUIDs.uuid1(),
                 current_time(trader),
                 nothing,
                 nothing,
                 nothing,
                 nothing,
                 nothing,
                 nothing,
                 0,
                 0.0,
                 "submitted",
                 quantity)
end
