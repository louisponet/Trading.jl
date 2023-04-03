mutable struct Trader{B <: Data.AbstractBroker} <: AbstractLedger
    l::Ledger
    broker::B
    ticker_ledgers::Dict{String, Data.DataLedger}
    data_task::Union{Task, Nothing}
    trading_task::Union{Task, Nothing}
    main_task::Union{Task, Nothing}
    stop_main::Bool
    stop_trading::Bool
    stop_data::Threads.Condition
    new_data_event::Threads.Condition
end

Overseer.ledger(t::Trader) = t.l

main_stage(t=clock()) = Stage(:main, [Purchaser(), Seller(), Filler(), SnapShotter(), Timer(), DayCloser()])
current_time(trader::Trader) = isempty(trader[Clock]) ? clock() : trader[Clock][1].time

function Trader(account, tickers::Vector{String}, strategies::Vector{Strategy} = Strategy[];start=clock())
    stages = Stage[]
    inday = in_day(start)
    
    push!(stages, main_stage(start))

    for s in strategies
        push!(stages, s.stage)
    end
        
    l = Ledger(stages...)
    Entity(l, Clock(start, Minute(0)))
    
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
        Entity(l, Position(ticker, 0.0)) 
    end

    for s in strategies
        Entity(l, s)
    end

    Overseer.ensure_component!(l, New)
    
    trader = Trader(l, account, ticker_ledgers, nothing, nothing, nothing, false, false, Threads.Condition(), Threads.Condition())
    
    fill_account!(trader)
    
    return trader
end

function Base.show(io::IO, ::MIME"text/plain", trader::Trader)
    
    positions = Matrix{Any}(undef, length(trader[Position]), 3)
    for (i, p) in enumerate(trader[Position])
        positions[i, 1] = p.ticker
        positions[i, 2] = p.quantity
        positions[i, 3] = Data.current_price(trader.broker, p.ticker) * p.quantity
    end
    
    println(io, "Trader\n")
    println(io, "Main task:    $(trader.main_task)")
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

function stop_main(trader::Trader)
    trader.stop_main = true
    while !istaskdone(trader.main_task)
        sleep(1)
    end
    trader.stop_main = false
    if trader.broker isa Data.HistoricalBroker
        notify(trader.broker.send_bars)
    end
    return trader
end

function stop_data(trader::Trader)
    lock(trader.stop_data) do
        notify(trader.stop_data, true)
    end
    
    while !istaskdone(trader.data_task)
        sleep(1)
    end
    return trader
end

function stop_trading(trader::Trader)
    trader.stop_trading=true
    while !istaskdone(trader.trading_task)
        sleep(1)
    end
    trader.stop_trading=false
end

function stop_all(trader::Trader)
    t1 = @async stop_data(trader)
    t2 = @async stop_trading(trader)
    t3 = @async stop_main(trader)
    fetch(t1), fetch(t2), fetch(t3)
end

delete_all_orders!(t::Trader) = Data.delete_all_orders!(t.broker)

function start_trading(trader::Trader)
    order_comp = trader[Order]
    broker = trader.broker
    trader.trading_task = Threads.@spawn @stoppable trader.stop_trading Data.trading_link(broker) do link
        while true
            try
                received = receive(link)
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
                end
                break
            end
                    
        end
        @info "Closed Trading Stream"
    end
end

function start_data(trader::Trader;  kwargs...)
    pipeline = Data.DataPipeline(trader.broker)
    for (ticker, ledger) in trader.ticker_ledgers
        Data.attach!(pipeline, ledger)
    end
    trader.data_task = Threads.@spawn Data.start_stream(pipeline, trader.stop_data, trader.new_data_event)
        
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
    
function fill_account!(trader::Trader)
    cash, positions = Data.account_details(trader.broker)

    empty!(trader[Cash])
    empty!(trader[PurchasePower])
    
    Entity(trader, Cash(cash), PurchasePower(cash))
    for p in positions
        id = findfirst(x->x.ticker == p[1], trader[Position])
        if id === nothing 
            Entity(trader, Position(p...))
        else
            trader[Position][id].quantity = p[2]
        end
    end
end

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

function start(trader::Trader{<:Data.HistoricalBroker})

    last = trader[Clock][1].time
    for (ticker, data) in trader.broker.bar_data
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

