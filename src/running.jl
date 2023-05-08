"""
    start(trader::Trader; kwargs...)
    
Starts all the tasks of a [`Trader`](@ref) or [`BackTester`](@ref).
The `kwargs` are passed to each of the [`start_main`](@ref), [`start_trading`](@ref) and [`start_data`](@ref) functions.
"""
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
    for (asset, data) in bars(trader.broker)
        tstop = timestamp(data)[end]
        last = max(tstop, last)
    end

    start(trader; sleep_time = 0.0, interval=trader[Clock][1].dtime)
    p = ProgressMeter.ProgressUnknown("Simulating..."; spinner = true)

    while current_time(trader) < last
        showvalues = isempty(trader[PortfolioSnapshot]) ?
                     [(:t, trader[Clock][1].time), (:value, trader[Cash][1].cash)] :
                     [(:t, trader[Clock][1].time),
                      (:value, trader[PortfolioSnapshot][end].value)]

        ProgressMeter.next!(p; spinner = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏", showvalues = showvalues)
        sleep(1)
    end

    stop(trader)

    ProgressMeter.finish!(p)

    return trader
end

function data_task(trader, ::Type{T}; interval=Minute(1), kwargs...) where {T}
    data_stream(trader.broker, T) do stream
        for (asset, q) in trader.asset_ledgers
            if occursin("_", asset.ticker)
                continue
            end
            
            if asset isa T
                register!(stream, asset)
            end
            
        end
        while !trader.stop_data

            try
                data = receive(stream)
                
                updated_tickers = Set{String}()
                
                for (ticker, tbar) in data.bars
                    time, bar = tbar
                    
                    new_bar!(trader.asset_ledgers[T(ticker)],
                             TimeStamp(time),
                             Open(bar[1]),
                             High(bar[2]),
                             Low(bar[3]),
                             Close(bar[4]),
                             Volume(round(Int, bar[5]));
                             interval = interval)
                             
                    push!(updated_tickers, ticker)
                end
                
                for (ticker, q) in data.quotes
                    l = trader.asset_ledgers[T(ticker)]
                    l.latest_quote = (TimeStamp(first(q)), q[2], q[3])
                    push!(updated_tickers, ticker)
                end
                
                for (ticker, q) in data.trades
                    Entity(trader.asset_ledgers[T(ticker)],  TimeStamp(first(q)), last(q))
                    push!(updated_tickers, ticker)
                end

                @sync for ticker in updated_tickers
                    Threads.@spawn begin
                        Overseer.update(trader.asset_ledgers[T(ticker)])
                    end
                end
                notify(trader.new_data_event)

            catch e
                if !(e isa InvalidStateException) && !(e isa EOFError) &&
                   !(e isa InterruptException) && !(e == HTTP.WebSockets.WebSocketError(HTTP.WebSockets.CloseFrameBody(1006, "WebSocket connection is closed")))
                    showerror(stdout, e, catch_backtrace())
                else
                    @info "Issue with $T data stream"
                    return
                end
            end
        end
        @info "Closed Data Stream"
    end
    
end

"""
    start_data(trader; interval = Minute(1))

Starts the `trader.data_tasks`.
It opens a [`DataStream`](@ref) for each [`Asset`](@ref) Class, and registers the [`AssetLedgers`](@ref AssetLedger) to it, in order to [`receive`](@ref) bar updates.

`interval`: signifies the desired interval of bar updates. If a bar for a given asset arrives after more than `interval`,
            bars will be interpolated between the last and new bar so the time interval between adjacent bars is always `interval`.
"""
function start_data(trader::Trader; interval = Minute(1), kwargs...)
    for T in unique(map(x->typeof(x.asset), values(trader.asset_ledgers)))
        if !haskey(trader.data_tasks, T) || istaskdone(trader.data_tasks[T])
            trader.data_tasks[T] = Threads.@spawn @stoppable trader.stop_data data_task(trader, T; interval=interval, kwargs...)
        end
    end
end

"""
    start_main(trader::Trader; sleep_time = 1, kwargs...)

Starts the `trader.main_task`. This periodically executes the core systems of the [`Trader`](@ref), with at least `sleep_time` between executions.
"""
function start_main(trader::Trader; sleep_time = 1, kwargs...)
    return trader.main_task = Threads.@spawn @stoppable trader.stop_main begin
        while !trader.stop_main
            curt = time()
            
            if istaskdone(trader.trading_task)
                start_trading(trader; kwargs...)
            end

            start_data(trader; kwargs...)
            
            try
                update(trader)
            catch e
                if !(e isa InterruptException)
                    showerror(stdout, e, catch_backtrace())
                else
                    rethrow()
                end
            end
            if !(trader.broker isa HistoricalBroker)
                to_sleep = clamp(time() - curt, 0, sleep_time)
                sleep(to_sleep)
            end
        end
    end
end

"""
    start_trading(trader)

Starts the trading task. This opens a [`TradingStream`](@ref) to `trader.broker` that listens to portfolio and order updates .
"""
function start_trading(trader::Trader)
    order_comp = trader[Order]
    broker = trader.broker
    return trader.trading_task = Threads.@spawn @stoppable trader.stop_trading trading_stream(broker) do stream
        trader.is_trading = true
        
        while !trader.stop_trading
            
            if isclosed(stream)
                @info "Trading stream closed, restarting"
                return 
            end
            
            try
                received = receive(stream)
                if received === nothing
                    continue
                end

                uid = received.id

                tries = 0
                #TODO dangerous when an order would come from somewhere else
                id = findlast(x -> x.id == uid, order_comp.data)
                while id === nothing && tries < 100
                    id = findlast(x -> x.id == uid, order_comp.data)
                    sleep(0.005)
                    tries += 1
                end

                if id === nothing
                    Entity(trader, received)
                else
                    received.asset = order_comp[id].asset
                    order_comp[id] = received
                end
                
            catch e
                if !(e isa InvalidStateException) && !(e isa EOFError) &&
                   !(e isa InterruptException)
                    # showerror(stdout, e, catch_backtrace())
                else
                    break
                end
            end
        end
        trader.is_trading = false
        @info "Closed Trading Stream"
    end
end

"""
    stop_main(trader)

Stops `trader.main_task`.
"""
function stop_main(trader::Trader)
    trader.stop_main = true
    while !istaskdone(trader.main_task)
        sleep(1)
    end
    trader.stop_main = false
    return trader
end

"""
    stop_data(trader)

Stops `trader.data_tasks`.
"""
function stop_data(trader::Trader)
    trader.stop_data = true
    while !all(x -> istaskdone(x), values(trader.data_tasks))
        sleep(1)
    end
    trader.stop_data = false
    return trader
end

"""
    stop_trading(trader)

Stops `trader.trading_task`.
"""
function stop_trading(trader::Trader)
    trader.stop_trading = true
    while !istaskdone(trader.trading_task)
        sleep(1)
    end
    trader.stop_trading = false
    return trader
end

"""
    stop(trader)

Stops all tasks.
"""
function stop(trader::Trader)
    stop_main(trader)
    t1 = @async stop_data(trader)
    t2 = @async stop_trading(trader)
    fetch(t1), fetch(t2)
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

    wait(trader.new_data_event)
    reset(trader.new_data_event)

    for s in stages(trader)
        update(s, trader)
    end
end
