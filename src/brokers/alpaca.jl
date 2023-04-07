const ALPACA_EXCHS = Dict(
    "A" => "NYSE American (AMEX)",
    "B" => "NASDAQ OMX BX",
    "C" => "National Stock Exchange",
    "D" => "FINRA ADF",
    "E" => "Market Independent",
    "H" => "MIAX",
    "I" => "International Securities Exchange",
    "J" => "Cboe EDGA",
    "K" => "Cboe EDGX",
    "L" => "Long Term Stock Exchange",
    "M" => "Chicago Stock Exchange",
    "N" => "New York Stock Exchange",
    "P" => "NYSE Arca",
    "Q" => "NASDAQ OMX",
    "S" => "NASDAQ Small Cap",
    "T" => "NASDAQ Int",
    "U" => "Members Exchange",
    "V" => "IEX",
    "W" => "CBOE",
    "X" => "NASDAQ OMX PSX",
    "Y" => "Cboe BYX",
    "Z" => "Cboe BZX",
)

const ALPACA_CTS_CONDS = Dict(
    " " => "Regular Sale",
    "B" => "Average Price Trade",
    "C" => "Cash Trade (Same Day Clearing)",
    "E" => "Automatic Execution",
    "F" => "Inter-market Sweep Order",
    "H" => "Price Variation Trade",
    "I" => "Odd Lot Trade",
    "K" => "Rule 127 (NYSE only) or Rule 155 (NYSE MKT only)",
    "L" => "Sold Last (Late Reporting)",
    "M" => "Market Center Official Close",
    "N" => "Next Day Trade (Next Day Clearing)",
    "O" => "Market Center Opening Trade",
    "P" => "Prior Reference Price",
    "Q" => "Market Center Official Open",
    "R" => "Seller",
    "T" => "Extended Hours Trade",
    "U" => "Extended Hours Sold (Out Of Sequence)",
    "V" => "Contingent Trade",
    "X" => "Cross Trade",
    "Z" => "Sold (Out Of Sequence) ",
    "4" => "Derivatively Priced",
    "5" => "Market Center Reopening Trade",
    "6" => "Market Center Closing Trade",
    "7" => "Qualified Contingent Trade",
    "8" => "Reserved",
    "9" => "Corrected Consolidated Close Price as per Listing Market",
)

const ALPACA_UTDF_CONDS = Dict(
    "@" => "Regular Sale",
    "R" => "Seller",
    "A" => "Acquisition",
    "S" => "Split Trade",
    "B" => "Bunched Trade",
    "T" => "Form T",
    "C" => "Cash Sale",
    "U" => "Extended trading hours (Sold Out of Sequence)",
    "D" => "Distribution",
    "V" => "Contingent Trade",
    "E" => "Placeholder",
    "W" => "Average Price Trade",
    "F" => "Intermarket Sweep",
    "X" => "Cross Trade",
    "G" => "Bunched Sold Trade",
    "Y" => "Yellow Flag Regular Trade",
    "H" => "Price Variation Trade",
    "Z" => "Sold (out of sequence)",
    "I" => "Odd Lot Trade",
    "1" => "Stopped Stock (Regular Trade)",
    "K" => "Rule 155 Trade (AMEX)",
    "4" => "Derivatively priced",
    "L" => "Sold Last",
    "5" => "Re-Opening Prints",
    "M" => "Market Center Official Close",
    "6" => "Closing Prints",
    "N" => "Next Day",
    "7" => "Qualified Contingent Trade (QCT)",
    "O" => "Opening Prints",
    "8" => "Placeholder For 611 Exempt",
    "P" => "Prior Reference Price",
    "9" => "Corrected Consolidated Close (per listing market)",
    "Q" => "Market Center Official Open",
)

const ALPACA_CQS_CONDS = Dict(
    "A" => "Slow Quote Offer Side",
    "B" => "Slow Quote Bid Side",
    "E" => "Slow Quote LRP Bid Side",
    "F" => "Slow Quote LRP Offer Side",
    "H" => "Slow Quote Bid And Offer Side",
    "O" => "Opening Quote",
    "R" => "Regular Market Maker Open",
    "W" => "Slow Quote Set Slow List",
    "C" => "Closing Quote",
    "L" => "Market Maker Quotes Closed",
    "U" => "Slow Quote LRP Bid And Offer",
    "N" => "Non Firm Quote",
    "4" => "On Demand Intra Day Auction",
)

const ALPACA_UQDF_CONDS = Dict(
    "A" => "Manual Ask Automated Bid",
    "B" => "Manual Bid Automated Ask",
    "F" => "Fast Trading",
    "H" => "Manual Bid And Ask",
    "I" => "Order Imbalance",
    "L" => "Closed Quote",
    "N" => "Non Firm Quote",
    "O" => "Opening Quote Automated",
    "R" => "Regular Two Sided Open",
    "U" => "Manual Bid And Ask Non Firm",
    "Y" => "No Offer No Bid One Sided Open",
    "X" => "Order Influx",
    "Z" => "No Open No Resume",
    "4" => "On Demand Intra Day Auction",
)

