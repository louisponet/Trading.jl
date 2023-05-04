# Trading.jl
[![Build Status](https://github.com/louisponet/Trading.jl/workflows/CI/badge.svg)](https://github.com/louisponet/Trading.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/louisponet/Trading.jl/branch/master/graph/badge.svg?token=86X3QFJL5P)](https://codecov.io/gh/louisponet/Trading.jl)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://louisponet.github.io/Trading.jl/dev/)
[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://louisponet.github.io/Trading.jl/stable/)
[![Package Downloads](https://shields.io/endpoint?url=https://pkgs.genieframework.com/api/v1/badge/Trading)](https://pkgs.genieframework.com?packages=Trading)

This is an algorithmic trading and backtesting package written in Julia. It provides a framework for defining and executing trading strategies based on technical indicators, as well as backtesting these strategies on historical data.
Behind the scenes it relies on an ECS paradigm as implemented by [Overseer.jl](https://github.com/louisponet/Overseer.jl), making it extremely easy to extend.

# Simple Example
To define a trading strategy, users need to implement a Julia struct with an update function that defines the trading logic. The update function is called periodically by the framework, and has access to tick data for the specified assets, as well as any technical indicators requested by the strategy.

```julia
struct StratSys <: System end

Overseer.requested_components(::StratSys) = (Open, Close, SMA{20, Close}, SMA{200, Close})

function Overseer.update(s::StratSys, trader, asset_ledgers)
   for ledger in asset_ledgers
        for e in new_entities(ledger, s)
            #Trading logic goes here
        end
    end
end
```

The package includes several built-in technical indicators, such as simple moving averages, relative strength index, and exponential moving averages, but users can also define their own custom indicators.

To execute a trading strategy in real-time, users can create a Trader object with the desired strategies and assets, and connect it to a real-time data source through the different broker APIs.

```julia
broker = AlpacaBroker("<key_id>", "<secret>")

strategy = Strategy(:strat, [StratSys()], assets=[Stock("AAPL")])

trader = Trader(broker, strategies=[strategy])

start(trader)
```

If one wants to backtest a trading strategy on historical data, users can instead use `BackTester` instead of `Trader` with the desired data range, interval, and strategies. The backtester will simulate the behavior of a realtime trader on the specified data. Afterwards a [`TimeArray`](https://github.com/JuliaStats/TimeSeries.jl) can be created with the data from the `trader`, and used for performance analysis.

```julia
trader = BackTester(HistoricalBroker(broker), 
                    strategies=[strategy], 
                    start = <start date>, 
                    stop  = <stop date>, 
                    dt    = <data timeframe>)

start(trader)

ta = TimeArray(trader)

using Plots
plot(ta[:value])
```

The package is designed to be flexible and customizable, and can be extended with new technical indicators, trading strategies, and data sources.

See [Documentation](https://louisponet.github.io/Trading.jl/dev) for more details.

# Future Roadmap
- Improved performance analysis, statistics
- Implement standard plotting functionality
- [`Trader`](@ref) loading and saving
- Implement further signals and [`Indicators`](@ref)
- Backtest comparisons
- Support for different [`Brokers`](@ref)
