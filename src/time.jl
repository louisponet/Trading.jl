using TimeZones

const LOCAL_TZ = tz"Europe/Zurich"

function current_time()
    tv = Base.Libc.TimeVal()
    tm = Libc.TmStruct(tv.sec)
    return TimeDate(tm.year + 1900, tm.month + 1, Int64(tm.mday), Int64(tm.hour), Int64(tm.min), Int64(tm.sec)) + Microsecond(tv.usec)
end

function market_open_close(date, timezone=tz"EST")
    y = round(date, Year, RoundDown)
    d = round(date, Day, RoundDown)

    open  = astimezone(ZonedDateTime(d + Hour(8) + Minute(30), timezone), LOCAL_TZ)
    close = astimezone(ZonedDateTime(d + Hour(15), timezone), LOCAL_TZ)

    return TimeDate(DateTime(open)), TimeDate(DateTime(close))
end

function yesterday()
    return TimeDate(round(now() - Day(1), Dates.Day))
end

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

current_time(trader::Trader{<:HistoricalBroker}) = trader[Clock][1].time
current_time(::Trader) = current_time() 
current_time(broker::HistoricalBroker) = broker.clock.time
current_time(::AlpacaBroker) = current_time()
