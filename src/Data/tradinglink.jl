"""
    TradingLink

Interface to support executing trades and retrieving account updates.
"""
Base.@kwdef struct TradingLink{B <: AbstractBroker}
    broker::B
    ws::Union{Nothing, WebSocket} = nothing
end

TradingLink(b::AbstractBroker; kwargs...) = TradingLink(;broker=b, kwargs...)

HTTP.receive(trading_link::TradingLink) = receive_order(trading_link.broker, trading_link.ws)

