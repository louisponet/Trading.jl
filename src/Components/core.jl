import Base: zero, +, -, /, *, sqrt, ^
@trait Indicator

@implement Is{Indicator} by zero(_) 
@implement Is{Indicator} by (+)(_, _) 
@implement Is{Indicator} by (-)(_, _) 
@implement Is{Indicator} by (*)(_, _) 
@implement Is{Indicator} by (/)(_, ::Int) 
@implement Is{Indicator} by (*)(_, ::AbstractFloat) 
@implement Is{Indicator} by (*)(::AbstractFloat, _) 
@implement Is{Indicator} by (*)(::Integer, _) 
@implement Is{Indicator} by (sqrt)(_) 
@implement Is{Indicator} by (^)(_, ::Int) 

@component Base.@kwdef mutable struct Clock
    time::TimeDate = TimeDate(now())
    dtime::Period  = Minute(1)
end

# All need to have a single field v
abstract type SingleValIndicator{T} end

"""
    Open

The opening price of a given bar.
"""
@component struct Open <: SingleValIndicator{Float64}
    v::Float64
end

"""
    Close

The closing price of a given bar.
"""
@component struct Close <: SingleValIndicator{Float64}
    v::Float64
end

"""
    High

The highest price of a given bar.
"""
@component struct High <: SingleValIndicator{Float64}
    v::Float64
end

"""
    Low

The lowest price of a given bar.
"""
@component struct Low <: SingleValIndicator{Float64}
    v::Float64
end

"""
    Volume

The traded volume of a given bar.
"""
@component struct Volume <: SingleValIndicator{Float64}
    v::Float64
end

"""
    LogVal

The logarithm of a value.
"""
@component struct LogVal{T} <: SingleValIndicator{T}
    v::T
end

for op in (:+, :-, :*, :/,  :^)
    @eval @inline Base.$op(b1::T, b2::T) where {T <: SingleValIndicator} = T($op(value(b1),   value(b2)))
    @eval @inline Base.$op(b1::T, b2::Number) where {T <: SingleValIndicator} = T($op(value(b1),   b2))
    @eval @inline Base.$op(b1::Number, b2::T) where {T <: SingleValIndicator} = T($op(b1,   value(b2)))
end

for op in (:(<), :(>), :(>=), :(<=), :(==))
    @eval @inline Base.$op(b1::SingleValIndicator, b2::SingleValIndicator) = $op(value(b1),   value(b2))
    @eval @inline Base.$op(b1::SingleValIndicator, b2::Number)             = $op(value(b1),   b2)
    @eval @inline Base.$op(b1::Number, b2::SingleValIndicator)             = $op(b1,   value(b2))
end

Base.zero(::T) where {T<:SingleValIndicator} = T(0.0)
@inline Base.sqrt(b::T) where {T <: SingleValIndicator} = T(sqrt(value(b)))
@inline Base.isless(b::SingleValIndicator, i) = value(b) < i
@inline value(b::SingleValIndicator) = value(b.v)
@inline value(b::Number) = b
@inline Base.convert(::Type{T}, b::SingleValIndicator) where {T <: Number} = convert(T, value(b))
Base.eltype(::Type{SingleValIndicator{T}}) where {T} = T

@assign SingleValIndicator with Is{Indicator}

"""
    TimeStamp

Associates a time to an `Entity`.
"""
@component struct TimeStamp
    t::TimeDate
end

TimeStamp() = TimeStamp(TimeDate(now()))

"""
    Strategy

A `Stage` with a set of `Systems` that execute a strategy.
"""
@component Base.@kwdef struct Strategy
    stage::Stage
    only_day::Bool = false
    tickers::Vector{String} = String[]
end

Strategy(name::Symbol, steps; kwargs...) = Strategy(stage=Stage(name, steps); kwargs...)
