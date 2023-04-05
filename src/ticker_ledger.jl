"""
    TickerLedger

A `TickerLedger` holds the data for a given `ticker` as it arrives. Currently this is bar data in the form of
[`Open`](@ref), [`High`](@ref), [`Low`](@ref), [`Close`](@ref) and [`Volume`](@ref), produced by a [`BarStream`](@ref).
If certain derived [`Indicator`](@ref Indicators) data is requested, it also holds this as it is produced by the different systems.
"""
mutable struct TickerLedger <: AbstractLedger
    ticker::String
    l::Ledger
end 

TickerLedger(ticker::String) = TickerLedger(ticker, Ledger())
Overseer.ledger(d::TickerLedger) = d.l
