function authenticate_data(b::AlpacaBroker, ws::WebSocket)
    send(ws,
         JSON3.write(Dict("action" => "auth",
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
    send(ws,
         JSON3.write(Dict("action" => "auth",
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
    resp = HTTP.get(URI(trading_url(b); path = "/v2/account"), header(b))

    if resp.status != 200
        return error("Couldn't get Account details")
    end

    acc_parse = JSON3.read(resp.body)
    cash = parse(Float64, acc_parse[:cash])

    resp = HTTP.get(URI(trading_url(b); path = "/v2/positions"), header(b))
    if resp.status != 200
        return error("Couldn't get position details")
    end

    pos_parse = JSON3.read(resp.body)
    positions = map(position -> (string(position[:symbol]), parse(Float64, position[:qty])),
                    pos_parse)
    return (; cash, positions)
end

account_details(b::HistoricalBroker) = (b.cash, ())

# TODO dumb
function fill_account!(trader::Trader)
    cash, positions = account_details(trader.broker)
    empty!(trader[Cash])
    empty!(trader[PurchasePower])

    Entity(trader.l, Cash(cash), PurchasePower(cash))
    
    current_positions = Set{String}(map(x->x.ticker, trader[Position]))

    for p in positions
        
        delete!(current_positions, p[1])
        
        id = findfirst(x -> x.ticker == p[1], trader[Position])
        if id === nothing
            Entity(trader.l, Position(p...))
        else
            trader[Position][id].quantity = p[2]
        end
    end
    
    for p in current_positions
        id = findfirst(x -> x.ticker == p, trader[Position])
        if id === nothing
            continue
        end

        trader[Position][id].quantity = 0.0
    end
end
