# TODO move away from DataSets
struct SMACalculator <: System
    horizon::Int
end

function Overseer.update(s::SMACalculator, l::AbstractLedger)
    @sync for c in components(l)
        if trait(Indicator, first(c)) isa Positive
            sma_T = SMA{s.horizon, first(c)}
            Overseer.ensure_component!(l, sma_T)
            sma_comp = l[sma_T]
            # Threads.@spawn begin
                sma(last(c), sma_comp)
            # end
        end
    end
end
function sma(comp, sma_comp)
    sma_T = eltype(sma_comp)
    horizon = sma_T.parameters[1]
    startid = length(sma_comp)+1

    if startid+horizon-1 > length(comp)
        return
    end

    m = sum(i -> comp[i], startid:length(sma_comp) + horizon-1)
    
    for i in startid+horizon-1:length(comp)
        m += comp[i]
        sma_comp[entity(comp, i)] = sma_T(m / horizon)
        m -= comp[i - horizon + 1]
    end
end
sma(::IsNot{Indicator}, args...) = nothing

struct MovingStdDevCalculator <: System
    horizon::Int
end

function Overseer.update(s::MovingStdDevCalculator, l::AbstractLedger)
    @sync for c in components(l)
        if trait(Indicator, first(c)) isa Positive
            stdev_T = MovingStdDev{s.horizon, first(c)}
            Overseer.ensure_component!(l, stdev_T)
            stdev_comp = l[stdev_T]
            # Threads.@spawn begin
                stdev(last(c), stdev_comp)
            # end
        end
    end
end

function stdev(comp, stdev_comp)
    stdev_T = eltype(stdev_comp)
    horizon = stdev_T.parameters[1]
    startid = length(stdev_comp)+1

    if startid+horizon-1 > length(comp)
        return
    end
    
    m  = sum(i -> comp[i], startid:length(stdev_comp) + horizon-1)
    m² = sum(i -> comp[i]^2, startid:length(stdev_comp) + horizon-1)

    for i in startid+horizon-1:length(comp)
        val = comp[i]
        m  += val
        m² += val^2
        t = (m² - m^2/horizon) / horizon
         
        stdev_comp[entity(comp, i)] = t < 0 ? stdev_T(zero(comp[1])) : stdev_T(sqrt(t))
            #TODO BAD
        m  -= comp[i - horizon + 1]
        m² -= comp[i - horizon + 1]^2
    end
end
stdev(::IsNot{Indicator}, args...) = nothing


Base.@kwdef struct EMACalculator <: System
    horizon::Int
    smoothing::Int = 2
end
EMACalculator(horizon::Int; kwargs...) = EMACalculator(horizon=horizon;kwargs...)

function Overseer.update(s::EMACalculator, l::AbstractLedger)
    for c in components(l)
        if trait(Indicator, first(c)) isa Positive
            ema_T = EMA{s.horizon, first(c)}
            Overseer.ensure_component!(l, ema_T)
            ema_comp = l[ema_T]
            ema(last(c), ema_comp, s.smoothing)
        end
    end
end

function ema(comp, ema_comp,smoothing)
    ema_T = eltype(ema_comp)
    horizon = ema_T.parameters[1]
    if isempty(comp)
        return
    end
    m = zero(comp[1])
    
    fac = smoothing/(1 + horizon)
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

Base.@kwdef struct BollingerCalculator <: System
    width::Float64 = 2.0
end

function Overseer.update(s::BollingerCalculator, l::AbstractLedger)
    # We need the sma for bollinger bands so we first ensure it is
    # created.
    @sync for c in components(l)
        if first(c) <: SMA
            bol_T = Bollinger{first(c).parameters...}
            Overseer.ensure_component!(l, bol_T)
            bol_comp = l[bol_T]
            comp = l[first(c).parameters[2]]
            if isempty(comp)
                continue
            end
            if value(comp[1]) isa Tuple
                continue
            end
            # Threads.@spawn begin
                bollinger(comp, last(c), bol_comp, s.width)
            # end
        end
    end
end

#TODO FIX
function bollinger(comp, sma_comp, bol_comp, width)
    stdev = zero(comp[1])
    sma_T = eltype(sma_comp)
    horizon = sma_T.parameters[1]
    
    startid = length(bol_comp)+1

    if startid+horizon-1 > length(comp)
        return
    end
    
    fac = width * sqrt((horizon - 1)/horizon)

    for ie in startid+horizon-1:length(comp)
        e = entity(comp, ie) 
        if e ∉ sma_comp
            continue
        end
        stdev = zero(stdev)
        s = sma_comp[e].sma
        for i = ie - horizon + 1:ie
            stdev += (comp[ie] - s)^2
        end
        stdev = sqrt(stdev/(horizon - 1))
        t = stdev * fac
        up = s + t
        down = s - t

        bol_comp[e] = eltype(bol_comp)(up, down)
    end
end

