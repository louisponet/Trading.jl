using TimeZones

const LOCAL_TZ = tz"Europe/Zurich"

function clock()
    tv = Base.Libc.TimeVal()
    tm = Libc.TmStruct(tv.sec)
    return TimeDate(tm.year + 1900, tm.month + 1, Int64(tm.mday), Int64(tm.hour), Int64(tm.min), Int64(tm.sec)) + Microsecond(tv.usec)
end

Base.round(x::TimeDate, ::Type{T}, t::RoundingMode) where {T<:Period} = TimeDate(round(DateTime(x), T, t))
Base.round(x::TimeDate, ::Type{T}) where {T<:Period} = round(x, T, RoundDown())

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

