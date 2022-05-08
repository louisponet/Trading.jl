@component struct SMA{Horizon}
    sma::Float64
end

@component struct EMA{Horizon}
    ema::Float64
end

@component struct Bollinger{Horizon}
    up::Float64
    down::Float64
end
