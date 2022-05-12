@component struct SMA{N}
    sma::NTuple{N, Float64}
end
SMA{N}(v::AbstractVector) where {N} = SMA{N}((v...,))

@component struct EMA{N}
    ema::NTuple{N, Float64}
end
EMA{N}(v::AbstractVector) where {N} = EMA{N}((v...,))

@component struct Bollinger{N}
    up::NTuple{N, Float64}
    down::NTuple{N, Float64}
end
Bollinger{N}(v1::AbstractVector, v2::AbstractVector) where {N} = EMA{N}((v1...,), (v2...,))

@component struct UpDown
    up::Float64
    down::Float64
end

@component struct RSI
    rsi::Float64
end
    
