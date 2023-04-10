using TimeZones

const LOCAL_TZ = tz"Europe/Zurich"

function parse_time(str)
    date, time = split(str, 'T')
    decimals_TZ = match(r"\.(\d+)([^\d]*.*)", time)
    if decimals_TZ !== nothing
        if !isempty(decimals_TZ.captures[2])
            tz = TimeZone(decimals_TZ.captures[2])
        else
            tz = LOCAL_TZ
        end
        
        return DateTime(astimezone(ZonedDateTime(DateTime(date*"T"*time[1:12]), tz), LOCAL_TZ))
    else
        TZ = match(r"(.*:\d\d)([^\d:]*.*)", str)
        if !isempty(TZ.captures[2])
            tz = TimeZone(TZ.captures[2])
        else
            tz = LOCAL_TZ
        end
        DateTime(astimezone(ZonedDateTime(DateTime(TZ.captures[1]), tz), LOCAL_TZ))
    end
end

"""
    current_time()
    current_time(broker)
    current_time(trader)

Returns the current time either globally, or of an [broker](@ref Brokers) or [`Trader`](@ref) which is essentially the same as the trader's broker.
"""
function current_time()
    tv = Base.Libc.TimeVal()
    tm = Libc.TmStruct(tv.sec)
    return TimeDate(tm.year + 1900, tm.month + 1, Int64(tm.mday), Int64(tm.hour), Int64(tm.min), Int64(tm.sec)) + Microsecond(tv.usec)
end

current_time(broker::HistoricalBroker) = broker.clock.time
current_time(::AlpacaBroker) = current_time()

current_time(trader::Trader{<:HistoricalBroker}) = trader[Clock][1].time
current_time(::Trader) = current_time() 

# TODO maybe use everywhere a way to supply what the local
# timezone is
"""
    market_open_close(time, timezone=tz"EST")

Returns the open and closing time of the market located in `timezone`, and converts it to the local timezone, i.e. central european time.
It assumes opening at 9:30am and closing at 4pm.

# Example
```jldoctest
julia> Trading.market_open_close(DateTime("2023-04-05"))
(DateTime("2023-04-05T15:30:00"), DateTime("2023-04-05T22:00:00"))
"""
function market_open_close(date, timezone=tz"EST")
    y = round(date, Year, RoundDown)
    d = round(date, Day, RoundDown)

    open  = astimezone(ZonedDateTime(d + Hour(8) + Minute(30), timezone), LOCAL_TZ)
    close = astimezone(ZonedDateTime(d + Hour(15), timezone), LOCAL_TZ)

    return TimeDate(DateTime(open)), TimeDate(DateTime(close))
end

yesterday() = 
    TimeDate(round(now() - Day(1), Dates.Day))

"""
    in_day(time, args...)

Returns `true` if the time is within the trading hours on a weekday.
The `args` are passed to [`market_open_close`](@ref).

# Example
```jldoctest
julia> Trading.in_day(DateTime("2023-02-02T00:00:00"))
false

julia> Trading.in_day(DateTime("2023-02-02T15:00:00"))
true
```
"""
function in_day(t)
    open, close = market_open_close(t)
    return dayofweek(t) <= 5 && open <= t <= close
end

in_day(l::Trader) = in_day(current_time(l))

"""
    previous_trading_day(time)

Returns the previous trading day, i.e. skipping saturdays and sundays.

# Example
```jldoctest
julia> Trading.previous_trading_day(DateTime("2023-04-06"))
2023-04-05T00:00:00

julia> Trading.previous_trading_day(DateTime("2023-04-03"))
2023-03-30T00:00:00
```
"""
function previous_trading_day(t=current_time())
    prev_day = t - Day(1)
    while dayofweek(prev_day) >= 5
        prev_day -= Day(1)
    end
    return prev_day
end

"""
    is_market_open(time, interval=Minute(1))

Tests whether a given time is within `interval` **before** market open.

# Example
```jldoctest
julia> Trading.is_market_open(DateTime("2023-04-04T15:31:00"))
false

julia> Trading.is_market_open(DateTime("2023-04-04T15:30:00"))
true

julia> Trading.is_market_open(DateTime("2023-04-04T15:29:00"))
true

julia> Trading.is_market_open(DateTime("2023-04-04T15:28:00"))
false
"""
is_market_open(t, interval::T=Minute(1)) where {T} = 
    T(0) <= market_open_close(t)[1] - t <= interval
    
"""
    is_market_close(time, interval=Minute(1))

Tests whether a given time is within `interval` **before** market close.

# Example
```jldoctest
julia> Trading.is_market_close(DateTime("2023-04-04T22:01:00"))
false

julia> Trading.is_market_close(DateTime("2023-04-04T22:00:00"))
true

julia> Trading.is_market_close(DateTime("2023-04-04T21:59:00"))
true

julia> Trading.is_market_close(DateTime("2023-04-04T21:58:00"))
false
"""
is_market_close(t, interval::T=Minute(1)) where {T} = 
    T(0) <= market_open_close(t)[2] - t <= interval
