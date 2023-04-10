# Time
```@meta
CurrentModule=Trading
```
Time is represented by the standard `DateTime` from [Base.Dates](https://docs.julialang.org/en/v1/stdlib/Dates/) and `ZonedDateTime` from [TimeZones.jl](https://github.com/JuliaTime/TimeZones.jl) for more precise timing.

## Important
- A standard `DateTime` will be assumed to be in central Europe / Zurich time
- Trading.jl is at present not aware of holidays or other market altering behavior, i.e. trading days are assumed to always be Monday-Friday; 9:30am - 4pm.

## Utility Functions
These can be pulled into the main namespace by `using Trading.Time`.
```@docs
current_time
market_open_close
in_day
previous_trading_day
is_market_open
is_market_close
```

## Clock
```@docs
Clock
```
