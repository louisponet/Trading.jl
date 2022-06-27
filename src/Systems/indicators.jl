struct SMACalculator{horizon} <: System
end

function Overseer.update(s::SMACalculator{horizon}, l::AbstractLedger) where {horizon}
    for d in l[Dataset]
        if d.first_e == Entity(0)
            continue
        end
        for c in components(l)
            if trait(Indicator, first(c)) isa Positive
                sma_T = SMA{eltype(last(c)), horizon}
                Overseer.ensure_component!(l, sma_T)
                sma_comp = l[sma_T]
                sma(last(c), sma_comp, d.first_e.id, d.last_e.id)
            end
        end
    end
end
function sma(comp, sma_comp, firstid, lastid)
    if isempty(comp)
        return
    end
    m = zero(comp[1])
    horizon = eltype(sma_comp).parameters[2]
    
    for ie in firstid:lastid
        e = Entity(ie)
        if e in sma_comp
            continue
        end
        @inbounds val = comp[e]
        m += val
        if ie - horizon >= 0
            sma_comp[e] = eltype(sma_comp)(m / horizon)
            m -= @inbounds comp[Entity(ie - horizon + 1)]
        end
    end
end
sma(::IsNot{Indicator}, args...) = nothing

# Base.@kwdef struct EMACalculator
#     horizon::Int
#     smoothing::Int = 2
# end

# function Overseer.update(s::EMACalculator, l::AbstractLedger)
#     Overseer.ensure_component!(l, to_types(s)[1])
#     ema_comp = l[to_types(s)[1]]
#     from_comp = l[from_types(s)[1]]
#     for d in l[Dataset]
#         if d.first_e == Entity(0)
#             continue
#         end
#         ema(s.rule.valfunc, from_comp, ema_comp, d.first_e.id, d.last_e.id, s.horizon, s.smoothing)
#     end
# end

# function ema(valfunc, l, ema_comp::Overseer.AbstractComponent{T}, firstid, lastid, horizon, smoothing) where {T}
#     em = zeros(T.parameters[1])
#     fac = smoothing/(1 + horizon)
#     for (i, ie) in enumerate(firstid:lastid)
#         e = Entity(ie)
#         @inbounds val = valfunc(l[e])
#         if !(e in ema_comp)
#             if i < horizon
#                 em .+= val
#             elseif i == horizon
#                 em .+= val
#                 em ./= horizon
#             else
#                 em .= val .* fac .+ em .* (1 - fac) 
#                 ema_comp[e] = T(em)
#             end
#         end
#     end
# end

# function ema_stage(valfunc::Function = x -> x.close;
#                     name::Symbol  = :ema,
#                     horizon::Int  = 20,
#                     smoothing::Int = 2,
#                     in::DataType  = Bar,
#                     out::DataType = EMA{1})
#     return Stage(name, [EMACalculator(TransformRule(valfunc, (in,), (out,)), horizon, smoothing)])
# end

# Base.@kwdef struct BollingerCalculator{R} <: AbstractCalculator{R}
#     rule::R
#     horizon::Int
#     width::Float64 = 2.0
# end

# function Overseer.update(s::BollingerCalculator, l::AbstractLedger)
#     # We need the sma for bollinger bands so we first ensure it is
#     # created.
#     bar_comp = l[from_types(s)[1]]
#     sma_comp = l[from_types(s)[2]]
#     bol_comp = l[to_types(s)[1]]

#     bollinger(s.rule.valfunc, bar_comp, sma_comp, bol_comp, s.horizon, s.width)
# end

# function bollinger(valfunc, bar_comp, sma_comp::Overseer.AbstractComponent{T}, bol_comp, horizon, width) where {T}
#     fac = width * sqrt((horizon - 1)/horizon)
#     N = T.parameters[1]
    
#     # caches
    
#     stdev = zeros(N)
#     for e in @entities_in(sma_comp)
#         fill!(stdev, 0)
#         for i = e.e.id - horizon + 1:e.e.id
#             stdev .+= (@inbounds valfunc(bar_comp[Entity(i)]) .- e.sma).^2
#         end
#         stdev .= sqrt.(stdev./(horizon - 1))
#         up   = e.sma .+ stdev .* fac
#         down = e.sma .- stdev .* fac

#         bol_comp[e] = eltype(bol_comp)(up, down)
#     end
# end

# function bollinger_stage(valfunc::Function = x -> x.close;
#                          name::Symbol = :bollinger,
#                          in::DataType   = Bar,
#                          out::DataType  = Bollinger{1},
#                          sma::DataType  = SMA{1},
#                          horizon::Int   = 20,
#                          width::Float64 = 2.0)
#     sma_calc = SMACalculator(TransformRule(valfunc, (in,), (sma, )), horizon)
#     bol_calc = BollingerCalculator(TransformRule(valfunc, (in, sma), (out,)), width)
#     return Stage(name, [sma_calc, bol_calc])
# end

# struct UpDownCalculator{R} <: AbstractCalculator{R}
#     rule::R
# end
    
# function Overseer.update(s::UpDownCalculator, l::AbstractLedger)
#     tocomp = l[to_types(s)[1]]
#     fromcomp = l[from_types(s)[1]]
    
#     for d in l[Dataset]
#         if d.first_e == Entity(0)
#             continue
#         end
#         updown(s.rule.valfunc, fromcomp, tocomp, d.first_e.id, d.last_e.id,)
#     end
# end
    
# function updown(valfunc, fromcomp, tocomp, firstid, lastid)
#     for ie in firstid + 1:lastid
#         e = Entity(ie)
#         # if !(e in tocomp)
#             prev_e = Entity(ie - 1)
#             @inbounds val = valfunc(fromcomp[e]) - valfunc(fromcomp[prev_e])
#             if val < 0
#                 tocomp[e] = eltype(tocomp)(0, val)
#             else
#                 tocomp[e] = eltype(tocomp)(val, 0)
#             end
#         # end
#     end
# end

# function Overseer.update(s::UpDownCalculator, l::AbstractLedger, storefunc)
#     tocomp = l[to_types(s)[1]]
#     fromcomp = l[from_types(s)[1]]
    
#     for d in l[Dataset]
#         if d.first_e == Entity(0)
#             continue
#         end
#         updown(s.rule.valfunc, fromcomp, tocomp, d.first_e.id, d.last_e.id,storefunc, l)
#     end
# end
    
# function updown(valfunc, fromcomp, tocomp, firstid, lastid, storefunc, l)
#     ct = typeof(storefunc(0, 2))
#     comp = l[ct]
#     for ie in firstid + 1:lastid
#         e = Entity(ie)
#         # if !(e in tocomp)
#             prev_e = Entity(ie - 1)
#             @inbounds val = valfunc(fromcomp[e]) - valfunc(fromcomp[prev_e])
#             if val < 0
#                 comp[e] = storefunc(0, val)
#             else
#                 comp[e] = storefunc(val, 0)
#             end
#         # end
#     end
# end

# Base.@kwdef struct RSICalculator{R} <: AbstractCalculator{R}
#     rule::R
# end

# function Overseer.update(s::RSICalculator, l::AbstractLedger)
#     # We need the sma for bollinger bands so we first ensure it is
#     # created.
#     updown_ema = l[from_types(s)[1]]
#     rsicomp    =  l[to_types(s)[1]]

#     rsi(updown_ema, rsicomp)
# end

# function rsi(updown_ema, rsicomp)
#     for e in @entities_in(updown_ema)
#         rsicomp[e] = eltype(rsicomp)(100 * ( 1 - 1 / ( 1 + e.ema[1] / abs(e.ema[2]))))
#     end
# end

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
                   
