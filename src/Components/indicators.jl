"""
    MovingStdDev{horizon, T}

The moving standard deviation of a value over a sliding window of `horizon`.
"""
@component struct MovingStdDev{horizon,T}
    σ::T
end
value(m::MovingStdDev) = value(m.σ)
Base.eltype(::Type{MovingStdDev{x,T}}) where {x,T} = T
prefixes(::Type{<:MovingStdDev{horizon}}) where {horizon} = ("MovingStdDev_$(horizon)",)

"""
    SMA{horizon, T}

The simple moving average of a value over a sliding window of `horizon`.
"""
@component struct SMA{horizon,T}
    sma::T
end
value(sma::SMA) = value(sma.sma)
Base.eltype(::Type{SMA{x,T}}) where {x,T} = T
prefixes(::Type{<:SMA{horizon}}) where {horizon} = ("SMA_$(horizon)",)

"""
    EMA{horizon, T}

The exponential moving average of a value over a sliding window of `horizon`.
"""
@component struct EMA{horizon,T}
    ema::T
end
value(ema::EMA) = value(ema.ema)
Base.eltype(::Type{EMA{x,T}}) where {x,T} = T
prefixes(::Type{<:EMA{horizon}}) where {horizon} = ("EMA_$(horizon)",)

"""
    Bollinger{horizon, T}

The up and down Bollinger bands for a value, over a sliding window of `horizon`.
"""
@component struct Bollinger{horizon,T}
    up::T
    down::T
end
value(b::Bollinger) = (value(b.up), value(b.down))
Base.eltype(::Type{Bollinger{x,T}}) where {x,T} = T
prefixes(::Type{<:Bollinger{horizon}}) where {horizon} = ("Bollinger_$(horizon)_up","Bollinger_$(horizon)_down") 

for diff_T in (:Difference, :RelativeDifference)
    @eval begin
        @component struct $diff_T{T} <: SingleValIndicator{T}
            v::T
        end
        value(d::$diff_T) = value(d.v)
        Base.zero(d::$diff_T) = $diff_T(zero(value(d)))
    end
end

prefixes(::Type{<:Difference}) = ("Difference",) 
prefixes(::Type{<:RelativeDifference}) = ("RelativeDifference",) 
"""
    Difference

The lag 1 difference.
"""
Difference

"""
    RelativeDifference

The lag 1 relative difference.
"""
RelativeDifference

@component struct UpDown{T}
    up::T
    down::T
end
Base.zero(d::UpDown) = UpDown(zero(d.up), zero(d.down))
Base.eltype(::Type{UpDown{T}}) where {T} = T
prefixes(::Type{UpDown}) = ("UpDown_up", "UpDown_down")

for op in (:+, :-, :*)
    @eval @inline function Base.$op(b1::UpDown, b2::UpDown)
        return UpDown($op(b1.up, b2.up), $op(b1.down, b2.down))
    end
end
@inline Base.:(/)(b::UpDown, i::Int) = UpDown(b.up / i, b.down / i)
@inline Base.:(^)(b::UpDown, i::Int) = UpDown(b.up^i, b.down^i)

@inline Base.:(*)(b::UpDown, i::AbstractFloat) = UpDown(b.up * i, b.down * i)
@inline Base.:(*)(i::Integer, b::UpDown) = b * i
@inline Base.sqrt(b::UpDown) = UpDown(sqrt(b.up), sqrt(b.down))
@inline Base.:(<)(i::Number, b::UpDown) = i < b.up && i < b.down
@inline Base.:(<)(b::UpDown, i::Number) = b.up < i && b.down < i
@inline Base.:(>)(i::Number, b::UpDown) = i > b.up && i > b.down
@inline Base.:(>)(b::UpDown, i::Number) = b.up > i && b.down > i
@inline Base.:(>=)(i::Number, b::UpDown) = i >= b.up && i >= b.down
@inline Base.:(>=)(b::UpDown, i::Number) = b.up >= i && b.down >= i
@inline Base.:(<=)(i::Number, b::UpDown) = i <= b.up && i <= b.down
@inline Base.:(<=)(b::UpDown, i::Number) = b.up <= i && b.down <= i
Base.zero(::Type{UpDown{T}}) where {T} = UpDown(zero(T), zero(T))

@assign UpDown with Is{Indicator}
value(ud::UpDown) = (value(ud.up), value(ud.down))

"""
    RSI{horizon, T}

The relative strength index of a value over timeframe of `horizon`.
"""
@component struct RSI{horizon,T}
    rsi::T
end
value(rsi::RSI) = value(rsi.rsi)
Base.eltype(::Type{RSI{horizon,T}}) where {horizon,T} = T
prefixes(::Type{<:RSI{horizon}}) where {horizon} = ("RSI_$(horizon)",)

"""
    Sharpe{horizon, T}

The sharpe ratio of a value over a timeframe `horizon`.
"""
@component struct Sharpe{horizon,T}
    sharpe::T
end
Base.eltype(::Type{Sharpe{horizon,T}}) where {horizon,T} = T
prefixes(::Type{<:Sharpe{horizon}}) where {horizon} = ("Sharpe_$(horizon)",)

function TimeSeries.colnames(::Type{T}) where {T<:Union{Difference, RelativeDifference, LogVal, MovingStdDev, SMA, EMA, RSI, Sharpe, Bollinger, UpDown}}
    cnames = colnames(eltype(T))
    out = String[]
    for c in cnames
        for prefix in prefixes(T)
            push!(out, replace("$(prefix)_$c", "Trading." => ""))
        end
    end
    return out
end

