"""
    Trader(broker::AbstractBroker; strategies = Strategy[])

This is the heart of the entire framework. It holds all the data, systems and references to runtime tasks.
It can be constructed with an [`AbstractBroker`](@ref) and potentially a set of [Strategies](@ref Strategies) and starting time.

Upon construction with a realtime broker, the [Portfolio](@ref) will be filled out with the account information retrieved through the
broker's API.

# Default Systems
There are a set of default systems that facilitate handling trade orders and other bookkeeping tasks.
These are [`StrategyRunner`](@ref), [`Purchaser`](@ref), [`Seller`](@ref), [`Filler`](@ref), [`SnapShotter`](@ref), [`Timer`](@ref) and [`DayCloser`](@ref).

# Runtime and Control
After calling [`start`](@ref) on the [`Trader`](@ref), the systems will run in sequence periodically in the `main_task`, performing the tasks that make everything tick.
Aside from this `main_task` there are two other tasks:
- `trading_task`: streams in portfolio and order updates
- `data_task`: streams in updates to the registered tickers and updates their [`TickerLedgers`](@ref TickerLedger)

Aside from [`start`](@ref) there are some other functions to control the runtime:
- [`stop_main`](@ref):     stops the `main_task`
- [`stop_trading`](@ref):  stops the `trading_task`
- [`stop_data`](@ref):     stops the `data_task`
- [`stop`](@ref):          combines the previous 3
- [`start_main`](@ref):    starts the `main_task`
- [`start_trading`](@ref): starts the `trading_task`
- [`start_data`](@ref):    stops the `data_task`

# AbstractLedger interface
[`Trader`](@ref) is a subtype of the `AbstractLedger` type defined in [Overseer.jl](https://github.com/louisponet/Overseer.jl), meaning that
it can be extended by adding more `Systems` and `Components` to it.
This lies at the heart of the extreme extensibility of this framework. You can think of the current implementation as one working
example of an algorithmic trader implementation, but it can be tuned and tweaked with all the freedom. 
"""
mutable struct Trader{B<:AbstractBroker} <: AbstractLedger
    l              :: Ledger
    broker         :: B
    ticker_ledgers :: Dict{String,TickerLedger}
    data_task      :: Union{Task,Nothing}
    trading_task   :: Union{Task,Nothing}
    main_task      :: Union{Task,Nothing}
    stop_main      :: Bool
    stop_trading   :: Bool
    is_trading     :: Bool
    stop_data      :: Bool
    new_data_event :: Base.Event
end

Overseer.ledger(t::Trader) = t.l

function Overseer.Entity(t::Trader, args...)
    e = Entity(Overseer.ledger(t), TimeStamp(current_time(t)), args...)
    notify(t.new_data_event)
    return e
end
function Overseer.Entity(t::Trader{<:HistoricalBroker}, args...)
    return Entity(Overseer.ledger(t), TimeStamp(current_time(t)), args...)
end

Base.getindex(t::Trader, id::String) = t.ticker_ledgers[id]

function main_stage()
    return Stage(:main,
                 [StrategyRunner(), Purchaser(), Seller(), Filler(), SnapShotter(), Timer(),
                  DayCloser()])
end

function Trader(broker::AbstractBroker; strategies::Vector{Strategy} = Strategy[],
                start = current_time())
    l = Ledger(main_stage())
    ticker_ledgers = Dict{String,TickerLedger}()

    for strat in strategies
        for c in Overseer.requested_components(strat.stage)
            ensure_component!(l, c)
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

    trader = Trader(l, broker, ticker_ledgers, nothing, nothing, nothing, false, false,
                    false, false, Base.Event())

    fill_account!(trader)

    return trader
end

"""
    current_position(trader, ticker::String)

Returns the current portfolio position for `ticker`.
Returns `nothing` if `ticker` is not found in the portfolio.
"""
function current_position(t::AbstractLedger, ticker::String)
    pos_id = findfirst(x -> x.ticker == ticker, t[Position])
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

    positions_value = sum(positions[:, 3]; init = 0)
    cash            = trader[Cash][1].cash

    println(io,
            "Portfolio -- positions: $positions_value, cash: $cash, tot: $(cash + positions_value)\n")

    println(io, "Current positions:")
    pretty_table(io, positions; header = ["Ticker", "Quantity", "Value"])
    println(io)

    println(io, "Strategies:")
    for s in stages(trader)
        if s.name in (:main, :indicators)
            continue
        end
        print(io, "$(s.name): ")
        for sys in s.steps
            print(io, "$sys ")
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
    pretty_table(io, trades; header = header)

    println(io)
    return nothing