function bollinger_stage(;
                         name::Symbol = :bollinger,
                         horizon::Int   = 20,
                         width::Float64 = 2.0)
    sma_calc = SMACalculator(horizon)
    bol_calc = BollingerCalculator(width)
    return Stage(name, [sma_calc, bol_calc])
end

struct DifferenceCalculator <: System end
    
function Overseer.update(::DifferenceCalculator, l::AbstractLedger)
    for c in components(l)
        if !(first(c) <: Difference || first(c) <: UpDown) && trait(Indicator, first(c)) isa Positive
            diff_T = Difference{first(c)}
            Overseer.ensure_component!(l, diff_T)
            diff_comp = l[diff_T]
            difference(last(c), diff_comp)
        end
    end
end
    
function difference(comp, diff_comp)
    for ie in length(diff_comp)+2:length(comp)
        val = comp[ie] - comp[ie-1]
        diff_comp[entity(comp, ie)] = eltype(diff_comp)(val)
    end
end

struct UpDownSeparator <: System end
    
function Overseer.update(::UpDownSeparator, l::AbstractLedger)
    for (T, comp) in components(l)
        if T <: Difference
            ud_T = UpDown{eltype(comp).parameters[1]}
            Overseer.ensure_component!(l, ud_T)
            updown(comp, l[ud_T])
        end
    end
end

function updown(from_comp, to_comp)
    for e in @entities_in(from_comp)
        if e.d < 0
            to_comp[e] = eltype(to_comp)(zero(e.d), e.d)
        else
            to_comp[e] = eltype(to_comp)(e.d, zero(e.d))
        end
    end
end
                    
struct RSICalculator <: System
    horizon::Int
end

function Overseer.update(s::RSICalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if T <: EMA && T.parameters[2] <: UpDown 
            rsi_T = RSI{s.horizon, T.parameters[2].parameters[1]}
            Overseer.ensure_component!(l, rsi_T)
            rsi(c, l[rsi_T])
        end
    end
end

function rsi(updown_ema, rsicomp)
    for e in @entities_in(updown_ema)
        v = value(e.ema)
        rsicomp[e] = eltype(rsicomp)(eltype(rsicomp).parameters[2](100 * ( 1 - 1 / ( 1 + v[1] / abs(v[2])))))
    end
end

function rsi_stage(horizon::Int         = 14,
                   smoothing::Int       = 2)

    ud     = UpDownSeparator()
    ud_ema = EMACalculator(horizon, smoothing)
    rsi    = RSICalculator(horizon) 
    return Stage(:rsi, [DifferenceCalculator(),ud, ud_ema, rsi])
end

struct SharpeCalculator <: System end

function Overseer.update(s::SharpeCalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if T <: SMA
            horizon = T.parameters[1]
            stdev_T = MovingStdDev{horizon, T.parameters[2]}
            if stdev_T ∈ l
                sharpe_T = Sharpe{horizon, T.parameters[2]}
                Overseer.ensure_component!(l, sharpe_T)
                sharpe(l[sharpe_T], c, l[stdev_T])
            end
        end
    end
end

function sharpe(sharpe_comp, mean_comp, stddev_comp)
    sharpe_T = eltype(sharpe_comp)
    for e in @entities_in(mean_comp && stddev_comp)
        sharpe_comp[e] = sharpe_T(e.sma / e.σ)
    end
end

function sharpe_stage(width)
    return Stage(:sharpe, [DifferenceCalculator(), SMACalculator(width), MovingStdDevCalculator(width), SharpeCalculator()])
end

struct LogValCalculator <: System end

function Overseer.update(::LogValCalculator, l::AbstractLedger)
    for (T, c) in components(l)
        if !(T <: LogVal) && !(T <: Difference) && !(T <: RelativeDifference) && trait(Indicator, T) isa Positive
            log_T = LogVal{T}
            Overseer.ensure_component!(l, log_T)
            log_comp = l[log_T]
            # Threads.@spawn begin
                log(c, log_comp)
            # end
        end
    end
end

function Base.log(comp::Overseer.AbstractComponent{T}, log_comp::Overseer.AbstractComponent{LT}) where {T, LT}
    for e in @entities_in(comp)
        log_comp[e] = LT(T(log(value(e[T]))))
    end
end

struct RelativeDifferenceCalculator <: System end
    
function Overseer.update(::RelativeDifferenceCalculator, l::AbstractLedger)
    for c in components(l)
        if !(first(c) <: RelativeDifference || first(c) <: UpDown) && trait(Indicator, first(c)) isa Positive
            diff_T = RelativeDifference{first(c)}
            Overseer.ensure_component!(l, diff_T)
            diff_comp = l[diff_T]
            relative_difference(last(c), diff_comp)
        end
    end
end
    
function relative_difference(comp, diff_comp)
    for ie in length(diff_comp)+2:length(comp)
        val = (comp[ie] - comp[ie-1])/comp[ie-1]
        diff_comp[entity(comp, ie)] = eltype(diff_comp)(val)
    end
end
