mutable struct RealtimeTrader{B <: Data.AbstractBroker} <: AbstractTrader
    l::Ledger
    broker::B
    ticker_ledgers::Dict{String, Data.DataLedger}
    data_task::Union{Task, Nothing}
    trading_task::Union{Task, Nothing}
    loop::Union{Task, Nothing}
    stop_main::Bool
    stop_data::Bool
    stop_trading::Bool
end

Overseer.ledger(t::RealtimeTrader) = t.l

in_session_stage(::Type{RealtimeTrader}) = Stage(:main, [Purchaser(), Seller(), Filler(), SnapShotter(), Timer(), DayCloser()])
end_of_day_stage(::Type{RealtimeTrader})  = Stage(:main, [Seller(), Filler(), SnapShotter(), Timer(), DayOpener()])
current_time(trader::RealtimeTrader) = TimeDate(now())

function RealtimeTrader(account, tickers::Vector{String}, strategies::Vector{Strategy} = Strategy[])
    stages = Stage[]
    inday = in_day(now())
    
    if inday 
        push!(stages, in_session_stage(RealtimeTrader))
    else
        push!(stages, end_of_day_stage(RealtimeTrader))
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
    
    trader = RealtimeTrader(l, account, ticker_ledgers, nothing, nothing, nothing, false, false, false)
    
    fill_account!(trader)
    
    return trader
end

function Base.show(io::IO, ::MIME"text/plain", trader::RealtimeTrader)
    
    positions = Matrix{Any}(undef, length(trader[Position]), 3)
    for (i, p) in enumerate(trader[Position])
        positions[i, 1] = p.ticker
        positions[i, 2] = p.quantity
        positions[i, 3] = current_price(trader, p.ticker) * p.quantity
    end
    
    println(io, "Trader\n")
    println(io, "Main task:    $(trader.loop)")
    println(io, "Trading task: $(trader.trading_task)")
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
    while !istaskdone(trader.loop)
        sleep(1)
    end
    trader.stop_main = false
    return trader
end

function stop_data(trader::RealtimeTrader)
    trader.stop_data = true
    while !istaskdone(trader.data_task)
        sleep(1)
    end
    trader.stop_data = false
    return trader
end

function stop_trading(trader::RealtimeTrader)
    trader.stop_trading = true
    while !istaskdone(trader.trading_task)
        sleep(1)
    end
    trader.stop_trading = false
    return trader
end

function stop_all(trader::RealtimeTrader)
    trader.stop_trading = true
    trader.stop_data = true
    trader.stop_main = true
    while !istaskdone(trader.trading_task) || !istaskdone(trader.data_task) || !istaskdone(trader.trading_task)
        sleep(1)
    end
    trader.stop_trading = false
    trader.stop_data = false
    trader.stop_main = false
    return trader
end

function delete_all_orders!(t::RealtimeTrader)
    HTTP.delete(URI(PAPER_TRADING_URL, path="/v2/orders"), Data.header(t.broker))
end

function start_trading(trader::RealtimeTrader)
    trader.trading_task = Threads.@spawn @stoppable trader.stop_trading begin
        HTTP.open(TRADING_STREAM_PAPER) do ws

            if !authenticate_trading(ws, trader)
                error("couldn't authenticate")
            end
            @info "Authenticated trading"
            send(ws, JSON3.write(Dict("action" => "listen",
                                      "data"  => Dict("streams" => ["trade_updates"]))))
            while true
                msg = JSON3.read(receive(ws))
                if msg[:stream] == "trade_updates" && msg[:data][:event] == "fill"
                    order_update!(trader, msg[:data][:order])
                end
            end
        end
    end
end

function start_data(trader::RealtimeTrader)
    pipeline = Data.DataPipeline(Data.RealtimeDataSource(trader.broker))
    for (ticker, ledger) in trader.ticker_ledgers
        Data.attach!(pipeline, ledger)
    end
    trader.data_task = Threads.@spawn @stoppable trader.stop_data Data.start_stream(pipeline)
end

function start_main(trader::RealtimeTrader)
    trader.loop = Threads.@spawn @stoppable trader.stop_main begin
        while true
            try
                if !trader.stop_data && (trader.data_task === nothing || istaskdone(trader.data_task) || istaskfailed(trader.data_task))
                    start_data(trader)
                end
                if !trader.stop_trading && (trader.trading_task === nothing || istaskdone(trader.trading_task) || istaskfailed(trader.trading_task))
                    start_trading(trader)
                end
                update(trader)
            catch e
                log_error(e)
            end
            sleep(1)
        end
    end
end
    
function fill_account!(trader::RealtimeTrader)
    cash, positions = Data.account_details(trader.broker)
    Entity(trader, Cash(cash), PurchasePower(cash))
    for p in positions
        Entity(trader, Position(p...))
    end
end

function start(trader::RealtimeTrader)
    if trader.loop !== nothing && !istaskdone(trader.loop)
        error("Trader already started")
    end

    fill_account!(trader)
    
    start_trading(trader)
    start_data(trader)
    start_main(trader)
    return trader
end

function order_update!(trader::RealtimeTrader, order_msg)
    uid = UUID(order_msg[:id])
   
    id = nothing
    while id === nothing
        id = findfirst(x->x.id == uid, trader[Order].data)
    end

    order = trader[Order].data[id]

    order.status           = order_msg[:status]
    order.updated_at       = TimeDate(order_msg[:updated_at][1:end-1])
    order.filled_at        = TimeDate(order_msg[:filled_at][1:end-1])
    order.submitted_at     = TimeDate(order_msg[:submitted_at][1:end-1])
    order.filled_qty       = parse(Int, order_msg[:filled_qty])
    order.filled_avg_price = parse(Float64, order_msg[:filled_avg_price])
end

current_price(trader::RealtimeTrader, ticker) = trader.ticker_ledgers[ticker][Close][end].v

timestamp(trader::RealtimeTrader) = TimeStamp()