function Overseer.update(trader::Trader)
    singleton(trader, PurchasePower).cash = singleton(trader, Cash).cash 

    for s in stages(trader)
        update(s, trader)
    end
end 

function Overseer.update(trader::Trader{<:Data.HistoricalBroker})
    singleton(trader, PurchasePower).cash = singleton(trader, Cash).cash 
    notify(trader.broker.send_bars)
    
    lock(trader.new_data_event) do 
        wait(trader.new_data_event)
    end
    for s in stages(trader)
        update(s, trader)
    end
end 

Entity(t::Trader, args...) = Entity(Overseer.ledger(t), TimeStamp(t), args...)

in_day(l::Trader) = in_day(current_time(l))

function current_position(t::AbstractLedger, ticker::String)
    pos_id = findfirst(x->x.ticker == ticker, t[Position])
    pos_id === nothing && return 0.0
    return t[Position][pos_id].quantity
end

Data.current_price(t::Trader, ticker) = Data.current_price(t.broker, ticker)

function Data.submit_order(t::Trader, e)
    t[e] = Data.submit_order(t.broker, e)
end

TimeStamp(l::Trader) = TimeStamp(current_time(l))

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

function setup_simulation(account::Data.HistoricalBroker, tickers::Vector{String}, strategies; dt=Minute(1), start=now() - dt*1000, stop = now(), cash = 1_000_000, only_day=true)
    trader = Trader(account, tickers, strategies, start=start)
    maxstart = start
    minstop = stop
    lck = ReentrantLock()
    @info "Fetching historical data"
    Threads.@threads for ticker in tickers
        b = Data.bars(account, ticker, start, stop, timeframe=dt, normalize=true)
        lock(lck) do 
            maxstart = max(timestamp(b)[1], maxstart)
            minstop  = min(timestamp(b)[end], minstop)
        end
        if only_day
            account.bar_data[(ticker, dt)] = Data.only_trading(b)
        end
    end

    for ticker in tickers
        account.bar_data[(ticker, dt)] = to(from(account.bar_data[(ticker, dt)], maxstart), minstop)
    end
    
    c = singleton(trader, Clock)
    c.dtime = dt
    account.clock = c[Clock]
    
    return trader
end

function reset!(trader::Trader)
    for (ticker, l) in trader.ticker_ledgers
        empty_entities!(l)
    end
    dt = trader[Clock][1].dtime

    start = minimum(x->timestamp(x)[1], values(trader.broker.bar_data))

    empty!(trader[Purchase])
    empty!(trader[Order])
    empty!(trader[Sale])
    empty!(trader[Filled])
    empty!(trader[Cash])
    empty!(trader[Clock])
    empty!(trader[TimeStamp])
    empty!(trader[PortfolioSnapshot])
    
    c = Clock(TimeDate(start), dt)
    Entity(trader, c)
    if trader.broker isa Data.HistoricalBroker
        trader.broker.clock = c
    end
    fill_account!(trader)
    return trader
end

function timestamps(l::AbstractLedger)
    unique(map(x->DateTime(x.t), l[Trading.TimeStamp]))
end

function TimeSeries.TimeArray(l::AbstractLedger, cols=keys(components(l)))

    out = nothing

    tcomp = l[TimeStamp]
    for T in cols

        if T == TimeStamp
            continue
        end
        
        if !hasmethod(value, (T,))
            continue
        end
        
        T_comp = l[T]
        es_to_store = filter(e -> e in tcomp, @entities_in(l[T]))
        if length(es_to_store) < 2
            continue
        end
        timestamps = map(x->DateTime(tcomp[x].t), es_to_store)

        colname = replace("$(T)", "Trading." => "")
        
        t = TimeArray(timestamps, map(x-> value(l[T][x]), es_to_store), String[colname])
        out = out === nothing ? t : merge(out, t, method=:outer)
    end

    if l isa Trader
        for (ticker, ledger) in l.ticker_ledgers
            ta = TimeArray(ledger)

            colnames(ta) .= Symbol.((ticker * "_",) .* string.(colnames(ta)))
            
            out = merge(out, ta, method=:outer)
        end
    end
    
    return out
end

function TimeSeries.TimeArray(ticker, timeframe, start, stop, account)
    l = Ledger(Stage(:core, [Trading.DatasetAdder()]))
    Entity(l, account, Trading.Dataset(ticker, timeframe, start, stop))
    Trading.update(l)
    return TimeArray(l)
end
