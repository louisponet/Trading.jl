"""
    TickerLedger

Represents the tick data of a given `ticker`. A `TickerLedger` can be attached to a [`DataPipeline`](@ref) with [`attach!`](@ref), which will cause data to flow in as soon as it is available.
"""
mutable struct TickerLedger <: AbstractLedger
    ticker::String
    l::Ledger
end 

TickerLedger(ticker::String) = TickerLedger(ticker, Ledger())
Overseer.ledger(d::TickerLedger) = d.l
