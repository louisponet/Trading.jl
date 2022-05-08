struct TransformRule{FT, TT, F<:Function}
    valfunc::F
    from_type::Type{FT}
    to_type::Type{TT}
end

from_type(::Type{TransformRule{FT}}) where {FT} = FT
to_type(::Type{TransformRule{FT, TT}}) where {FT, TT} = TT

abstract type AbstractIndicator{R<:TransformRule} <: System end

Overseer.requested_components(::AbstractIndicator{R}) where {R} = (R.parameters[1], R.parameters[2])

from_type(::AbstractIndicator{R}) where {R} = from_type(R)
to_type(::AbstractIndicator{R}) where {R} = to_type(R)

struct SMAIndicator{R} <: AbstractIndicator{R}
    rule::R 
    horizon::Int
end

function Overseer.update(s::SMAIndicator, l::AbstractLedger)
    Overseer.ensure_component!(l, to_type(s))
    sma_comp = l[to_type(s)]
    from_comp = l[from_type(s)]
    for d in l[Dataset]
        if d.first_e == Entity(0)
            continue
        end
        sma(s.rule.valfunc, from_comp, sma_comp, d.first_e.id, d.last_e.id, s.horizon)
    end
end
function sma(valfunc, l, sma_comp::Overseer.AbstractComponent{T}, firstid, lastid, horizon) where {T}
    m = 0.0
    for (i, ie) in enumerate(firstid:lastid)
        e = Entity(ie)
        @inbounds val = valfunc(l[e])
        if !(e in sma_comp) 
            m += val
            if i >= horizon
                sma_comp[e] = T(m/horizon)
                first_bar = l[i - horizon + 1]
                m -= valfunc(first_bar)
            end
        end
    end
end

Base.@kwdef struct EMAIndicator{R} <: AbstractIndicator{R}
    rule::R
    horizon::Int
    smoothing::Int = 2
end

function Overseer.update(s::EMAIndicator, l::AbstractLedger)
    Overseer.ensure_component!(l, to_type(s))
    ema_comp = l[to_type(s)]
    from_comp = l[from_type(s)]
    for d in l[Dataset]
        if d.first_e == Entity(0)
            continue
        end
        ema(s.rule.valfunc, from_comp, ema_comp, d.first_e.id, d.last_e.id, s.horizon, s.smoothing)
    end
end

function ema(valfunc, l, ema_comp::Overseer.AbstractComponent{T}, firstid, lastid, horizon, smoothing) where {T}
    em = 0.0
    fac = smoothing/(1 + horizon)
    for (i, ie) in enumerate(firstid:lastid)
        e = Entity(ie)
        @inbounds val = valfunc(l[e])
        if !(e in ema_comp)
            if i < horizon
                em += val
            elseif i == horizon
                em += val
                em /= horizon
            else
                em = val * fac + em * (1 - fac) 
                ema_comp[e] = T(em)
            end
        end
    end
end

Base.@kwdef struct BollingerIndicator{R} <: AbstractIndicator{R}
    rule::R
    horizon::Int
    width::Float64 = 2.0
end

function Overseer.update(s::BollingerIndicator, l::AbstractLedger)

    # We need the sma for bollinger bands so we first ensure it is
    # created.
    smasys = SMAIndicator(s.rule, s.horizon)
    update(smasys, l)

    Overseer.ensure_component!(l, to_type(s))
    
    b_comp   = l[Bollinger{horizon}]
    sma_comp = l[SMA{horizon}]
    bar_comp = l[Bar]

    fac = sqrt((horizon - 1)/horizon)

    for e in @entities_in(sma_comp)
        stdev = 0.0
        for i = e.e.id - horizon + 1:e.e.id
            stdev += (bar_comp[Entity(i)].close - e.sma)^2
        end
        stdev = sqrt(stdev/(horizon - 1))

        up = e.sma + stdev * s.width * fac
        down = e.sma - stdev * s.width * fac
        l[e] = Bollinger{horizon}(up, down)
    end
end

