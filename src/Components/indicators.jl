@component struct SMA{T, horizon}
    sma::T
end

@component struct EMA{T, horizon}
    ema::T
end

@component struct Bollinger{T, horizon}
    up::T
    down::T
end

@component struct RSI
    rsi::Float64
end
    
