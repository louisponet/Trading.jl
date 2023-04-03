function authenticate_data(b::AlpacaBroker, ws::WebSocket)
    send(ws, JSON3.write(Dict("action" => "auth",
                              "key"    => b.key_id,
                              "secret" => b.secret_key)))
    reply = receive(ws)
    try
        return JSON3.read(reply)[1][:T] == "success"
    catch e
        throw(AuthenticationException(e))
    end
end

function authenticate_trading(b::AlpacaBroker, ws::WebSocket)
    send(ws, JSON3.write(Dict("action" => "auth",
                              "key"    => b.key_id,
                              "secret" => b.secret_key)))
    reply = receive(ws)
    try
        return JSON3.read(reply)["data"]["status"] == "authorized"
    catch
        throw(AuthenticationException(e))
    end
end

function account_details(b::AlpacaBroker)
    resp = HTTP.get(URI(trading_url(b), path="/v2/account"), header(b))

    if resp.status != 200
        return error("Couldn't get Account details")
    end

    acc_parse = JSON3.read(resp.body)
    cash = parse(Float64, acc_parse[:cash])

    resp = HTTP.get(URI(trading_url(b), path="/v2/positions"), header(b))
    if resp.status != 200
        return error("Couldn't get position details")
    end

    pos_parse = JSON3.read(resp.body)
    positions = map(position -> (string(position[:symbol]), parse(Float64, position[:qty])), pos_parse)
    return (;cash, positions)
end

account_details(b::HistoricalBroker) = (b.cash, ())

function fill_account!(trader::Trader)
    cash, positions = account_details(trader.broker)

    empty!(trader[Cash])
    empty!(trader[PurchasePower])
    
    Entity(trader, Cash(cash), PurchasePower(cash))
    for p in positions
        id = findfirst(x->x.ticker == p[1], trader[Position])
        if id === nothing 
            Entity(trader, Position(p...))
        else
            trader[Position][id].quantity = p[2]
        end
    end
end

