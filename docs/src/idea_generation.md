# Idea Generation

Another, perhaps more standard, way to try and come up with new strategies before implementing them as a system is to manipulate data in `TimeArrays`.
Due to the way that the [`BackTester`](@ref) tries to mimic a true trading situation, it sacrifices a bit of outright speed. This may be fine in most cases,
but for true big data it is often faster to work with a `TimeArray`. Most of this functionality is present in the brilliant [TimeSeries](https://juliastats.org/TimeSeries.jl/latest/) and [MarketTechnicals](https://juliaquant.github.io/MarketTechnicals.jl/dev/) packages.

We here discuss the [slow fast](@ref slow_fast_id) again from this point of view.

## Slow Fast with TimeArrays
As usual, we define a [`Broker`](@ref Brokers), and proceed with acquiring the historical data with [`bars`](@ref).
```@example timearray_strategy
using Trading#hide
using Plots#hide
using MarketTechnicals

broker = AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"])

start_day = DateTime("2015-01-01T00:00:00")
stop_day  = DateTime("2020-01-01T00:00:00")
full_bars = bars(broker, Stock("AAPL"), start_day, stop_day, timeframe=Day(1))
df        = rename(merge(full_bars[:c], full_bars[:o]), [:AAPL_Close, :AAPL_Open])
```
Next, we calculate the two moving averages that we will use in our strategy:
```@example timearray_strategy
sma_ta = merge(sma(df, 20), sma(df, 120))
```
To find crossovers we do:

```@example timearray_strategy
diffs  = rename(sma_ta[:AAPL_Close_sma_20] .- sma_ta[:AAPL_Close_sma_120], :diff)
signal = TimeArray(timestamp(diffs), zeros(length(diffs)), [:signal])
diffs  = merge(diffs, rename(sign.(diffs), :sign), rename(sign.(lag(diffs,1)), :lagged_sign), signal)

diffs = map(diffs) do timestamp, vals
    if vals[2] != vals[3]
        if vals[1] < 0
            vals[4] = 1
        elseif vals[1] > 0
            vals[4] = -1
        end
    end
    return timestamp, vals
end
diffs[diffs[:signal] .!= 0]
```
Then we fill in our positions and cash balance, and calculate the total position value:
```@example timearray_strategy
signal   = lag(diffs[:signal], 1) # because we buy at open next period
position       = rename(cumsum(signal), :position)
position_value = rename(df[:AAPL_Close] .* position, :position_value)
cash           = rename(cumsum(signal .* -1 .* df[:AAPL_Open]), :cash)
total = rename(cash .+ position_value, :total)
df = merge(df, position_value, cash, total)

plot([df[:AAPL_Close] df[:total]])
```
We find similar horrible results as in [slow fast](@ref slow_fast_id) before.
