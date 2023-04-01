# Broker Interface
"""
    AbstractBroker

Interface for external brokers.
"""
abstract type AbstractBroker end

delete_all_orders!(b::AbstractBroker) = HTTP.delete(order_url(b), header(b))
#TODO cleanup interface 
# subscibe(::AbstractBroker, ::WebSocket, ::String) = throw(MethodError(subscribe))
# bars(::AbstractBroker, ::Vector)                  = throw(MethodError(bars))
# authenticate_data(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_data))
# authenticate_trading(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_trading))
# latest_quote(::AbstractBroker, ticker::String)

struct AuthenticationException <: Exception
    e
end

function Base.showerror(io::IO, err::AuthenticationException, args...)
    println(io, "AuthenticationException:")
    showerror(io, err.e, args...)
end

"""
    AbstractDataSource

Interface for different datasources.
"""
abstract type AbstractDataSource end

current_price(link::AbstractDataSource, ticker) = nothing 
last_close(link::AbstractDataSource, ticker)    = nothing

const HistoricalTradeDataDict = Dict{String, TimeArray{Any, 2, TimeDate, Matrix{Any}}}
const HistoricalQuoteDataDict = Dict{String, TimeArray{Any, 2, TimeDate, Matrix{Any}}}
const HistoricalBarDataDict = Dict{Tuple{String, Period}, TimeArray{Float64, 2, TimeDate, Matrix{Float64}}}

broker(b::AbstractBroker) = b
stock_query(b::AbstractBroker, args...; kwargs...) = stock_query(broker(b), args...; kwargs...)

function retrieve_data(provider::AbstractBroker, set, key, start, stop, args...; kwargs...)
    ticker = key isa Tuple ? first(key) : key

    dt = key isa Tuple ? last(key) : Millisecond(1)
    @assert stop === nothing || start <= stop ArgumentError("start should be <= stop")
    
    if haskey(set, key)

        data = set[key]
        timestamps = timestamp(data)
        if stop !== nothing
            if start <= stop < timestamps[1]
                new_data = stock_query(provider, ticker, start, stop, args...; kwargs...)
                
                if new_data !== nothing
                    set[key] = vcat(new_data, data)
                end
                
                return new_data
                
            elseif timestamps[end] < start <= stop
                new_data = stock_query(provider, ticker, start, stop, args...; kwargs...)

                if new_data !== nothing
                    set[key] = vcat(data, new_data)
                end
                
                return new_data
                
            end
        end
            
        if timestamps[1] <= start 
            out_data = from(data, start)
        else
            next_stop = timestamps[1] - dt
            new_data = stock_query(provider, ticker, start, next_stop, args...; kwargs...)
            
            if new_data !== nothing
                out_data = vcat(new_data, data)
                set[key] = out_data
            else
                out_data = data
            end

        end
        
        if stop === nothing
            return out_data
        end
        
        if timestamps[end] >= stop
            return to(out_data, stop)
        else
            next_start = timestamps[end] + dt
            
            new_data = stock_query(provider, ticker, next_start, stop, args...; kwargs...)
            if new_data !== nothing
                out_data = vcat(out_data, new_data)
                set[key] = vcat(data, new_data)
            end

            return out_data
        end
    end
    data = stock_query(provider, ticker, start, stop, args...; kwargs...)
    if data !== nothing
        set[key] = data
    end
    
    return data
end

function bars(provider::AbstractBroker, ticker, start, stop=clock(); timeframe::Period, kwargs...)
    
    start = round(start, typeof(timeframe), RoundDown)
    stop  = round(stop, typeof(timeframe), RoundUp)

    t = retrieve_data(provider, provider.bar_data, (ticker, timeframe), start, stop, Float64; section="bars", timeframe=timeframe, kwargs...)

    provider.bar_data[(ticker, timeframe)] = normalize(t, timeframe)
end

function normalize(tf::TimeArray{T}, timeframe::Period) where {T}
    tstamps = timestamp(tf)
    vals  = values(tf) 
    start = tstamps[1]
    stop = tstamps[end]
    out_times = TimeDate[start]
    ncols = size(vals, 2)
    out_vals = [[vals[1, i]] for i in 1:ncols]

    for i in 2:length(tf)
        prev_i = i - 1
        
        curt = tstamps[i]
        prevt = tstamps[prev_i]

        dt = curt - prevt

        if dt == timeframe
            push!(out_times, curt)
            for ic in 1:ncols
                push!(out_vals[ic], vals[i, ic])
            end
            continue
        end

        nsteps = dt / timeframe
        
        for j in 1:nsteps
            push!(out_times, prevt + timeframe * j)

            for ic in 1:ncols
                vp = vals[prev_i, ic]
                push!(out_vals[ic], vp + (vals[i, ic] - vp)/nsteps * j)
            end
            
        end
    end
    TimeArray(out_times, hcat(out_vals...), colnames(tf))
end

quotes(provider::AbstractBroker, ticker, args...; kwargs...) =
    retrieve_data(provider, provider.quote_data, ticker, args...; section="quotes", kwargs...)
    
trades(provider::AbstractBroker, ticker, args...; kwargs...) = 
    retrieve_data(provider, provider.trade_data, ticker, args...; section="trades", kwargs...)

function current_price(provider::AbstractBroker, ticker)
    dat = latest_quote(provider, ticker)
    return dat === nothing ? nothing : (dat[1] + dat[2])/2
end

