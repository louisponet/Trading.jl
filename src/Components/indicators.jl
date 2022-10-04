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

@component struct Difference{T}
    d::T
end
value(d::Difference) = value(d.d)

Base.zero(d::Difference) = Difference(zero(d.d))
for op in (:+, :-, :*)
    @eval @inline Base.$op(b1::Difference, b2::Difference) = Difference($op(b1.d, b2.d))
end
@inline Base.:(/)(b::Difference, i::Int) = Difference(b.d/i)
@inline Base.:(^)(b::Difference, i::Int) = Difference(b.d^i)

@inline Base.:(*)(b::Difference, i::AbstractFloat) = Difference(b.d*i)
@inline Base.:(*)(i::AbstractFloat, b::Difference) = b * i
@inline Base.sqrt(b::Difference) = Difference(sqrt(b.d))

@assign Difference with Is{Indicator}

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
@inline Base.:(*)(i::AbstractFloat, b::UpDown) = b * i
@inline Base.sqrt(b::UpDown) = UpDown(sqrt(b.up), sqrt(b.down))

@assign UpDown with Is{Indicator}
value(ud::UpDown) = (value(ud.up), value(ud.down))

@component struct RSI{horizon, T}
    rsi::T
end
value(rsi::RSI) = value(rsi.rsi)