end

"""
    BackTester(broker::HistoricalBroker;
               dt = Minute(1),
               start    = current_time() - dt*1000,
               stop     = current_time(),
               cash     = 1e6,
               only_day = true)

This creates a [`Trader`](@ref) and adds some additional functionality to perform a backtest. Since behind the scenes it really is just
a tweaked [`Trader`](@ref), backtesting mimics the true behavior of the algorithm/strategy if it were running in realtime.
By using a [`HistoricalBroker`](@ref), the main difference is that the datastreams are replaced with [`historical data`](@ref historical_data),
as are the behavior of [`current_price`](@ref) and [`current_time`](@ref).

See [`reset!`](@ref) to be able to rerun a [`BackTester`](@ref)

# Keyword arguments
- `dt`: the timestep or granularity of the data. This will also be the tickrate of the `main_task` of the [`Trader`](@ref).
- `start`: the starting time of the backtest 
- `stop`: the stopping time of the backtest
- `cash`: the starting cash
- `only_day`: whether the backtest should only be ran during the day. This mainly improves performance.
"""
function BackTester(broker::HistoricalBroker;
                    dt       = Minute(1),
                    start    = current_time() - dt * 1000,
                    stop     = current_time(),
                    cash     = 1e6,
                    only_day = true, kwargs...)
    trader = Trader(broker; start = start, kwargs...)

    maxstart = start
    minstop = stop

    lck = ReentrantLock()
    @info "Fetching historical data"

    tickers = filter(x -> !occursin("_", x), collect(keys(trader.ticker_ledgers)))

    Threads.@threads for ticker in tickers
        b = bars(broker, ticker, start, stop; timeframe = dt, normalize = true)

        lock(lck) do
            maxstart = max(timestamp(b)[1], maxstart)
            return minstop = min(timestamp(b)[end], minstop)
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

    c            = singleton(trader, Clock)
    c.dtime      = dt
    c.time       = maxstart - dt
    broker.clock = c[Clock]
    broker.cash  = cash
    return trader
end

function ensure_systems!(l::AbstractLedger)
    stageid = findfirst(x -> x.name == :indicators, stages(l))
    if stageid !== nothing
        ind_stage = stages(l)[stageid]
    else
        ind_stage = Stage(:indicators, System[])
    end

    n_steps = 0
    n_components = 0
    while length(ind_stage.steps) != n_steps || n_components != length(keys(components(l)))
        n_steps      = length(ind_stage.steps)
        n_components = length(keys(components(l)))

        for T in keys(components(l))
            eT = eltype(T)
            if !(eT <: Number)
                ensure_component!(l, eltype(T))
            end

            if T <: SMA && SMACalculator() ∉ ind_stage
                push!(ind_stage, SMACalculator())
            elseif T <: MovingStdDev && MovingStdDevCalculator() ∉ ind_stage
                push!(ind_stage, MovingStdDevCalculator())
            elseif T <: EMA && EMACalculator() ∉ ind_stage
                push!(ind_stage, EMACalculator())
            elseif T <: UpDown && UpDownSeparator() ∉ ind_stage
                push!(ind_stage, UpDownSeparator())
            elseif T <: Difference && DifferenceCalculator() ∉ ind_stage
                push!(ind_stage, DifferenceCalculator())
            elseif T <: RelativeDifference && RelativeDifferenceCalculator() ∉ ind_stage
                push!(ind_stage, RelativeDifferenceCalculator())

            elseif T <: Sharpe && SharpeCalculator() ∉ ind_stage
                horizon = T.parameters[1]
                comp_T  = T.parameters[2]

                sma_T = SMA{horizon,comp_T}
                std_T = MovingStdDev{horizon,comp_T}
                ensure_component!(l, sma_T)
                ensure_component!(l, std_T)

                push!(ind_stage, sharpe_systems()...)

            elseif T <: LogVal && LogValCalculator() ∉ ind_stage
                push!(ind_stage, LogValCalculator())

            elseif T <: RSI && RSICalculator() ∉ ind_stage
                ema_T = EMA{T.parameters[1],UpDown{Difference{T.parameters[2]}}}
                ensure_component!(l, ema_T)
                push!(ind_stage, rsi_systems()...)

            elseif T <: Bollinger && BollingerCalculator() ∉ ind_stage
                sma_T = SMA{T.parameters...}
                ind_T = T.parameters[2]
                ensure_component!(l, sma_T)
                ensure_component!(l, ind_T)

                push!(ind_stage, bollinger_systems()...)
            end
        end
        unique!(ind_stage.steps)
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

    start = minimum(x -> timestamp(x)[1], values(bars(trader.broker))) - dt

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

