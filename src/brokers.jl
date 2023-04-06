"""
    AbstractBroker

Interface for external brokers.
"""
abstract type AbstractBroker end

# Broker Interface
#TODO cleanup interface 
# subscibe(::AbstractBroker, ::WebSocket, ::String) = throw(MethodError(subscribe))
# bars(::AbstractBroker, ::Vector)                  = throw(MethodError(bars))
# authenticate_data(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_data))
# authenticate_trading(::AbstractBroker, ::WebSocket)  = throw(MethodError(authenticate_trading))
# latest_quote(::AbstractBroker, ticker::String)
broker(b::AbstractBroker) = b
data_query(b::AbstractBroker, args...; kwargs...) = data_query(broker(b), args...; kwargs...)

"""
    AuthenticationException

Use when throwing a failed authentication to a broker.
"""
struct AuthenticationException <: Exception
    e
end

function Base.showerror(io::IO, err::AuthenticationException, args...)
    println(io, "AuthenticationException:")
    showerror(io, err.e, args...)
end

# TODO not great
function retrieve_data(broker::AbstractBroker, set, key, start, stop, args...; normalize=false, kwargs...)
    ticker = key isa Tuple ? first(key) : key

    dt = key isa Tuple ? last(key) : Millisecond(1)
    @assert stop === nothing || start <= stop ArgumentError("start should be <= stop")
    
    if haskey(set, key) && !isempty(set[key])

        data = set[key]
        timestamps = timestamp(data)
        if stop !== nothing
            if start <= stop < timestamps[1]
                new_data = data_query(broker, ticker, start, stop, args...; kwargs...)
                
                if new_data !== nothing
                    new_data = normalize ? interpolate_timearray(new_data; kwargs...) : new_data
                    set[key] = vcat(new_data, data)
                end
                
                return new_data
                
            elseif timestamps[end] < start <= stop
                new_data = data_query(broker, ticker, start, stop, args...; kwargs...)

                if new_data !== nothing
                    new_data = normalize ? interpolate_timearray(new_data; kwargs...) : new_data
                    set[key] = vcat(data, new_data)
                end
                
                return new_data
                
            end
        end
            
        if timestamps[1] <= start 
            out_data = from(data, start)
        else
            next_stop = timestamps[1] - dt
            new_data = data_query(broker, ticker, start, next_stop, args...; kwargs...)
            
            if new_data !== nothing
                new_data = normalize ? interpolate_timearray(new_data; kwargs...) : new_data
                out_data = vcat(new_data, data)
                set[key] = out_data
            else
                out_data = data
            end

        end
        
        if stop === nothing
            return normalize ? interpolate_timearray(out_data; kwargs...) : out_data
        end
        
        if timestamps[end] >= stop
            tout = to(out_data, stop)
            return normalize ? interpolate_timearray(tout) : tout 
        else
            next_start = timestamps[end] + dt
            
            new_data = data_query(broker, ticker, next_start, stop, args...; kwargs...)
            if new_data !== nothing
                new_data = normalize ? interpolate_timearray(new_data; kwargs...) : new_data
                out_data = vcat(out_data, new_data)
                set[key] = vcat(set[key], new_data)
            end

            return normalize ? interpolate_timearray(out_data; kwargs...) : out_data
        end
    end
    data = data_query(broker, ticker, start, stop, args...; kwargs...)
    if data !== nothing
        data = normalize ? interpolate_timearray(data; kwargs...) : data
        set[key] = data
    end
    
    return data
end

include("brokers/alpaca.jl")
include("brokers/historical.jl")
include("brokers/mock.jl")
