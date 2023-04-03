"""
   HistoricalBroker

Stores and provides data from historical datasets. Data can be streamed fashion by assigning a
[`Clock`](@ref) to the `clock` constructor kwarg, which will be used to determine the next bar to
stream when calling `receive` on this broker.
"""
Base.@kwdef mutable struct HistoricalBroker{B <: AbstractBroker} <: AbstractBroker
    broker::B
    cache::DataCache = DataCache()
    clock::Clock = Clock(current_time(), Millisecond(1))
    last::TimeDate = TimeDate(0)
    cash::Float64 = 100000.0
    send_bars::Base.Event = Base.Event()
    variable_transaction_fee::Float64 = 0.0
    fee_per_share::Float64 = 0.0
    fixed_transaction_fee::Float64 = 0.0
end

HistoricalBroker(b::AbstractBroker; kwargs...)  = HistoricalBroker(; broker=b, kwargs...)
broker(b::HistoricalBroker) = b.broker
