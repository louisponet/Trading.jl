trades(broker::AbstractBroker) = broker.cache.trades_data 
trades(broker::AbstractBroker, ticker, args...; kwargs...) = 
    retrieve_data(broker, trades(broker), ticker, args...; section="trades", kwargs...)

function failed_order(broker, order)
    t = current_time(broker)
    return Order(order.ticker, uuid1(), uuid1(), t, t, t, nothing, nothing, nothing, t, 0.0, 0.0, "failed", order.quantity, 0.0)
end

side(::AlpacaBroker, ::EntityState{Tuple{Component{Purchase}}}) = "buy"
side(::AlpacaBroker, ::EntityState{Tuple{Component{Sale}}})     = "sell"

function order_body(b::AlpacaBroker, order::EntityState)
    body = Dict("symbol" => string(order.ticker),
                "qty"           => string(order.quantity),
                "side"          => side(b, order),
                "type"          => string(order.type),
                "time_in_force" => string(order.time_in_force))
    
    if order.type == OrderType.Limit
        body["limit_price"] = string(order.price)
    end
    
    return JSON3.write(body)    
end

function parse_order(b::AlpacaBroker, resp::HTTP.Response)
    
    if resp.status != 200
        error("something went wrong while submitting order")
    end

    parse_body = JSON3.read(resp.body)
    return parse_order(b, parse_body)
end

function parse_order(::AlpacaBroker, parse_body)
    return Order(parse_body[:symbol],
                 UUID(parse_body[:id]),
                 UUID(parse_body[:client_order_id]),
                 parse_body[:created_at]   !== nothing ? TimeDate(parse_body[:created_at][1:end-1])   : nothing,
                 parse_body[:updated_at]   !== nothing ? TimeDate(parse_body[:updated_at][1:end-1])   : nothing,
                 parse_body[:submitted_at] !== nothing ? TimeDate(parse_body[:submitted_at][1:end-1]) : nothing,
                 parse_body[:filled_at]    !== nothing ? TimeDate(parse_body[:filled_at][1:end-1])    : nothing,
                 parse_body[:expired_at]   !== nothing ? TimeDate(parse_body[:expired_at][1:end-1])   : nothing,
                 parse_body[:canceled_at]  !== nothing ? TimeDate(parse_body[:canceled_at][1:end-1])  : nothing,
                 parse_body[:failed_at]    !== nothing ? TimeDate(parse_body[:failed_at][1:end-1])    : nothing,
                 parse(Float64, parse_body[:filled_qty]),
                 parse_body[:filled_avg_price] !== nothing ? parse(Float64, parse_body[:filled_avg_price]) : 0.0,
                 parse_body[:status],
                 parse(Float64,parse_body[:qty]),
                 0.0)
end

function receive_order(b::AlpacaBroker, ws)
    msg = JSON3.read(receive(ws))
    if msg[:stream] == "trade_updates" && msg[:data][:event] == "fill"
        return parse_order(b, msg[:data][:order])
    end
end

function receive_order(broker::HistoricalBroker, args...)
    sleep(1)
    return nothing
end

function submit_order(broker::AlpacaBroker, order)
    uri  = order_url(broker)
    h    = header(broker)
    try
        resp = HTTP.post(uri, h, order_body(broker, order))
        return parse_order(broker, resp)
    catch e
        if e isa HTTP.Exceptions.StatusError
            return failed_order(broker, order)
        else
            rethrow()
        end
    end
end

function submit_order(broker::HistoricalBroker, order::T) where {T}
    try
        p = price(broker, broker.clock.time + broker.clock.dtime, order.ticker)
        max_fee = 0.005 * abs(order.quantity) * p
        fee = abs(order.quantity) * (p * broker.variable_transaction_fee + broker.fee_per_share) + broker.fixed_transaction_fee
        fee = min(fee, max_fee)
        return Order(order.ticker,
                     uuid1(),
                     uuid1(),
                     current_time(broker),
                     current_time(broker),
                     current_time(broker),
                     current_time(broker),
                     nothing,
                     nothing,
                     nothing,
                     order.quantity,
                     p,
                     "filled",
                     order.quantity,
                     fee)
    catch
        return failed_order(broker, order)
    end
end

function submit_order(t::Trader, e)
    t[e] = submit_order(t.broker, e)
end

delete_all_orders!(b::AbstractBroker) = HTTP.delete(order_url(b), header(b))
delete_all_orders!(::HistoricalBroker) = nothing
delete_all_orders!(t::Trader) = delete_all_orders!(t.broker)

"""
    OrderLink

Interface to support executing trades and retrieving account updates.
"""
Base.@kwdef struct OrderLink{B <: AbstractBroker}
    broker::B
    ws::Union{Nothing, WebSocket} = nothing
end

OrderLink(b::AbstractBroker; kwargs...) = OrderLink(;broker=b, kwargs...)

HTTP.receive(order_link::OrderLink) = receive_order(order_link.broker, order_link.ws)

function order_link(f::Function, broker::AlpacaBroker)
    HTTP.open(trading_stream_url(broker)) do ws
        if !authenticate_trading(broker, ws)
            error("couldn't authenticate")
        end
        @info "Authenticated trading"
        send(ws, JSON3.write(Dict("action" => "listen",
                                  "data"  => Dict("streams" => ["trade_updates"]))))
        try
            f(OrderLink(broker, ws))
        catch e
            showerror(stdout, e, catch_backtrace())
            if !(e isa InterruptException)
                rethrow(e)
            end
        end
    end
end

order_link(f::Function, broker::HistoricalBroker) = f(OrderLink(broker, nothing))

