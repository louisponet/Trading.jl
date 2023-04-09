```@meta
EditURL = "<unknown>/src/strategies/slow_fast.jl"
```

# [Slow Fast Moving Average](@id slow_fast_id)

````@example slow_fast
using Trading
using Trading.Strategies
using Trading.Basic
using Trading.Indicators
using Trading.Portfolio

struct SlowFast <: System end
Overseer.requested_components(::SlowFast) = (SMA{50, Close}, SMA{200, Close})

function Overseer.update(s::SlowFast, t::Trader, ticker_ledgers)
    for ticker_ledger in ticker_ledgers
        ticker = ticker_ledger.ticker
        for e in new_entities(ticker_ledger, s)
            lag_e = lag(e, 1)

            if lag_e === nothing
                continue
            end

            sma_50  = e[SMA{50, Close}].sma
            sma_200 = e[SMA{200, Close}].sma

            lag_sma_50 = lag_e[SMA{50, Close}].sma
            lag_sma_200 = lag_e[SMA{200, Close}].sma

            if sma_50 > sma_200 && lag_sma_50 < lag_sma_200
                Entity(t, Sale(ticker, Inf))
            elseif sma_50 < sma_200 && lag_sma_50 > lag_sma_200
                Entity(t, Purchase(ticker, Inf))
            end
        end
    end
end
````

The `Inf` values for the quantity of stocks to trade in the [`Sale`](@ref) and [`Purchase`](@ref) constructors signifies that we want to buy as many stocks as our cash balance allows for.

````@example slow_fast
broker = HistoricalBroker(AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"]))

strategy = Strategy(:slowfast, [SlowFast()], tickers=["MSFT", "AAPL"])

trader = BackTester(broker, start = DateTime("2015-01-01T00:00:00"),
                            stop = DateTime("2020-01-01T00:00:00"),
                            dt = Day(1),
                            strategies = [strategy],
                            cash = 1000,
                            only_day=false)
start(trader)
````

After having executed the strategy, we can see some quick overview from the output, but
by converting it to a `TimeArray` we can more easily analyse how the strategy performed

````@example slow_fast
using Plots

ta = TimeArray(trader)

plot(ta[:value])
````

We see that in this case the strategy didn't work particularly well. In fact it seems that
inverting it, we might get a better result.
We can simply redefine our `update` function as follows:

````@example slow_fast
function Overseer.update(s::SlowFast, t::Trader, ticker_ledgers)
    for ticker_ledger in ticker_ledgers
        ticker = ticker_ledger.ticker
        for e in new_entities(ticker_ledger, s)
            lag_e = lag(e, 1)

            if lag_e === nothing
                continue
            end

            sma_50  = e[SMA{50, Close}].sma
            sma_200 = e[SMA{200, Close}].sma

            lag_sma_50 = lag_e[SMA{50, Close}].sma
            lag_sma_200 = lag_e[SMA{200, Close}].sma

            if sma_50 > sma_200 && lag_sma_50 < lag_sma_200
                Entity(t, Purchase(ticker, Inf))
            elseif sma_50 < sma_200 && lag_sma_50 > lag_sma_200
                Entity(t, Sale(ticker, Inf))
            end
        end
    end
end
````

We have basically swapped the [`Purchase`](@ref) and [`Sale`](@ref) components.
To execute this updated version we call [`reset!`](@ref) and [`start`](@ref) again.

````@example slow_fast
reset!(trader)
start(trader)
````

and plot the results again, this time taking the relative performances of the portfolio vs the two stocks:

````@example slow_fast
ta = TimeArray(trader)

portfolio_val = ta[:value]./values(ta[:value])[1]
aapl_closes = ta[:AAPL_Close] ./ values(ta[:AAPL_Close])[1]
msft_closes = ta[:MSFT_Close] ./ values(ta[:MSFT_Close])[1]

plot(merge(portfolio_val, aapl_closes, msft_closes))
````

