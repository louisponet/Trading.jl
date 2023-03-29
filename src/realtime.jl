mutable struct RealtimeTrader{B <: Data.AbstractBroker} <: AbstractTrader
    l::Ledger
    broker::B
    ticker_ledgers::Dict{String, Data.DataLedger}
    data_task::Union{Task, Nothing}
    order_channel::Channel
    main_task::Union{Task, Nothing}
    stop_main::Bool
    stop_data::Threads.Condition
end

Overseer.ledger(t::RealtimeTrader) = t.l

main_stage() = Stage(:main, [Purchaser(), Seller(), Filler(), SnapShotter(), Timer(), in_day(clock()) ? DayCloser() : DayOpener()])
current_time(trader::RealtimeTrader) = TimeDate(now())

function RealtimeTrader(account, tickers::Vector{String}, strategies::Vector{Strategy} = Strategy[])
    stages = Stage[]
    inday = in_day(now())
    
    push!(stages, main_stage())

    for s in strategies
        if !s.only_day
            push!(stages, s.stage)
        elseif inday
            push!(stages, s.stage)
        end
    end
        
    l = Ledger(stages...)
    
    ensure_systems!(l)

    ticker_ledgers  = Dict{String, Data.DataLedger}()
    
    for ticker in tickers
        
        ticker_ledger = Data.DataLedger(ticker)
        for s in strategies
            for c in Overseer.requested_components(s.stage)
                Overseer.ensure_component!(ticker_ledger, c)
            end
        end

        ensure_systems!(ticker_ledger)
        Overseer.ensure_component!(ticker_ledger, New)
        
        ticker_ledgers[ticker] = ticker_ledger
         
    end

    for s in strategies
        Entity(l, s)
    end

    Overseer.ensure_component!(l, New)
    
    trader = RealtimeTrader(l, account, ticker_ledgers, nothing, Channel(), nothing, false, Threads.Condition())
    
    fill_account!(trader)
    
    return trader
end

function Base.show(io::IO, ::MIME"text/plain", trader::RealtimeTrader)
    
    positions = Matrix{Any}(undef, length(trader[Position]), 3)
    for (i, p) in enumerate(trader[Position])
        positions[i, 1] = p.ticker
        positions[i, 2] = p.quantity
        positions[i, 3] = Data.current_price(trader.broker, p.ticker) * p.quantity
    end
    
    println(io, "Trader\n")
    println(io, "Main task:    $(trader.main_task)")
    println(io, "Order channel: $(trader.order_channel)")
    println(io, "Data task:    $(trader.data_task)")
    println(io)
     
    positions_value = sum(positions[:, 3], init=0)
    cash            = trader[Cash][1].cash
    
    println(io, "Portfolio -- positions: $positions_value, cash: $cash, tot: $(cash + positions_value)\n")
    
    println(io, "Current positions:")
    pretty_table(io, positions, header = ["Ticker", "Quantity", "Value"])
    println(io)

    println(io, "Strategies:")
    for s in stages(trader)
        if s.name in (:main, :indicators)
            continue
        end
        print(io, "$(s.name): ", )
        for sys in s.steps
            print(io, "$sys ", )
        end
        println(io)
    end
    println(io)
    
    println(io, "Trades:")
    
    header = ["Time", "Ticker", "Side", "Quantity", "Avg Price", "Tot Price"]
    trades = Matrix{Any}(undef, length(trader[Filled]), length(header))

    for (i, e) in enumerate(@entities_in(trader, TimeStamp && Filled && Order))
        trades[i, 1] = e.filled_at
        trades[i, 2] = e.ticker
        trades[i, 3] = e in trader[Purchase] ? "buy" : "sell"
        trades[i, 4] = e.quantity
        trades[i, 5] = e.avg_price
        trades[i, 6] = e.avg_price * e.quantity
    end
    pretty_table(io, trades, header=header)

    println(io) 
    show(io, "text/plain", trader.l)
    return nothing
end 

function stop_main(trader::RealtimeTrader)
    trader.stop_main = true
    while !istaskdone(trader.main_task)
        sleep(1)
    end
    trader.stop_main = false
    return trader
end

function stop_data(trader::RealtimeTrader)
    lock(trader.stop_data)
    
    notify(trader.stop_data, true)
    unlock(trader.stop_data)
    while !istaskdone(trader.data_task)
        sleep(1)
    end
    return trader
end

function stop_trading(trader::RealtimeTrader)
    close(trader.order_channel)
end

function stop_all(trader::RealtimeTrader)
    lock(trader.stop_data)
    notify(trader.stop_data, true)
    unlock(trader.stop_data)
    trader.stop_main = true
    stop_trading(trader)
    while !istaskdone(trader.data_task) || !istaskdone(trader.main_task)
        sleep(1)
    end
    trader.stop_main = false
    return trader
end

delete_all_orders!(t::RealtimeTrader) = Data.delete_all_orders!(t.broker)

function start_trading(trader::RealtimeTrader;threaded=true, kwargs...)
    trader.order_channel = Channel(c -> Data.start_trading(c, trader.broker, trader[Order]), 100, spawn=threaded)
end

function start_data(trader::RealtimeTrader; threaded = true, kwargs...)
    pipeline = Data.DataPipeline(trader.broker)
    for (ticker, ledger) in trader.ticker_ledgers
        Data.attach!(pipeline, ledger)
    end
    if threaded
        trader.data_task = Threads.@spawn Data.start_stream(pipeline, trader.stop_data)
    else
        trader.data_task = @async Data.start_stream(pipeline, trader.stop_data)
    end
        
end

function start_main(trader::RealtimeTrader;sleep_time = 1, threaded=true, kwargs...)
    if threaded
        trader.main_task = Threads.@spawn @stoppable trader.stop_main begin
            while true
                try
                    update(trader)
                catch e
                    showerror(stdout, e, catch_backtrace())
                end
                sleep(sleep_time)
            end
        end
    else
        trader.main_task = @async @stoppable trader.stop_main begin
            while true
                try
                    update(trader)
                catch e
                    showerror(stdout, e, catch_backtrace())
                end
                sleep(sleep_time)
            end
        end
    end
end
    
function fill_account!(trader::RealtimeTrader)
    cash, positions = Data.account_details(trader.broker)


    empty!(trader[Cash])
    empty!(trader[PurchasePower])
    empty!(trader[Position])
    
    Entity(trader, Cash(cash), PurchasePower(cash))
    for p in positions
        Entity(trader, Position(p...))
    end
end

function start(trader::RealtimeTrader; kwargs...)
    if trader.main_task !== nothing && !istaskdone(trader.main_task)
        error("Trader already started")
    end

    fill_account!(trader)
    
    start_trading(trader; kwargs...)
    start_data(trader; kwargs...)
    start_main(trader; kwargs...)
    return trader
end

