struct SMACalculator <: System
    horizon::Int
end

function Overseer.update(s::SMACalculator, l::AbstractLedger)
    for (d, es) in pools(l[Dataset])
        if length(es) == 1
            continue
        end
        for c in components(l)
            if trait(Indicator, first(c)) isa Positive
                sma_T = SMA{s.horizon, first(c)}
                Overseer.ensure_component!(l, sma_T)
                sma_comp = l[sma_T]
                sma(last(c), sma_comp, es)
            end
        end
    end
end
function sma(comp, sma_comp, es)
    if isempty(comp) || es[end] in sma_comp
        return
    end
    m = zero(comp[1])
    sma_T = eltype(sma_comp)
    horizon = sma_T.parameters[1]
    
    for (i, e) in enumerate(es)
        if e in sma_comp
            continue
        end
        @inbounds val = comp[e]
        m += val
        if i >= horizon
            sma_comp[e] = sma_T(m / horizon)
            m -= @inbounds comp[es[i - horizon + 1]]
        end
    end
end
sma(::IsNot{Indicator}, args...) = nothing

Base.@kwdef struct EMACalculator <: System
    horizon::Int
    smoothing::Int = 2
end
EMACalculator(horizon::Int; kwargs...) = EMACalculator(horizon=horizon;kwargs...)

function Overseer.update(s::EMACalculator, l::AbstractLedger)
    for (d, es) in pools(l[Dataset])
        if length(es) == 1
            continue
        end
        for c in components(l)
            if trait(Indicator, first(c)) isa Positive
                ema_T = EMA{s.horizon, first(c)}
                Overseer.ensure_component!(l, ema_T)
                ema_comp = l[ema_T]
                ema(last(c), ema_comp, es, s.smoothing)
            end
        end
    end
end

function ema(comp, ema_comp, entities, smoothing)
    if isempty(comp) || entities[end] in ema_comp
        return
    end
    m = zero(comp[1])
    ema_T = eltype(ema_comp)
    horizon = ema_T.parameters[1]
    
    fac = smoothing/(1 + horizon)
    for (i, e) in enumerate(entities)
        if e in ema_comp
            continue
        end
        @inbounds val = comp[e]
        if i < horizon
            m += val
        elseif i == horizon
            m += val
            m /= horizon
        else
            m = val * fac + m * (1 - fac) 
            ema_comp[e] = ema_T(m)
        end
    end
end

Base.@kwdef struct BollingerCalculator
    width::Float64 = 2.0
end

function Overseer.update(s::BollingerCalculator, l::AbstractLedger)
    # We need the sma for bollinger bands so we first ensure it is
    # created.
    for (d, es) in pools(l[Dataset])
        if length(es) == 1
            continue
        end
        for c in components(l)
            if first(c) <: SMA
                bol_T = Bollinger{first(c).parameters...}
                Overseer.ensure_component!(l, bol_T)
                bol_comp = l[bol_T]
                comp = l[first(c).parameters[2]]
                bollinger(comp, last(c), bol_comp, es, s.width)
            end
        end
    end
end

function bollinger(comp, sma_comp, bol_comp, es, width)
    if isempty(comp) || es[end] in bol_comp
        return
    end
    stdev = zero(comp[1])
    sma_T = eltype(sma_comp)
    horizon = sma_T.parameters[1]
    fac = width * sqrt((horizon - 1)/horizon)

    
    for ie in horizon:length(es)
        e = es[ie]
        if e in bol_comp
            continue
        end
            
        stdev = zero(stdev)
        s = e.sma
        for i = ie - horizon + 1:ie
            stdev += (@inbounds comp[es[i]] - s)^2
        end
        stdev = sqrt(stdev/(horizon - 1))
        t = stdev * fac
        up   = s + t
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
    for (d,es) in pools(l[Dataset])
        if length(es) == 1
            continue
        end
        for c in components(l)
            if !(first(c) <: Difference || first(c) <: UpDown) && trait(Indicator, first(c)) isa Positive
                diff_T = Difference{first(c)}
                Overseer.ensure_component!(l, diff_T)
                diff_comp = l[diff_T]
                difference(last(c), diff_comp, es)
            end
        end
    end
end
    
function difference(comp, diff_comp, es)
    for ie in 2:length(es)
        e = es[ie]
        if !(e in diff_comp)
            prev_e = es[ie - 1]
            @inbounds val = comp[e] - comp[prev_e]
            diff_comp[e] = eltype(diff_comp)(val)
        end
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
        if !(e in to_comp)
            if e.d < 0
                to_comp[e] = eltype(to_comp)(zero(e.d), e.d)
            else
                to_comp[e] = eltype(to_comp)(e.d, zero(e.d))
            end
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

# function rsi_stage(valfunc::Function = x -> x.close;
#                    name::Symbol         = :rsi,
#                    in::DataType         = Bar,
#                    updown::DataType     = UpDown,
#                    updown_ema::DataType = EMA{2},
#                    out::DataType        = RSI,
#                    horizon::Int         = 14,
#                    smoothing::Int       = 2)


#     ud     = UpDownCalculator(TransformRule(valfunc, (in,), (updown,)))
#     ud_ema = EMACalculator(TransformRule(x -> (x.up, x.down), (updown,), (updown_ema, )), horizon, smoothing)
#     rsi    = RSICalculator(TransformRule(x -> nothing, (updown_ema, ), (out,))) 
#     return Stage(name, [ud, ud_ema, rsi])
# end
                   