"""
    AlpacaBroker

Broker to communicate with [Alpaca](https://app.alpaca.markets).
Can be constructed with your `key_id` and `secret_key` (see [connect-to-alpaca-api](https://alpaca.markets/learn/connect-to-alpaca-api/)).
"""
Base.@kwdef mutable struct AlpacaBroker <: AbstractBroker
    key_id::String
    secret_key::String
    cache::DataCache = DataCache()
    rate::Int = 200
    last::TimeDate = current_time()
    @atomic nrequests::Int
    
    function AlpacaBroker(key_id, secret_key, cache, rate, last, nrequests)
        try
            header  = ["APCA-API-KEY-ID" => key_id, "APCA-API-SECRET-KEY" => secret_key]
            testurl =  URI("https://data.alpaca.markets/v2/stocks/AAPL/trades")
            resp    = HTTP.get(testurl, header)
        catch e
            throw(AuthenticationException(e))
        end
        return new(key_id, secret_key, cache, rate, last, nrequests)
    end
    
end

AlpacaBroker(key_id, secret_key; kwargs...) = AlpacaBroker(; key_id=key_id, secret_key=secret_key, nrequests=0, kwargs...)

header(b::AlpacaBroker) = ["APCA-API-KEY-ID" => b.key_id, "APCA-API-SECRET-KEY" => b.secret_key]

data_stream_url(::AlpacaBroker)            = URI("wss://stream.data.alpaca.markets/v2/iex")
trading_stream_url(::AlpacaBroker)         = URI("wss://paper-api.alpaca.markets/stream") 
trading_url(::AlpacaBroker)                = URI("https://paper-api.alpaca.markets")
order_url(b::AlpacaBroker)                 = URI(trading_url(b), path="/v2/orders")
data_url(::AlpacaBroker)                   = URI("https://data.alpaca.markets")
quote_url(b::AlpacaBroker, ticker::String) = URI(data_url(b), path = "/v2/stocks/$ticker/quotes/latest")

function Base.string(::AlpacaBroker, timeframe::Period)
    if timeframe isa Minute
        period_string = "Min"
    else
        period_string = string(typeof(timeframe))
    end
    return "$(timeframe.value)$period_string"
end

Base.string(::AlpacaBroker, a) = string(a)

function Base.string(::AlpacaBroker, a::DateTime)
    return string(ZonedDateTime(a, LOCAL_TZ))
end

function data_fields(b::AlpacaBroker, section::String)
    if section == "bars"
        return bar_fields(b)[2:end]
    end
end

bar_fields(::AlpacaBroker) = (:t, :o, :h, :l, :c, :v, :n, :vw)

mock_bar(b::AlpacaBroker, ticker, vals) = merge((T="b", S=ticker), NamedTuple(map(x -> x[1] => x[2], zip(bar_fields(b), vals))))

function data_query(broker::AlpacaBroker, symbol, start, stop=nothing, ::Type{T} = Any; section, limit=1000, kwargs...) where {T}
    query = Dict{String, Any}("start" => string(broker, start))
    if stop !== nothing
        query["end"] = string(broker, stop)
    end
    query["limit"] = limit
    for (k, v) in kwargs
        query[string(k)] = string(broker, v)
    end
    
    make_uri = () -> URI(data_url(broker), path = "/v2/stocks/$symbol/$section", query=query)

    out = Dict()
    timestamps = TimeDate[] 

    dat_keys = nothing
    section_symbol = Symbol(section)
    
    while true

        #TODO requests are throttling more than they should
        while broker.nrequests == broker.rate
            sleep(1)
        end
        
        resp = HTTP.get(make_uri(), header(broker))
        @atomic broker.nrequests += 1
        
        @async begin
            sleep(60)
            @atomic broker.nrequests -= 1
        end
        
        if resp.status == 200
            t = JSON3.read(resp.body)
            if t[section_symbol] === nothing
                if t["next_page_token"] === nothing
                    return
                else
                    continue
                end
            end

            data = t[section_symbol]

            n_dat = length(data)
            dat_keys = data_fields(broker, section)
            t_dat = Dict([k => Vector{T}(undef, n_dat) for k in dat_keys])
            t_timestamps = Vector{TimeDate}(undef, n_dat)

            Threads.@threads for i in 1:n_dat
                d = data[i]
                t_timestamps[i] = parse_time(d[:t])
                
                for k in dat_keys
                    t_dat[k][i] = d[k]
                end
                
            end

            for (k, vals) in t_dat
                if haskey(out, k)
                    append!(out[k], vals)
                else
                    out[k] = vals
                end
            end
            append!(timestamps, t_timestamps)
            
            if haskey(t, :next_page_token) && t[:next_page_token] !== nothing
                query["page_token"] = t[:next_page_token]
            else
                break
            end
        else
            @warn """
            Something went wrong querying $section data for ticker $symbol
            leading to status: $(resp.status)
            """
            break
        end
    end
    
    delete!(query, "page_token")
    
    return TimeArray(timestamps, hcat([out[k] for k in dat_keys]...), collect(dat_keys))
end

