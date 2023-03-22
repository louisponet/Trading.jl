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

function SimulatedTrader(account::AccountInfo, ticker_ledgers::Dict{String, Ledger}; dt=Minute(1), cash = 1_000_000)
    core_stage = Stage(:main, [Purchaser(), Seller(), Filler(), SnapShotter(), Timer(), BarUpdater(), OrderUpdater()])
    l = Ledger(core_stage)

    start = TimeDate(now())

    historical_ledgers = Dict{String, Ledger}()
    last_order_ids     = Dict{String, Int}()
    cur_bar_ids     = Dict{String, Int}()
    for (ticker, ledger) in ticker_ledgers
        
        tl = Ledger(Stage(:main, [DatasetAdder()]))
        Entity(tl, deepcopy(ledger[Dataset][1]), account)
        update(DatasetAdder(), tl)
        
        start = min(ledger[Dataset][1].start, start)
        historical_ledgers[ticker] = tl

        last_order_ids[ticker] = 1
        cur_bar_ids[ticker] = 1
    end
   
    # TODO BAD
    Entity(l, Trading.Dataset("Portfolio", "1Min", start), TimingData(start, dt), Cash(cash))
    return SimulatedTrader(l, nothing, ticker_ledgers, historical_ledgers, last_order_ids, cur_bar_ids, false, 1)
end

current_time(trader::SimulatedTrader) = trader[TimingData][1].time

function ticker_value(trader::SimulatedTrader, ticker::String, curt=current_time(trader))

    tl   = trader.historical_ledgers[ticker]

    last_id = trader.last_order_ids[ticker]

    order_id = findnext(x -> x.time >= curt, tl[TimeStamp], last_id + 1)

    order_id === nothing && return nothing
    
    trader.last_order_ids[ticker] = order_id

    return tl[Open][order_id]
end

function start(trader::SimulatedTrader; sleep_time = 0.001)

    last = trader[TimingData][1].time
    for (ticker, ledger) in trader.historical_ledgers
        tstop = ledger[Dataset][1].stop === nothing ? TimeDate(now()) : ledger[Dataset][1].stop
        last = max(tstop, last)
    end

    while current_time(trader) < last && !trader.done
        ticker_ledgers = values(trader.ticker_ledgers)
        cur_es = sum(x -> length(x.entities), ticker_ledgers)
        update(trader)
        if sum(x -> length(x.entities), ticker_ledgers) - cur_es > 0  
            for tl in ticker_ledgers
                update(tl)
            end
            println("update")
        else
            println("no update")
        end
    end
    trader.done=false
end

struct BarUpdater <: System end

function Overseer.update(::BarUpdater, trader::SimulatedTrader)
    curt = current_time(trader)
    for (ticker, ledger) in trader.historical_ledgers
        cur_bar_id = trader.cur_bar_ids[ticker]
        
        tstampcomp = ledger[TimeStamp]

        if cur_bar_id + 1 > length(tstampcomp)
            continue
        end

        if tstampcomp[cur_bar_id + 1].t < curt
            bar_e = entity(tstampcomp, cur_bar_id + 1)
            tl = trader.ticker_ledgers[ticker]
            bar = ledger[bar_e]
            new_e              = Entity(tl, bar...)
            data_e             = singleton(tl, Dataset)
            tl[Dataset][new_e] = data_e
            ds                 = tl[Dataset].data[1]
            ds.last_e          = new_e
            ds.stop            = bar[TimeStamp].t
            
            trader.cur_bar_ids[ticker] += 1
        end
    end
end

struct OrderUpdater <: System end

function Overseer.update(::OrderUpdater, trader::SimulatedTrader)
    if length(trader[Order]) >= trader.cur_order_id
        for id in trader.cur_order_id:length(trader[Order])
            order = trader[Order][id]
            e = entity(trader[Order], id)

            if e ∈ trader[Purchase]
                order_info = trader[Purchase][e]
            else
                order_info = trader[Sale][e]
            end
            val = ticker_value(trader, order_info.ticker, order.created_at)
            val === nothing && continue

            order.filled_at = current_time(trader)
            order.updated_at = order.filled_at
            order.filled_qty = order_info.quantity
            order.status = "filled"
            order.filled_avg_price = val
        end
        trader.cur_order_id = length(trader[Order]) + 1
    end
end

function submit_order(trader::SimulatedTrader, e; quantity = e.quantity)
    return Order(UUIDs.uuid1(),
                 UUIDs.uuid1(),
                 TimeDate(now()),
                 nothing,
                 nothing,
                 nothing,
                 nothing,
                 nothing,
                 nothing,
                 0,
                 0.0,
                 "submitted")
end
