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

function SimulatedTrader(account::AccountInfo, ticker_ledgers::Dict{String, Ledger}, strategy_stage; dt=Minute(1), start=now() - dt*1000, stop = now(), cash = 1_000_000)
    core_stage = Stage(:main, [Purchaser(), Seller(), Filler(), SnapShotter(), Timer(), BarUpdater(), OrderUpdater()])
    l = Ledger(core_stage, strategy_stage)

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
    last_order_ids     = Dict{String, Int}()
    cur_bar_ids     = Dict{String, Int}()
    for (ticker, ledger) in ticker_ledgers
        
        tl = Ledger(Stage(:main, [DatasetAdder()]))
        Entity(tl, Dataset(ticker, timeframe, TimeDate(start), TimeDate(stop)), account)
        update(tl)

        for c in Overseer.requested_components(strategy_stage)
            Overseer.ensure_component!(ledger, c)
        end
        
        start = min(tl[Dataset][1].start, start)
        historical_ledgers[ticker] = tl

        last_order_ids[ticker] = 1
        cur_bar_ids[ticker] = 1
    end

    # TODO BAD
    Entity(l, TimingData(start, dt), Cash(cash), PurchasePower(cash))
    return SimulatedTrader(l, nothing, ticker_ledgers, historical_ledgers, last_order_ids, cur_bar_ids, false, 1)
end

function reset!(trader::SimulatedTrader)
    for (ticker, l) in trader.ticker_ledgers
        empty_entities!(l)
        trader.last_order_ids[ticker] = 1
        trader.cur_bar_ids[ticker] = 1
    end
    dt = trader[TimingData][1].dtime
    cash = isempty(trader[PortfolioSnapshot]) ? trader[Cash][1].cash : trader[PortfolioSnapshot][1].cash

    start = minimum(x->x[Dataset][1].start, values(trader.historical_ledgers))

    empty_entities!(trader)
    Entity(trader, TimingData(start, dt), Cash(cash), PurchasePower(cash))
    trader.cur_order_id = 1
    return trader
end


current_time(trader::SimulatedTrader) = trader[TimingData][1].time

function current_price(trader::SimulatedTrader, ticker::String, curt=current_time(trader))

    tl   = trader.historical_ledgers[ticker]

    last_id = trader.last_order_ids[ticker]
    order_id = findnext(x -> x.t >= curt, tl[TimeStamp], last_id)

    order_id === nothing && return nothing
    
    trader.last_order_ids[ticker] = order_id

    return tl[Open][order_id].v
end

function Overseer.update(trader::SimulatedTrader)
    singleton(trader, PurchasePower).cash = singleton(trader, Cash).cash 
    ticker_ledgers = values(trader.ticker_ledgers)
    cur_es = sum(x -> length(x.entities), ticker_ledgers)
    
    update(stage(trader, :main), trader)
    
    if sum(x -> length(x.entities), ticker_ledgers) - cur_es > 0  
        @sync for tl in ticker_ledgers
            Threads.@spawn update(tl)
        end
    end
    for s in stages(trader)
        s.name == :main && continue
        update(s, trader)
    end
    for tl in ticker_ledgers
        empty!(tl[New])
    end
end 

function start(trader::SimulatedTrader; sleep_time = 0.001)

    last = trader[TimingData][1].time
    for (ticker, ledger) in trader.historical_ledgers
        tstop = ledger[Dataset][1].stop === nothing ? TimeDate(now()) : ledger[Dataset][1].stop
        last = max(tstop, last)
    end

    while current_time(trader) < last && !trader.done
        update(trader)
    end
    trader.done=false
end

struct BarUpdater <: System end

function Overseer.update(::BarUpdater, trader::SimulatedTrader)
    curt = current_time(trader)
    open, close = market_open_close(curt)
    # if curt < open || curt > close
    #     return
    # end
    for (ticker, ledger) in trader.historical_ledgers
        
        ticker_ledger = trader.ticker_ledgers[ticker]
        cur_bar_id = trader.cur_bar_ids[ticker]
        
        tstampcomp = ledger[TimeStamp]

        if cur_bar_id + 1 > length(tstampcomp)
            continue
        end
        last_t = TimeStamp in ticker_ledger ? ticker_ledger[TimeStamp][end].t : TimeDate(0)
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
