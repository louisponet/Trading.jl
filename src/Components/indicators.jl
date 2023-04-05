"""
    MovingStdDev{horizon, T}

The moving standard deviation of a value over timeframe of `horizon`.
"""
@component struct MovingStdDev{horizon, T}
    σ::T
end
value(m::MovingStdDev) = value(m.σ)

"""
    SMA{horizon, T}

The simple moving average of a value over a timeframe of `horizon`.
"""
@component struct SMA{horizon, T}
    sma::T
end
value(sma::SMA) = value(sma.sma)

"""
    EMA{horizon, T}

The exponential moving average of a value over timeframe of `horizon`.
"""
@component struct EMA{horizon, T}
    ema::T
end
value(ema::EMA) = value(ema.ema)

"""
    Bollinger{horizon, T}

The up and down Bollinger bands for a value, over a timeframe of `horizon`.
"""
@component struct Bollinger{horizon, T}
    up::T
    down::T
end
value(b::Bollinger) = (value(b.up), value(b.down))

for diff_T in (:Difference, :RelativeDifference)
    @eval begin
        @component struct $diff_T{T} <: SingleValIndicator
            v::T
        end
        value(d::$diff_T) = value(d.v)

        Base.zero(d::$diff_T) = $diff_T(zero(value(d)))
    end
end

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

for op in (:+, :-, :*)
    @eval @inline Base.$op(b1::UpDown, b2::UpDown) = UpDown($op(b1.up, b2.up), $op(b1.down, b2.down))
end
@inline Base.:(/)(b::UpDown, i::Int) = UpDown(b.up/i, b.down/i)
@inline Base.:(^)(b::UpDown, i::Int) = UpDown(b.up^i, b.down^i)

@inline Base.:(*)(b::UpDown, i::AbstractFloat) = UpDown(b.up*i, b.down*i)
@inline Base.:(*)(i::Integer, b::UpDown) = b * i
@inline Base.sqrt(b::UpDown) = UpDown(sqrt(b.up), sqrt(b.down))
@inline Base.:(<)(i::Number, b::UpDown) = i < b.up &&  i < b.down
@inline Base.:(<)(b::UpDown, i::Number) = b.up < i &&  b.down < i
@inline Base.:(>)(i::Number, b::UpDown) = i > b.up &&  i > b.down
@inline Base.:(>)(b::UpDown, i::Number) = b.up > i &&  b.down > i
@inline Base.:(>=)(i::Number, b::UpDown) = i >= b.up && i >= b.down
@inline Base.:(>=)(b::UpDown, i::Number) = b.up >= i && b.down >= i
@inline Base.:(<=)(i::Number, b::UpDown) = i <= b.up && i <= b.down
@inline Base.:(<=)(b::UpDown, i::Number) = b.up <= i && b.down <= i

@assign UpDown with Is{Indicator}
value(ud::UpDown) = (value(ud.up), value(ud.down))

"""
    RSI{horizon, T}

The relative strength index of a value over timeframe of `horizon`.
"""
@component struct RSI{horizon, T}
    rsi::T
end

value(rsi::RSI) = value(rsi.rsi)

"""
    Sharpe{horizon, T}

The sharpe ratio of a value over a timeframe `horizon`.
"""
@component struct Sharpe{horizon, T}
    sharpe::T
end
