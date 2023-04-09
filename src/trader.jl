"""
    Trader(broker::AbstractBroker; strategies::Vector{Pair{String, Vector{Strategy}}}, start=current_time())

Holds all data and tasks related to trading. 
"""
mutable struct Trader{B <: AbstractBroker} <: AbstractLedger
    l              ::Ledger
    broker         ::B
    ticker_ledgers ::Dict{String, TickerLedger}
    data_task      ::Union{Task, Nothing}
    trading_task   ::Union{Task, Nothing}
    main_task      ::Union{Task, Nothing}
    stop_main      ::Bool
    stop_trading   ::Bool
    is_trading     ::Bool
    stop_data      ::Bool
    new_data_event ::Base.Event
end

Overseer.ledger(t::Trader) = t.l

function Overseer.Entity(t::Trader, args...)
    e = Entity(Overseer.ledger(t), TimeStamp(current_time(t)), args...)
    notify(t.new_data_event)
    return e
end
Overseer.Entity(t::Trader{<:HistoricalBroker}, args...) = Entity(Overseer.ledger(t), TimeStamp(current_time(t)), args...)

Base.getindex(t::Trader, id::String) = t.ticker_ledgers[id]

main_stage() = Stage(:main, [StrategyRunner(), Purchaser(), Seller(), Filler(), SnapShotter(), Timer(), DayCloser()])

function Trader(broker::AbstractBroker; strategies::Vector{Strategy} = Strategy[],
                                        start = current_time())
                                        
    l = Ledger(main_stage())
    ticker_ledgers = Dict{String, TickerLedger}()
    
    for strat in strategies
        
        for c in Overseer.requested_components(strat.stage)
            Overseer.ensure_component!(l, c)
        end
        
        Entity(l, strat)

        for ticker in strat.tickers
            
            tl = get!(ticker_ledgers, ticker, TickerLedger(ticker))
            register_strategy!(tl, strat)

            if current_position(l, ticker) === nothing
                Entity(l, Position(ticker, 0.0))
            end
            
        end

        combined = join(strat.tickers, "_")
        tl = get!(ticker_ledgers, combined, TickerLedger(combined))
        register_strategy!(tl, strat)
    end

    for ledger in values(ticker_ledgers)
        ensure_systems!(ledger)
    end
     Entity(l, Clock(start, Minute(0)))
    
    ensure_systems!(l)
    
    trader = Trader(l, broker, ticker_ledgers, nothing, nothing, nothing, false, false,false, false, Base.Event())
    
    fill_account!(trader)
   
    return trader
end

"""
    BackTester(broker)
"""
function BackTester(broker::HistoricalBroker; dt       = Minute(1),
                                              start    = current_time() - dt*1000,
                                              stop     = current_time(),
                                              cash     = 1e6,
                                              only_day = true, kwargs...)
                                              
    trader = Trader(broker; start=start, kwargs...)
    
    maxstart = start
    minstop = stop
    
    lck = ReentrantLock()
    @info "Fetching historical data"
    
    tickers =  filter(x->!occursin("_", x), collect(keys(trader.ticker_ledgers)))
    
    Threads.@threads for ticker in tickers
        b = bars(broker, ticker, start, stop, timeframe=dt, normalize=true)
        
        lock(lck) do 
            maxstart = max(timestamp(b)[1], maxstart)
            minstop  = min(timestamp(b)[end], minstop)
        end
        
        if only_day
            bars(broker)[(ticker, dt)] = only_trading(b)
        end
        
    end

    for ticker in tickers
        bars(broker)[(ticker, dt)] = to(from(bars(broker)[(ticker, dt)], maxstart), minstop)
    end

    if all(isempty, values(bars(broker)))
        error("No data to backtest")
    end
    
    c = singleton(trader, Clock)
    c.dtime = dt
    c.time = maxstart - dt
    broker.clock = c[Clock]
    broker.cash = cash
    return trader
end

"""
    current_position(trader, ticker::String)

Returns the current portfolio position for `ticker`.
Returns `nothing` if `ticker` is not found in the portfolio.
"""
function current_position(t::AbstractLedger, ticker::String)
    pos_id = findfirst(x->x.ticker == ticker, t[Position])
    pos_id === nothing && return 0.0
    return t[Position][pos_id].quantity
end

"""
    current_cash(trader)

Returns the current cash balance of the trader.
"""
current_cash(t::AbstractLedger) = singleton(t, Cash).cash

"""
    current_purchasepower(trader)

Returns the current [`PurchasePower`](@ref).
"""
current_purchasepower(t::AbstractLedger) = singleton(t, PurchasePower).cash

function Base.show(io::IO, ::MIME"text/plain", trader::Trader)
    
    positions = Matrix{Any}(undef, length(trader[Position]), 3)
    for (i, p) in enumerate(trader[Position])
        positions[i, 1] = p.ticker
        positions[i, 2] = p.quantity
        positions[i, 3] = current_price(trader.broker, p.ticker) * p.quantity
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

function ensure_systems!(l::AbstractLedger)
    stageid = findfirst(x -> x.name == :indicators, stages(l))
    if stageid !== nothing
        ind_stage = stages(l)[stageid]
    else
        ind_stage = Stage(:indicators, System[])
    end

    for T in keys(components(l))
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

    # Now insert the indicators stage in the most appropriate spot
    if stageid === nothing
        mainid = findfirst(x -> x.name == :main, stages(l))
        if mainid === nothing
            push!(l, ind_stage)
        else
            insert!(stages(l), mainid + 1, ind_stage)
        end
    end
end

"""
    reset!(trader)

Resets a [`Trader`](@ref) to the starting point. Usually only used on a [`BackTester`](@ref).
"""
function reset!(trader::Trader)
    
    for l in values(trader.ticker_ledgers)
        empty_entities!(l)
    end
    
    dt = trader[Clock][1].dtime

    start = minimum(x->timestamp(x)[1], values(bars(trader.broker))) - dt

    empty!(trader[Purchase])
    empty!(trader[Order])
    empty!(trader[Sale])
    empty!(trader[Filled])
    empty!(trader[Cash])
    empty!(trader[Clock])
    empty!(trader[TimeStamp])
    empty!(trader[PortfolioSnapshot])
    
    c = Clock(TimeDate(start), dt)
    Entity(Overseer.ledger(trader), c)
    
    for p in trader[Position]
        p.quantity = 0.0
    end
    
    if trader.broker isa HistoricalBroker
        trader.broker.clock = c
    end

    if trader.broker isa HistoricalBroker
        reset(trader.broker.send_bars)
    end
    reset(trader.new_data_event)
    
    fill_account!(trader)
    return trader
end