function returns(t::Trader, period::Function=day)
    ensure_component!(t, RelativeDifference{PortfolioSnapshot})
    update(RelativeDifferenceCalculator(), t)

    ensure_component!(t, Difference{PortfolioSnapshot})
    update(DifferenceCalculator(), t)

    t_relret = split(TimeArray(t[RelativeDifference{PortfolioSnapshot}], t[TimeStamp]), period)
    t_ret    = split(TimeArray(t[Difference{PortfolioSnapshot}], t[TimeStamp]), period)

    ret = sum(t_ret[1])
    for r in t_ret[2:end]
        ret = vcat(ret, sum(r))
    end
         
    relret = prod(x -> 1 + x, values(t_relret[1])).-1
    tstamps = DateTime[timestamp(t_relret[1])[end]]
    for r in t_relret[2:end]
        relret = vcat(relret, prod(x -> 1 + x, values(r)).-1)
        push!(tstamps, timestamp(r)[end])
    end
    out = merge(rename(ret, [:absolute]), TimeArray(tstamps, relret, [:relative]), method=:outer) 
    return out[findall(out[:relative] .!= 0 .&& out[:absolute] .!= 0)]
end

"""
    sharpe(t::Trader, args...; risk_free = 0.0)
    
Calculates the Sharpe ratio of a [`Trader`](@ref).
The Sharpe ratio is a measure of risk-adjusted return, and is defined as the average excess return earned over the risk-free
rate per unit of volatility or total risk (i.e. the standard deviation of the returns).

`risk_free`: the risk-free rate to use as a baseline for the Sharpe ratio calculation.
             The risk-free rate represents the return an investor can earn from a risk-free investment, such as a Treasury bill.
             The default value is 0.0, representing a risk-free rate of 0%.
"""
function sharpe(t::Trader, args...; risk_free = 0.0)
    relrets = returns(t, args...)[:relative]
    return values(mean(relrets .- risk_free)./std(relrets))[1]
end

"""
    downside_risk(t::Trader, args...; required_return=0.0)
    
Calculates the downside risk of a [`Trader`](@ref). Downside risk is a measure of the potential loss of an investment,
and is defined as the standard deviation of returns below a certain threshold: `required_return`.
"""
function downside_risk(t::Trader, args...; required_return=0.0)
    adjusted_returns = returns(t, args...)[:relative].-required_return
    map(adjusted_returns) do t, x
        return t, x > 0 ? 0 : x
    end
    return values(sqrt.(mean(adjusted_returns.^2)))[1]
end

"""
    value_at_risk(t::Trader, args...; cutoff = 0.05)

Calculates the value at risk (VaR) of a [`Trader`](@ref).
Value at risk is a measure of the potential loss of an investment over a certain time horizon,
and is defined as the maximum loss expected at a given confidence level.

`cutoff`: the confidence level at which to calculate value at risk. The confidence level represents
          the probability of the maximum loss being less than or equal to the value at risk.
          The default value is 0.05, representing a 5% confidence level.
"""    
function value_at_risk(t::Trader, args...; cutoff = 0.05)
    rets = returns(t)[:relative]
    quantile(values(rets), cutoff)
end

"""
Calculates the maximum drawdown of a [`Trader`](@ref) object.
Maximum drawdown is a measure of the largest loss experienced by an investment over a certain time period,
and is defined as the peak-to-trough decline in portfolio value.
"""
function maximum_drawdown(t::Trader)
    portfolio = t[PortfolioSnapshot]
    
    curmax = curmin = portfolio[1].value
    curdrawdown = 0
    
    for i = 2:length(portfolio)
        v = portfolio[i].value
        if v > curmax
            curmax = v
            curmin = v
        elseif v < curmin
            curmin = v
            curdrawdown = max(curdrawdown, (curmax - v)/curmax)
        end
    end
    return curdrawdown
end
    
