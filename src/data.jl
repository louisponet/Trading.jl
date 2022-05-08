const HISTORICAL_DATA = joinpath(@__DIR__, "../data/historical.jld2")

function bars(ticker::String; start=Date("01-01-2000", dateformat"dd-mm-yyyy"), stop=Date(today()), timeframe="5Min", account::Union{Nothing, AccountInfo}=nothing)
    t = jldopen(HISTORICAL_DATA, "r") do f
        if haskey(f, "$ticker/$timeframe")
            return to(from(f["$ticker/$timeframe"], DateTime(start)), DateTime(stop))
        end
    end
    t !== nothing && return t
    # If not returned before here we add data and return
    jldopen(HISTORICAL_DATA, "a+") do f
        @assert account !== nothing "To pull new data please set the account keyword."
        allbars = TimeArray(query_bars(account, ticker, TimeDate(start), stop = TimeDate(stop), timeframe=timeframe))
        f["$ticker/$timeframe"] = allbars
        return allbars
    end
end

function intraday(bars)
    days = findall(x-> ( oc = market_open_close(x); oc[1] <= x <= oc[2]), timestamp(bars))
    return bars[days]
end

