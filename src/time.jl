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

function current_time()
    tv = Base.Libc.TimeVal()
    tm = Libc.TmStruct(tv.sec)
    return TimeDate(tm.year + 1900, tm.month + 1, Int64(tm.mday), Int64(tm.hour), Int64(tm.min), Int64(tm.sec)) + Microsecond(tv.usec)
end

current_time(broker::HistoricalBroker) = broker.clock.time
current_time(::AlpacaBroker) = current_time()

current_time(trader::Trader{<:HistoricalBroker}) = trader[Clock][1].time
current_time(::Trader) = current_time() 

function market_open_close(date, timezone=tz"EST")
    y = round(date, Year, RoundDown)
    d = round(date, Day, RoundDown)

    open  = astimezone(ZonedDateTime(d + Hour(8) + Minute(30), timezone), LOCAL_TZ)
    close = astimezone(ZonedDateTime(d + Hour(15), timezone), LOCAL_TZ)

    return TimeDate(DateTime(open)), TimeDate(DateTime(close))
end

yesterday() = 
    TimeDate(round(now() - Day(1), Dates.Day))

function in_day(t)
    open, close = market_open_close(t)
    return open <= t <= close
end

in_day(l::Trader) = in_day(current_time(l))

function in_trading(t)
    open, close = market_open_close(t)
    return dayofweek(t) <= 5 && open <= t <= close
end

function previous_trading_day(t=current_time())
    prev_day = t - Day(1)
    while dayofweek(prev_day) >= 5
        prev_day -= Day(1)
    end
    return prev_day
end

is_market_open(t, period::T=Minute(1)) where {T} = 
    T(0) <= market_open_close(t)[1] - t <= T(1)
