abstract type AbstractTrader <: AbstractLedger end

function current_position(t::AbstractLedger, ticker::String)
    pos_id = findfirst(x->x.ticker == ticker, t[Position])
    pos_id === nothing && return 0.0
    return t[Position][pos_id].quantity
end
