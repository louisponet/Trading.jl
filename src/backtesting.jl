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
