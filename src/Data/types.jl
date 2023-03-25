
const TimeArrayType = TimeArray{Float64, 2, TimeDate, Matrix{Float64}}

abstract type AbstractDataProvider end
abstract type AbstractTradingProvider end

abstract type AbstractBroker end

# abstract type AbstractHistoricalDataProvider <: AbstractDataProvider end

# abstract type AbstractRealtimeDataProvider <: AbstractDataProvider end




struct AuthenticationException <: Exception
    e
end

function Base.showerror(io::IO, err::AuthenticationException, args...)
    println(io, "AuthenticationException:")
    showerror(io, err.e, args...)
end

