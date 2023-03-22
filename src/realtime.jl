mutable struct RealtimeTrader <: AbstractTrader
    l::Ledger
    loop::Union{Task, Nothing}
    account::AccountInfo
    ticker_ledgers::Dict{String, Ledger}
    stop::Bool
end

Overseer.ledger(t::RealtimeTrader) = t.l

function RealtimeTrader(account::AccountInfo, ticker_ledgers::Dict{String, Ledger})
    core_stage = Stage(:main, [Purchaser(), Seller(), Filler(), SnapShotter()])
    l = Ledger(core_stage)
    
    # TODO BAD
    Entity(l, Trading.Dataset("Portfolio", "1Min", TimeDate(now())))
    return RealtimeTrader(l, nothing, account, ticker_ledgers, false)
end

function authenticate_trading(ws, t::RealtimeTrader)
    send(ws, JSON3.write(Dict("action" => "auth",
                              "key"    => t.account.key_id,
                              "secret" => t.account.secret_key)))
    reply = receive(ws)
    try
        return JSON3.read(reply)["data"]["status"] == "authorized"
    catch
        return false
    end
end
function authenticate_data(ws, t::RealtimeTrader)
    send(ws, JSON3.write(Dict("action" => "auth",
                              "key"    => t.account.key_id,
                              "secret" => t.account.secret_key)))
    reply = receive(ws)
    try
        return JSON3.read(reply)[1][:T] == "success"
    catch
        return false
    end
end

function subscribe_tickers(ws, tickers)
    send(ws, JSON3.write(Dict("action" => "subscribe",
                              "bars"  => collect(keys(tickers)))))
end

function delete_all_orders!(t::RealtimeTrader)
    HTTP.delete(URI(PAPER_TRADING_URL, path="/v2/orders"), header(t.account))
end

function start(trader::RealtimeTrader)
    
    resp = HTTP.get(URI(PAPER_TRADING_URL, path="/v2/account"), Trading.header(trader.account))

    if resp.status != 200
        return error("Couldn't get Account details")
    end

    acc_parse = JSON3.read(resp.body)
    Entity(trader, Cash(parse(Float64, acc_parse[:cash])))

    resp = HTTP.get(URI(PAPER_TRADING_URL, path="/v2/positions"), Trading.header(trader.account))
    if resp.status != 200
        return error("Couldn't get position details")
    end

    pos_parse = JSON3.read(resp.body)
    for position in pos_parse
        Entity(trader, Position(position[:symbol], parse(Float64, position[:qty])))
    end
    
    trading_task = Threads.@spawn begin
        t = @task begin
            try
                HTTP.open(TRADING_STREAM_PAPER) do ws
        
                    if !authenticate_trading(ws, trader)
                        error("couldn't authenticate")
                    end
                    send(ws, JSON3.write(Dict("action" => "listen",
                                              "data"  => Dict("streams" => ["trade_updates"]))))

                    for raw_msg in ws 
                        msg = JSON3.read(raw_msg)
                        if msg[:stream] == "trade_updates" && msg[:data][:event] == "fill"
                            order_update!(trader, msg[:data][:order])
                        end
                    end
                end
            catch
                nothing
            end
        end
        schedule(t)
        while !trader.stop
            sleep(1)
        end
        Base.throwto(t, InterruptException())
        fetch(t)
    end

    data_task = Threads.@spawn begin
        t = @task begin
            try
                HTTP.open(MARKET_DATA_STREAM) do ws
                    if !authenticate_data(ws, trader)
                        error("couldn't authenticate")
                    end

                    subscribe_tickers(ws, trader.ticker_ledgers)
                    for raw_msg in ws 
                        msg = JSON3.read(raw_msg)
                        for m in msg
                            if m[:T] == "b"
                                bar_update!(trader, m)
                            end
                        end
                    end
                end
            catch
                nothing
            end
        end
        schedule(t)
        while !trader.stop
            sleep(1)
        end
        Base.throwto(t, InterruptException())
        fetch(t)
    end

    while !trader.stop
        for tl in values(trader.ticker_ledgers)
            update(tl)
        end
        
        update(trader)
        
        if istaskfailed(trading_task)
            @info "Trading task failed"
            trader.stop = true
        elseif istaskfailed(data_task)
            @info "Data task failed"
            trader.stop=true
        end
        sleep(1)
    end
    
    while !(istaskdone(trading_task) || istaskfailed(trading_task)) || !(istaskdone(data_task) || istaskfailed(data_task))
        @show trading_task
        @show data_task
        sleep(1)
    end
    trader.stop = false
    @info "Trader stopped"
    return data_task, trading_task
   
