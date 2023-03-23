Base.round(x::TimeDate, ::Type{T}, args...) where {T<:Period} = round(DateTime(x), T, args...)

function market_open_close(date)
    y = round(date, Year, RoundDown)
    d = round(date, Day, RoundDown)
    if y + Month(2) + Day(12) <= date < y + Month(10) + Day(5)
        open = d + Hour(13) + Minute(30)
    else
        open = d + Hour(14) + Minute(30)
    end
    return open, open + Hour(6) + Minute(30)
end

function yesterday()
    return round(now() - Day(1), Dates.Day)
end
