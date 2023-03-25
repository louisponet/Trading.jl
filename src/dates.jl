using TimeZones

const LOCAL_TZ = tz"Europe/Zurich"



Base.round(x::TimeDate, ::Type{T}, args...) where {T<:Period} = round(DateTime(x), T, args...)

function market_open_close(date, timezone=tz"EST")
    y = round(date, Year, RoundDown)
    d = round(date, Day, RoundDown)

    open  = astimezone(ZonedDateTime(d + Hour(8) + Minute(30), timezone), LOCAL_TZ)
    close = astimezone(ZonedDateTime(d + Hour(15), timezone), LOCAL_TZ)

    return TimeDate(DateTime(open)), TimeDate(DateTime(close))
end

function yesterday()
    return round(now() - Day(1), Dates.Day)
end

function in_day(t)
    open, close = market_open_close(t)
    return open <= t <= close
end

