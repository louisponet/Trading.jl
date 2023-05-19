# # [Slow Fast Moving Average](@id slow_fast_id)

using Trading
using Trading.Strategies
using Trading.Basic
using Trading.Indicators
using Trading.Portfolio

struct SlowFast <: System end
Overseer.requested_components(::SlowFast) = (SMA{50, Close}, SMA{200, Close})

function Overseer.update(s::SlowFast, t::Trader, asset_ledgers)
    for asset_ledger in asset_ledgers
        asset = asset_ledger.asset
        for e in new_entities(asset_ledger, s)
            prev_e = prev(e, 1)
            
            if prev_e === nothing
                continue
            end

            sma_50  = e[SMA{50, Close}].sma
            sma_200 = e[SMA{200, Close}].sma
            
            prev_sma_50 = prev_e[SMA{50, Close}].sma
            prev_sma_200 = prev_e[SMA{200, Close}].sma

            if sma_50 > sma_200 && prev_sma_50 < prev_sma_200
                Entity(t, Sale(asset, 1.0))
            elseif sma_50 < sma_200 && prev_sma_50 > prev_sma_200
                Entity(t, Purchase(asset, 1.0))
            end
        end
    end
end
# The `Inf` values for the quantity of stocks to trade in the [`Sale`](@ref) and [`Purchase`](@ref) constructors signifies that we want to buy as many stocks as our cash balance allows for.

broker = HistoricalBroker(AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"]))

strategy = Strategy(:slowfast, [SlowFast()], assets=[Stock("MSFT"), Stock("AAPL")])

trader = BackTester(broker, start = DateTime("2015-01-01T00:00:00"),
                            stop = DateTime("2020-01-01T00:00:00"),
                            dt = Day(1),
                            strategies = [strategy],
                            cash = 1000,
                            only_day=false)
start(trader)
# After having executed the strategy, we can see some quick overview from the output, but
# by converting it to a `TimeArray` we can more easily analyse how the strategy performed
using Plots

ta = TimeArray(trader)

plot(ta[:portfolio_value])

# We see that in this case the strategy didn't work particularly well. In fact it seems that
# inverting it, we might get a better result.
# We can simply redefine our `update` function as follows:

function Overseer.update(s::SlowFast, t::Trader, asset_ledgers)
    for asset_ledger in asset_ledgers
        asset = asset_ledger.asset
        for e in new_entities(asset_ledger, s)
            prev_e = prev(e, 1)
            
            if prev_e === nothing
                continue
            end

            sma_50  = e[SMA{50, Close}].sma
            sma_200 = e[SMA{200, Close}].sma
            
            prev_sma_50 = prev_e[SMA{50, Close}].sma
            prev_sma_200 = prev_e[SMA{200, Close}].sma

            if sma_50 > sma_200 && prev_sma_50 < prev_sma_200
                Entity(t, Purchase(asset, Inf))
            elseif sma_50 < sma_200 && prev_sma_50 > prev_sma_200
                Entity(t, Sale(asset, Inf))
            end
        end
    end
end

# We have basically swapped the [`Purchase`](@ref) and [`Sale`](@ref) components.
# To execute this updated version we call [`reset!`](@ref) and [`start`](@ref) again.

reset!(trader)
start(trader)
# and plot the results again, this time taking the relative performances of the portfolio vs the two stocks:

ta = Trading.relative(TimeArray(trader))

portfolio_val = ta[:portfolio_value]
aapl_closes = ta[:AAPL_Close]
msft_closes = ta[:MSFT_Close]

p = plot(merge(portfolio_val, aapl_closes, msft_closes))
savefig("slow_fast.svg") # hide
p # hide
