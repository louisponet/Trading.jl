function failed_order(broker, order, exc)
    t = current_time(broker)
    b = IOBuffer()
    showerror(b, exc)
    return Order(order.asset, "", uuid1(), uuid1(), t, t, t, nothing, nothing, nothing, t, 0.0,
                 0.0, "failed\n$(String(take!(b)))", order.quantity, 0.0)
end

# I don't understand why but fractional stuff is just not allowed... 
sanitize_quantity(::AlpacaBroker, ::Asset, quantity) = round(quantity, RoundDown)

"""
    submit_order(broker, order::Union{Purchase,Sale})

Submits the `order` to a `broker` for execution.
"""
function submit_order(broker::AlpacaBroker, order)
    uri = order_url(broker)
    h   = header(broker)
    try
        resp = HTTP.post(uri, h, order_body(broker, order))
        o = parse_order(broker, resp)
        o.asset = order.asset
        return o
    catch e
        if e isa HTTP.Exceptions.StatusError
            msg = JSON3.read(e.response.body)
            
            if msg[:message] == "insufficient day trading buying power"
                order.quantity = sanitize_quantity(broker, order.asset, 0.9 * order.quantity)
                return submit_order(broker, order)
                
            elseif occursin("insufficient qty available for order", msg[:message])
                m = match(r"available: (\d+)\)", msg[:message])
                
                if m !== nothing
                    order.quantity = parse(Float64, m.captures[1])
                    return submit_order(broker, order)
                end
            elseif msg[:message] == "qty must be integer"
                order.quantity = sanitize_quantity(broker, order.asset, order.quantity)
                return submit_order(broker, order)
            end

            return failed_order(broker, order, e)
        else
            rethrow()
        end
    end
end

order_side(order::EntityState{Tuple{Component{Purchase}}}) = "buy"
order_side(order::EntityState{Tuple{Component{Sale}}})     = "sell"

function submit_order(broker::HistoricalBroker, order)
    try
        p = price(broker, broker.clock.time + broker.clock.dtime, order.asset)
        max_fee = 0.005 * abs(order.quantity) * p
        fee = abs(order.quantity) *
              (p * broker.variable_transaction_fee + broker.fee_per_share) +
              broker.fixed_transaction_fee
        fee = min(fee, max_fee)
        return Order(order.asset,
                     order_side(order),
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
    catch e
        return failed_order(broker, order, e)
    end
end

function submit_order(t::Trader, e)
    return t[e] = submit_order(t.broker, e)
end

side(::AlpacaBroker, ::EntityState{Tuple{Component{Purchase}}}) = "buy"
side(::AlpacaBroker, ::EntityState{Tuple{Component{Sale}}})     = "sell"

function order_body(b::AlpacaBroker, order::EntityState)
    body = Dict("symbol"        => string(order.asset.ticker),
                "qty"           => string(order.quantity),
                "side"          => side(b, order),
                "type"          => string(order.type),
                "time_in_force" => string(order.time_in_force))
                
    if order.type == OrderType.Limit
        body["limit_price"] = string(order.price)
    end

    return JSON3.write(body)
end

function parse_order(b::AbstractBroker, resp::HTTP.Response)
    if resp.status != 200
        error("something went wrong while submitting order")
    end

    parse_body = JSON3.read(resp.body)
    return parse_order(b, parse_body)
end

function parse_order(::AlpacaBroker, parse_body::JSON3.Object)
    if parse_body[:asset_class] == "crypto"
        asset_T = AssetType.Crypto
    elseif parse_body[:asset_class] == "us_equity"
        asset_T = AssetType.Stock
    else
        asset_T = AssetType.Unknown
    end
    return Order(Asset(asset_T, parse_body[:symbol]),
                 parse_body[:side],
                 UUID(parse_body[:id]),
                 UUID(parse_body[:client_order_id]),
                 parse_body[:created_at] !== nothing ? parse_time(parse_body[:created_at]) :
                 nothing,
                 parse_body[:updated_at] !== nothing ? parse_time(parse_body[:updated_at]) :
                 nothing,
                 parse_body[:submitted_at] !== nothing ?
                 parse_time(parse_body[:submitted_at]) : nothing,
                 parse_body[:filled_at] !== nothing ? parse_time(parse_body[:filled_at]) :
                 nothing,
                 parse_body[:expired_at] !== nothing ? parse_time(parse_body[:expired_at]) :
                 nothing,
                 parse_body[:canceled_at] !== nothing ?
                 parse_time(parse_body[:canceled_at]) : nothing,
                 parse_body[:failed_at] !== nothing ? parse_time(parse_body[:failed_at]) :
                 nothing,
                 parse(Float64, parse_body[:filled_qty]),
                 parse_body[:filled_avg_price] !== nothing ?
                 parse(Float64, parse_body[:filled_avg_price]) : 0.0,
                 parse_body[:status],
                 parse(Float64, parse_body[:qty]),
                 0.0)
end

function order(broker::AlpacaBroker, id::UUID)
    resp = HTTP.get(order_url(broker, string(id)), header(broker))
    return parse_order(broker, JSON3.read(resp.body))
end

order(trader::Trader, args...) = order(trader.broker, args...)

function orders(broker::AlpacaBroker; kwargs...)
    resp = HTTP.get(URI(order_url(broker), query=Dict(kwargs)), header(broker))
    @show String(resp.body)
    return map(x->parse_order(broker, x), JSON3.read(resp.body))
end
orders(trader::Trader, args...) = orders(trader.broker, args...)

function receive_trades(b::AlpacaBroker, ws)
    msg = JSON3.read(receive(ws))
    if msg[:stream] == "trade_updates"
        return parse_order(b, msg[:data][:order])
    end
end

function receive_trades(broker::HistoricalBroker, args...)
    sleep(1)
    return nothing
end

delete_all_orders!(b::AbstractBroker) = HTTP.delete(order_url(b), header(b))
delete_all_orders!(::HistoricalBroker) = nothing
delete_all_orders!(t::Trader) = delete_all_orders!(t.broker)

ispending(b::AlpacaBroker, o::Order) =
    o.status ∈ ("new", "accepted", "held", "partially_filled")
ispending(b::HistoricalBroker, o::Order) =
    false
ispending(b::MockBroker, o::Order) =
    false
ispending(t::Trader, o::Order) = ispending(t.broker, o)

function subscribe_orderbook(::AlpacaBroker, asset::Asset, ws::WebSocket)
    if asset.type == AssetType.Stock
        return
    else
        return send(ws, JSON3.write(Dict("action" => "subscribe",
                                         "orderbooks" => [asset.ticker])))
    end
end

subscribe_orderbook(::HistoricalBroker, args...) = nothing

function orderbook(::AlpacaBroker, msg)
    bids = Tuple{String, Tuple{DateTime, Bid}}[]
    asks = Tuple{String, Tuple{DateTime, Ask}}[]
    for m in msg
        
        m[:T] != "o" && continue
        
        asset = m[:S]
        time = parse_time(m[:t])
        
        for bid in m[:b]
            bid[:s] == 0 && continue
            push!(bids, (asset, (time, Bid(bid[:p], bid[:s]))))
        end
        
        for ask in m[:a]
            ask[:s] == 0 && continue
            push!(asks, (asset, (time, Ask(ask[:p], ask[:s]))))
        end
    end

    return (bids = bids, asks=asks)
end

