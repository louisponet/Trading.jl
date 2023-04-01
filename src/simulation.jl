mutable struct SimulatedTrader <: AbstractTrader
    trader::RealtimeTrader
end

Overseer.ledger(trader::SimulatedTrader) = trader.trader.l

function SimulatedTrader(account, tickers::Vector{String}, strategies; dt=Minute(1), start=now() - dt*1000, stop = now(), cash = 1_000_000, only_day=true)
    trader = RealtimeTrader(account, tickers, strategies, start=start)

    @info "Fetching historical data"
    Threads.@threads for ticker in tickers
        b = Data.bars(account, ticker, start, stop, timeframe=dt)
        if only_day
            account.bar_data[(ticker, dt)] = b[findall(x->in_day(x), timestamp(b))]
        end
    end

    c = singleton(trader, Clock)
    c.dtime = dt
    account.clock = c[Clock]
    
    return SimulatedTrader(trader)
end

function reset!(trader::SimulatedTrader)
    
    for (ticker, l) in trader.trader.ticker_ledgers
        
        empty_entities!(l)
        
    end
    dt = trader[Clock][1].dtime

    start = minimum(x->timestamp(x)[1], values(trader.trader.broker.bar_data))

    empty_entities!(trader)
    Entity(trader, Clock(TimeDate(start), dt)) 
    fill_account!(trader)
    return trader
end

current_time(trader::SimulatedTrader) = trader[Clock][1].time

function start(trader::SimulatedTrader; sleep_time = 0.001)

    last = trader[Clock][1].time
    for (ticker, data) in trader.trader.broker.bar_data
        tstop = timestamp(data)[end]
        last = max(tstop, last)
    end

    start(trader.trader; sleep_time=0.0, threaded=true)
    p = ProgressMeter.ProgressUnknown("Simulating..."; spinner = true) 
    while current_time(trader) < last
        showvalues = isempty(trader[PortfolioSnapshot]) ?
                     [(:t, trader[Clock][1].time), (:value, trader[Cash][1].cash)] :
                     [(:t, trader[Clock][1].time), (:value, trader[PortfolioSnapshot][end].value)]
        ProgressMeter.next!(p; spinner = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏", showvalues = showvalues)
        sleep(1)
    end
    stop_all(trader.trader)
    ProgressMeter.finish!(p)
end
