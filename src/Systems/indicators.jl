"""
    SMACalculator

Calculates the [`SMA`](@ref) of data.
"""
struct SMACalculator <: System end

function Overseer.update(s::SMACalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if T <: SMA && T.parameters[2] ∈ l
            sma(l[T.parameters[2]], c)
        end
    end
end

function sma(comp, sma_comp::AbstractComponent{sma_T}) where {sma_T<:SMA}
    horizon = sma_T.parameters[1]
    startid = length(sma_comp) + 1

    if startid + horizon - 1 > length(comp)
        return
    end

    m = sum(i -> comp[i], startid:length(sma_comp)+horizon-1)

    for i in startid+horizon-1:length(comp)
        m += comp[i]
        sma_comp[entity(comp, i)] = sma_T(m / horizon)
        m -= comp[i-horizon+1]
    end
end

"""
    MovingStdDevCalculator

Calculates the [`MovingStdDev`](@ref) of data.
"""
struct MovingStdDevCalculator <: System end

function Overseer.update(s::MovingStdDevCalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if T <: MovingStdDev && T.parameters[2] ∈ l
            stdev(l[T.parameters[2]], c)
        end
    end
end

function stdev(comp, stdev_comp::AbstractComponent{stdev_T}) where {stdev_T<:MovingStdDev}
    horizon = stdev_T.parameters[1]
    startid = length(stdev_comp) + 1

    if startid + horizon - 1 > length(comp)
        return
    end

    m  = sum(i -> comp[i], startid:length(stdev_comp)+horizon-1)
    m² = sum(i -> comp[i]^2, startid:length(stdev_comp)+horizon-1)

    for i in startid+horizon-1:length(comp)
        val = comp[i]
        m += val
        m² += val^2
        t = (m² - m^2 / horizon) / horizon

        stdev_comp[entity(comp, i)] = t < 0 ? stdev_T(zero(comp[1])) : stdev_T(sqrt(t))
        m -= comp[i-horizon+1]
        m² -= comp[i-horizon+1]^2
    end
end

"""
    EMACalculator

Calculates the [`EMA`](@ref) of data.
"""
Base.@kwdef struct EMACalculator <: System
    smoothing::Int = 2
end

function Overseer.update(s::EMACalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if T <: EMA && T.parameters[2] ∈ l
            ema(l[T.parameters[2]], c, s.smoothing)
        end
    end
end

function ema(comp::AbstractComponent{T}, ema_comp::AbstractComponent{ema_T},
             smoothing) where {T,ema_T<:EMA}
    horizon = ema_T.parameters[1]

    m = zero(T)

    fac = smoothing / (1 + horizon)
    for i in 1:length(comp)
        val = comp[i]
        if i < horizon
            m += val
        elseif i == horizon
            m += val
            m /= horizon
        else
            m = val * fac + m * (1 - fac)

            ema_comp[entity(comp, i)] = ema_T(m)
        end
    end
end

"""
    BollingerCalculator

Calculates the [`Bollinger`](@ref) bands for data.
The `width` parameter can be tuned, by default it is `2.0`.
"""
Base.@kwdef struct BollingerCalculator <: System
    width::Float64 = 2.0
end

function Overseer.update(s::BollingerCalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if T <: Bollinger
            sma_T = SMA{T.parameters...}
            ind_T = T.parameters[2]

            if sma_T ∈ l && ind_T ∈ l
                bollinger(l[ind_T], l[sma_T], c, s.width)
            end
        end
    end
end

function bollinger(comp::AbstractComponent{T}, sma_comp::AbstractComponent{sma_T},
                   bol_comp::AbstractComponent{bol_T},
                   width) where {T,sma_T<:SMA,bol_T<:Bollinger}
    stdev = zero(T)
    horizon = sma_T.parameters[1]

    startid = length(bol_comp) + 1

    if startid + horizon - 1 > length(comp)
        return
    end

    fac = width * sqrt((horizon - 1) / horizon)

    for ie in startid+horizon-1:length(comp)
        e = entity(comp, ie)

        stdev = zero(stdev)

        s = sma_comp[e].sma

        for i in ie-horizon+1:ie
            stdev += (comp[i] - s)^2
        end

        stdev = sqrt(stdev / (horizon - 1))
        t = stdev * fac
        up = s + t
        down = s - t

        bol_comp[e] = bol_T(up, down)
    end
end

function bollinger_systems(width::Float64 = 2.0)
    sma_calc = SMACalculator()
    bol_calc = BollingerCalculator(width)
    return [sma_calc, bol_calc]
end

"""
    DifferenceCalculator

Computes the lag 1 differences of data values.
"""
struct DifferenceCalculator <: System end

function Overseer.update(::DifferenceCalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if T <: Difference && T.parameters[1] ∈ l
            difference(l[T.parameters[1]], c)
        end
    end
end

function difference(comp, diff_comp::AbstractComponent{diff_T}) where {diff_T<:Difference}
    for ie in length(diff_comp)+2:length(comp)
        val = comp[ie] - comp[ie-1]
        diff_comp[entity(comp, ie)] = diff_T(val)
    end
end

struct UpDownSeparator <: System end

function Overseer.update(::UpDownSeparator, l::AbstractLedger)
    for (T, c) in components(l)
        if T <: UpDown && T.parameters[1] ∈ l
            updown(l[T.parameters[1]], c)
        end
    end
end

function updown(from_comp::AbstractComponent{T},
                to_comp::AbstractComponent{ud_T}) where {T,ud_T<:UpDown}
    for e in @entities_in(from_comp)
        val = e[T]
        if val < 0
            to_comp[e] = ud_T(zero(T), val)
        else
            to_comp[e] = ud_T(val, zero(T))
        end
    end
end

"""
    RSICalculator

Calculates the [`RSI`](@ref) of values.
"""
struct RSICalculator <: System end

function Overseer.update(s::RSICalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if !(T <: RSI)
            continue
        end

        ema_T = EMA{T.parameters[1],UpDown{Difference{T.parameters[2]}}}

        if ema_T ∈ l
            rsi(l[ema_T], c)
        end
    end
end

function rsi(updown_ema, rsicomp::AbstractComponent{rsi_T}) where {rsi_T<:RSI}
    for e in @entities_in(updown_ema)
        v = value(e.ema)

        rsicomp[e] = rsi_T(rsi_T.parameters[2](100 * (1 - 1 / (1 + v[1] / abs(v[2])))))
    end
end

function rsi_systems(smoothing::Int = 2)
    ud     = UpDownSeparator()
    ud_ema = EMACalculator(smoothing)
    rsi    = RSICalculator()
    return [DifferenceCalculator(), ud, ud_ema, rsi]
end

"""
    SharpeCalculator

Calculates the bare [`Sharpe`](@ref) ratio of data.
"""
struct SharpeCalculator <: System end

function Overseer.update(s::SharpeCalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if !(T <: Sharpe)
            continue
        end

        horizon = T.parameters[1]
        comp_T  = T.parameters[2]
        sma_T   = SMA{horizon,comp_T}
        std_T   = MovingStdDev{horizon,comp_T}

        if comp_T ∈ l && sma_T ∈ l && std_T ∈ l
            sharpe(c, l[sma_T], l[std_T])
        end
    end
end

function sharpe(sharpe_comp::AbstractComponent{sharpe_T}, mean_comp,
                stddev_comp) where {sharpe_T<:Sharpe}
    for ie in length(sharpe_comp)+1:length(mean_comp)
        e = entity(mean_comp, ie)
        sharpe_comp[e] = sharpe_T(mean_comp[ie].sma / stddev_comp[ie].σ)
    end
end

function sharpe_systems()
    return [DifferenceCalculator(), SMACalculator(), MovingStdDevCalculator(),
            SharpeCalculator()]
end

"""
    LogValCalculator

Calculates the logarithms of data.
"""
struct LogValCalculator <: System end

function Overseer.update(::LogValCalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if !(T <: LogVal)
            continue
        end

        comp_T = T.parameters[1]
        if comp_T ∈ l
            log(l[comp_T], c)
        end
    end
end

function Base.log(comp::Overseer.AbstractComponent{T},
                  log_comp::Overseer.AbstractComponent{LT}) where {T,LT}
    for ie in length(log_comp)+1:length(comp)
        e = entity(comp, ie)
        log_comp[e] = LT(T(log(value(comp[ie]))))
    end
end

"""
    RelativeDifferenceCalculator

Calculates the lag 1 [`RelativeDifference`](@ref) of data.
"""
struct RelativeDifferenceCalculator <: System end

function Overseer.update(::RelativeDifferenceCalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if !(T <: RelativeDifference)
            continue
        end

        comp_T = T.parameters[1]
        if comp_T ∈ l
            relative_difference(l[comp_T], c)
        end
    end
end

function relative_difference(comp, diff_comp::AbstractComponent{T}) where {T}
    for ie in length(diff_comp)+2:length(comp)
        val = (comp[ie] - comp[ie-1]) / comp[ie-1]

        diff_comp[entity(comp, ie)] = T(val)
    end
end
