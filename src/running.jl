function start(trader::Trader; kwargs...)
    if trader.main_task !== nothing && !istaskdone(trader.main_task)
        error("Trader already started")
    end

    fill_account!(trader)
    
    start_trading(trader)
    start_data(trader; kwargs...)
    start_main(trader; kwargs...)
    return trader
end

function start(trader::Trader{<:HistoricalBroker})

    last = trader[Clock][1].time
    for (ticker, data) in bars(trader.broker)
        tstop = timestamp(data)[end]
        last = max(tstop, last)
    end

    start(trader; sleep_time=0.0)
    p = ProgressMeter.ProgressUnknown("Simulating..."; spinner = true)
    
    while current_time(trader) < last
        showvalues = isempty(trader[PortfolioSnapshot]) ?
                     [(:t, trader[Clock][1].time), (:value, trader[Cash][1].cash)] :
                     [(:t, trader[Clock][1].time), (:value, trader[PortfolioSnapshot][end].value)]
                     
        ProgressMeter.next!(p; spinner = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏", showvalues = showvalues)
        sleep(1)
    end
    
    stop_all(trader)
    
    ProgressMeter.finish!(p)
    
    return trader
end

function start_data(trader::Trader;  kwargs...)
    trader.data_task = Threads.@spawn @stoppable trader.stop_data bar_stream(trader.broker) do stream
        for (ticker, q) in trader.ticker_ledgers
            register!(stream, ticker)
        end
        while !trader.stop_data && !isclosed(stream)
            try
                bars = receive(stream)
                updated_tickers = Set{String}()
                for (ticker, tbar) in bars
                    time, bar  = tbar
                    Entity(trader.ticker_ledgers[ticker], TimeStamp(time), Open(bar[1]), High(bar[2]), Low(bar[3]), Close(bar[4]), Volume(round(Int,bar[5])))
                    push!(updated_tickers, ticker)
                end
                
                @sync for ticker in updated_tickers
                    Threads.@spawn begin
                        Overseer.update(trader.ticker_ledgers[ticker])
                    end
                end
                lock(trader.new_data_event) do 
                    notify(trader.new_data_event)
                end
                    
            catch e
                if !(e isa InvalidStateException) && !(e isa EOFError) && !(e isa InterruptException)
                    showerror(stdout, e, catch_backtrace())
                end
            end
        end
        @info "Closed Data Stream"
    end
end

function start_main(trader::Trader;sleep_time = 1, kwargs...)
    trader.main_task = Threads.@spawn @stoppable trader.stop_main begin
        while !trader.stop_main
            try
                update(trader)
            catch e
                showerror(stdout, e, catch_backtrace())
            end
            sleep(sleep_time)
        end
    end
end
    
function start_trading(trader::Trader)
    order_comp = trader[Order]
    broker = trader.broker
    trader.trading_task = Threads.@spawn @stoppable trader.stop_trading order_stream(broker) do stream
        while true
            try
                received = receive(stream)
                if received === nothing
                    continue
                end
                
                uid = received.id

                tries = 0
                id = nothing
                #TODO dangerous when an order would come from somewhere else
                while id === nothing && tries < 100
                    id = findlast(x->x.id == uid, order_comp.data)
                    tries += 1
                end
                
                if id === nothing
                    Entity(trader, received)
                else
                    order_comp[id] = received
                end
            catch e
                if !(e isa InvalidStateException) && !(e isa EOFError) && !(e isa InterruptException)
                    showerror(stdout, e, catch_backtrace())
                else
                    break
                end
            end
                    
        end
        @info "Closed Trading Stream"
    end
end

function stop_main(trader::Trader)
    trader.stop_main = true
    while !istaskdone(trader.main_task)
        sleep(1)
    end
    trader.stop_main = false
    if trader.broker isa HistoricalBroker
        notify(trader.broker.send_bars)
    end
    return trader
end

function stop_data(trader::Trader)
    trader.stop_data = true
    while !istaskdone(trader.data_task)
        sleep(1)
    end
    trader.stop_data = false
    return trader
end

function stop_trading(trader::Trader)
    trader.stop_trading=true
    while !istaskdone(trader.trading_task)
        sleep(1)
    end
    trader.stop_trading=false
    return trader
end

function stop_all(trader::Trader)
    t1 = @async stop_data(trader)
    t2 = @async stop_trading(trader)
    t3 = @async stop_main(trader)
    fetch(t1), fetch(t2), fetch(t3)
    return trader
end

function Overseer.update(trader::Trader)
    singleton(trader, PurchasePower).cash = singleton(trader, Cash).cash 

    for s in stages(trader)
        update(s, trader)
    end
end 

function Overseer.update(trader::Trader{<:HistoricalBroker})
    singleton(trader, PurchasePower).cash = singleton(trader, Cash).cash
    
    notify(trader.broker.send_bars)
    
    lock(trader.new_data_event) do 
        wait(trader.new_data_event)
    end
    
    for s in stages(trader)
        update(s, trader)
    end
end 