end

function bar_update!(trader::RealtimeTrader, bar)
    sym = bar[:S]
    tl                 = trader.ticker_ledgers[sym]
    parsed_bar         = parse_bar(bar)
    new_e              = Entity(tl, parsed_bar...)
    data_e             = singleton(tl, Dataset)
    tl[Dataset][new_e] = data_e
    ds                 = tl[Dataset].data[1]
    ds.last_e          = new_e
    ds.stop            = parsed_bar[end].t
end

function order_update!(trader::RealtimeTrader, order_msg)
    uid = UUID(order_msg[:id])
   
    # TODO BAD
    id = nothing
    while id === nothing
        id = findfirst(x->x.id == uid, trader[Order].data)
    end

    order = trader[Order].data[id]

    order.status           = order_msg[:status]
    order.updated_at       = TimeDate(order_msg[:updated_at][1:end-1])
    order.filled_at        = TimeDate(order_msg[:filled_at][1:end-1])
    order.submitted_at     = TimeDate(order_msg[:submitted_at][1:end-1])
    order.filled_qty       = parse(Int, order_msg[:filled_qty])
    order.filled_avg_price = parse(Float64, order_msg[:filled_avg_price])
end

current_price(trader::RealtimeTrader, ticker) = trader.ticker_ledgers[ticker][Close][end].v

function submit_order(trader::RealtimeTrader, e; quantity = e.quantity)
    side = Purchase ∈ e ? "buy" : "sell"
    body = Dict("symbol"        => string(e.ticker),
                "qty"           => string(quantity),
                "side"          => side,
                "type"          => string(e.type),
                "time_in_force" => string(e.time_in_force))
    
    if e.type == OrderType.Limit
        body["limit_price"] = string(e.price)
    end
        
    resp = HTTP.post(URI(PAPER_TRADING_URL, path="/v2/orders"), Trading.header(trader.account), JSON3.write(body))
    if resp.status != 200
        error("something went wrong")
    end

    parse_body = JSON3.read(resp.body)

    return Order(UUID(parse_body[:id]),
                 UUID(parse_body[:client_order_id]),
                 parse_body[:created_at] !== nothing ? TimeDate(parse_body[:created_at][1:end-1])     : nothing,
                 parse_body[:updated_at] !== nothing ? TimeDate(parse_body[:updated_at][1:end-1])     : nothing,
                 parse_body[:submitted_at] !== nothing ? TimeDate(parse_body[:submitted_at][1:end-1]) : nothing,
                 parse_body[:filled_at] !== nothing ? TimeDate(parse_body[:filled_at][1:end-1])       : nothing,
                 parse_body[:expired_at] !== nothing ? TimeDate(parse_body[:expired_at][1:end-1])     : nothing,
                 parse_body[:canceled_at] !== nothing ? TimeDate(parse_body[:canceled_at][1:end-1])   : nothing,
                 parse_body[:failed_at] !== nothing ? TimeDate(parse_body[:failed_at][1:end-1])       : nothing,
                 parse(Int, parse_body[:filled_qty]),
                 parse_body[:filled_avg_price] !== nothing ? parse(Float64, parse_body[:filled_avg_price]) : 0.0,
                 parse_body[:status])
end

timestamp(trader::RealtimeTrader) = TimeStamp()
