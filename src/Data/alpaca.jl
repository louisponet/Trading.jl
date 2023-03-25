const ALPACA_HISTORICAL_DATA_URL = URI("https://data.alpaca.markets")

Base.@kwdef mutable struct AlpacaBroker <: AbstractBroker
    key_id::String
    secret_key::String
    rate::Int = 200
    last::TimeDate = clock()
    nrequests::UInt64 = 0
    function AlpacaBroker(key_id, secret_key, rate, last, nrequests)
        try
            header = ["APCA-API-KEY-ID" => key_id, "APCA-API-SECRET-KEY" => secret_key]
            testpath = "/v2/stocks/AAPL/trades"
            resp = HTTP.get(URI(ALPACA_HISTORICAL_DATA_URL, path=testpath), header)
        catch e
            throw(AuthenticationException(e))
        end
        return new(key_id, secret_key, rate, last, nrequests)
    end
end

AlpacaBroker(key_id, secret_key; kwargs...) = AlpacaBroker(; key_id=key_id, secret_key=secret_key, kwargs...)

Base.string(::AlpacaBroker, start::TimeDate) = string(start) * "Z"
header(b::AlpacaBroker) = ["APCA-API-KEY-ID" => b.key_id, "APCA-API-SECRET-KEY" => b.secret_key]

function Base.string(::AlpacaBroker, timeframe::Period)
    if timeframe isa Minute
        period_string = "Min"
    else
        period_string = string(typeof(timeframe))
    end
    return "$(timeframe.value)$period_string"
end

Base.string(::AlpacaBroker, a) = string(a)

function stock_query(broker::AlpacaBroker, symbol, start, stop=clock(), ::Type{T} = Any; section, limit=1000, kwargs...) where {T}
    
    query = Dict{String, Any}("start" => string(broker, start))
    
    query["end"] = string(broker, stop)
    query["limit"] = limit
    for (k, v) in kwargs
        query[string(k)] = string(broker, v)
    end
    
    make_uri = () -> URI(ALPACA_HISTORICAL_DATA_URL, path = "/v2/stocks/$symbol/$section", query=query)

    out = Dict()
    timestamps = TimeDate[] 

    dat_keys = nothing
    section_symbol = Symbol(section)
    
    while true
        
        if broker.nrequests == broker.rate
            st = Minute(1) - (clock() - broker.last)
            if st < Minute(0)
                broker.nrequests=0
                broker.last = clock()
            else
                @info "Account request limit reached, throttling..."
                sleep(convert(Microsecond, st))
            end
        end
        
        if clock() - broker.last > Minute(1)
            broker.nrequests = 0
            broker.last = clock()
        end
        
        resp = HTTP.get(make_uri(), header(broker))
        broker.nrequests += 1
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
            dat_keys = filter(!isequal(:t), keys(data[1]))
            t_dat = Dict([k => Vector{T}(undef, n_dat) for k in dat_keys])
            t_timestamps = Vector{TimeDate}(undef, n_dat)

            Threads.@threads for i in 1:n_dat
                d = data[i]
                t_timestamps[i] = TimeDate(d[:t][1:end-1])
                
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

const HistoricalTradeDataDict = Dict{String, TimeArray{Any, 2, TimeDate, Matrix{Any}}}
const HistoricalQuoteDataDict = Dict{String, TimeArray{Any, 2, TimeDate, Matrix{Any}}}
const HistoricalBarDataDict = Dict{Tuple{String, Period}, TimeArray{Float64, 2, TimeDate, Matrix{Float64}}}
"""
   HistoricalDataProvider

"""
Base.@kwdef mutable struct HistoricalDataProvider{B <: AbstractBroker} <: AbstractDataProvider
    broker::B
    
    bar_data::HistoricalBarDataDict = HistoricalBarDataDict()
    trade_data::HistoricalTradeDataDict = HistoricalTradeDataDict()
    quote_data::HistoricalQuoteDataDict = HistoricalQuoteDataDict()
end

HistoricalDataProvider(b::AbstractBroker; kwargs...)  = HistoricalDataProvider(; broker=b, kwargs...)

# function retrieve_data(provider::HistoricalDataProvider, dataset, key, start, stop; kwargs...)

function retrieve_data(provider::HistoricalDataProvider, set, key, start, stop, args...; kwargs...)
    ticker = key isa Tuple ? first(key) : key

    dt = key isa Tuple ? last(key) : Millisecond(1)
    @assert start <= stop ArgumentError("start should be <= stop")
    
    if haskey(set, key)

        data = set[key]
        timestamps = timestamp(data)

        if start <= stop < timestamps[1]
            new_data = stock_query(provider.broker, ticker, start, stop, args...; kwargs...)
            
            if new_data !== nothing
                set[key] = vcat(new_data, data)
            end
            
            return new_data
            
        elseif timestamps[end] < start <= stop
            new_data = stock_query(provider.broker, ticker, start, stop, args...; kwargs...)

            if new_data !== nothing
                set[key] = vcat(data, new_data)
            end
            
            return new_data
            
        end
            

        if timestamps[1] <= start 
            out_data = from(data, start)
        else
            next_stop = timestamps[1] - dt
            new_data = stock_query(provider.broker, ticker, start, next_stop, args...; kwargs...)
            
            if new_data !== nothing
                out_data = vcat(new_data, data)
                set[key] = out_data
            else
                out_data = data
            end

        end

        if timestamps[end] >= stop
            return to(out_data, stop)
        else
            next_start = timestamps[end] + dt
            
            new_data = stock_query(provider.broker, ticker, next_start, stop, args...; kwargs...)
            if new_data !== nothing
                out_data = vcat(out_data, new_data)
                set[key] = vcat(data, new_data)
            end

            return out_data
        end
    end

    data = stock_query(provider.broker, ticker, start, stop, args...; kwargs...)
    if data !== nothing
        set[key] = data
    end
    
    return data
end
    

function bars(provider::HistoricalDataProvider, ticker, start, stop=clock(); timeframe::Period, kwargs...)
    
    start = round(start, typeof(timeframe), RoundDown)
    stop  = round(stop, typeof(timeframe), RoundUp)

    retrieve_data(provider, provider.bar_data, (ticker, timeframe), start, stop, Float64; section="bars", timeframe=timeframe, kwargs...)
end

quotes(provider::HistoricalDataProvider, ticker, args...; kwargs...) =
    retrieve_data(provider, provider.quote_data, ticker, args...; section="quotes", kwargs...)
    
trades(provider::HistoricalDataProvider, ticker, args...; kwargs...) = 
    retrieve_data(provider, provider.trade_data, ticker, args...; section="trades", kwargs...)
