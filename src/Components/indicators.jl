@component struct MovingStdDev{horizon, T}
    σ::T
end
value(m::MovingStdDev) = value(m.σ)

@component struct SMA{horizon, T}
    sma::T
end
value(sma::SMA) = value(sma.sma)

@component struct EMA{horizon, T}
    ema::T
end
value(ema::EMA) = value(ema.ema)

@component struct Bollinger{horizon, T}
    up::T
    down::T
end
value(b::Bollinger) = (value(b.up), value(b.down))

for diff_T in (:Difference, :RelativeDifference)
    @eval begin
        @component struct $diff_T{T}
            d::T
        end
        value(d::$diff_T) = value(d.d)

        Base.zero(d::$diff_T) = $diff_T(zero(d.d))
    end
    for op in (:+, :-, :*, :/)
        @eval @inline Base.$op(b1::$diff_T, b2::$diff_T) = $diff_T($op(b1.d, b2.d))
    end
    @eval begin
        @inline Base.:(/)(b::$diff_T, i::Int) = $diff_T(b.d/i)
        @inline Base.:(^)(b::$diff_T, i::Int) = $diff_T(b.d^i)

        @inline Base.:(*)(b::$diff_T, i::AbstractFloat) = $diff_T(b.d*i)
        @inline Base.:(*)(i::AbstractFloat, b::$diff_T) = b * i
        @inline Base.:(*)(i::Integer, b::$diff_T) = b * i
        @inline Base.sqrt(b::$diff_T) = $diff_T(sqrt(b.d))
        @inline Base.:(<)(i::Number, b::$diff_T) = i < b.d
        @inline Base.:(<)(b::$diff_T, i::Number) = b.d < i
        @inline Base.:(>)(i::Number, b::$diff_T) = i > b.d
        @inline Base.:(>)(b::$diff_T, i::Number) = b.d > i
        @inline Base.:(>=)(i::Number, b::$diff_T) = i >= b.d
        @inline Base.:(>=)(b::$diff_T, i::Number) = b.d >= i
        @inline Base.:(<=)(i::Number, b::$diff_T) = i <= b.d
        @inline Base.:(<=)(b::$diff_T, i::Number) = b.d <= i
        @assign $diff_T with Is{Indicator}
    end
end


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

@component struct RSI{horizon, T}
    rsi::T
end
value(rsi::RSI) = value(rsi.rsi)

@component struct Sharpe{horizon, T}
    sharpe::T
end
