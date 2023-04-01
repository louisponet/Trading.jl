const ALPACA_HISTORICAL_DATA_URL = URI("https://data.alpaca.markets")

 Base.@kwdef mutable struct AlpacaBroker <: AbstractBroker
    key_id::String
    secret_key::String
    
    bar_data::HistoricalBarDataDict     = HistoricalBarDataDict()
    trade_data::HistoricalTradeDataDict = HistoricalTradeDataDict()
    quote_data::HistoricalQuoteDataDict = HistoricalQuoteDataDict()
    rate::Int = 200
    last::TimeDate = clock()
    nrequests::UInt64 = 0
    
    function AlpacaBroker(key_id, secret_key, bar_data, trade_data, quote_data, rate, last, nrequests)
        try
            header = ["APCA-API-KEY-ID" => key_id, "APCA-API-SECRET-KEY" => secret_key]
            testpath = "/v2/stocks/AAPL/trades"
            resp = HTTP.get(URI(ALPACA_HISTORICAL_DATA_URL, path=testpath), header)
        catch e
            throw(AuthenticationException(e))
        end
        return new(key_id, secret_key, bar_data, trade_data, quote_data, rate, last, nrequests)
    end
    
end

AlpacaBroker(key_id, secret_key; kwargs...) = AlpacaBroker(; key_id=key_id, secret_key=secret_key, kwargs...)

Base.string(::AlpacaBroker, start::TimeDate) = string(start) * "Z"
header(b::AlpacaBroker) = ["APCA-API-KEY-ID" => b.key_id, "APCA-API-SECRET-KEY" => b.secret_key]

data_stream_url(::AlpacaBroker)    = URI("wss://stream.data.alpaca.markets/v2/iex")
trading_stream_url(::AlpacaBroker) = URI("wss://paper-api.alpaca.markets/stream") 
trading_url(::AlpacaBroker) = URI("https://paper-api.alpaca.markets")
order_url(b::AlpacaBroker) = URI(trading_url(b), path="/v2/orders")
quote_url(b::AlpacaBroker, ticker::String) = URI(ALPACA_HISTORICAL_DATA_URL, path = "/v2/stocks/$ticker/quotes/latest")

function receive_bars(b::AlpacaBroker, ws)
    bars(b, JSON3.read(receive(ws)))
end

function bars(::AlpacaBroker, msg::AbstractVector)
    return map(filter(x->x[:T] == "b", msg)) do bar
        ticker = bar[:S]
        ticker, (TimeDate(bar[:t][1:end-1]), (bar[:o], bar[:h], bar[:l], bar[:c], bar[:v]))
    end
end        

#TODO merge both
function authenticate_data(b::AlpacaBroker, ws::WebSocket)
    send(ws, JSON3.write(Dict("action" => "auth",
                              "key"    => b.key_id,
                              "secret" => b.secret_key)))
    reply = receive(ws)
    try
        return JSON3.read(reply)[1][:T] == "success"
    catch
        return false
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
        return false
    end
end

#TODO Make nice error
function subscribe_bars(::AlpacaBroker, ticker::String, ws::WebSocket)
    send(ws, JSON3.write(Dict("action" => "subscribe",
                              "bars"  => [ticker])))
    # msg = JSON3.read(receive(ws))
    # errid = findfirst(x->x[:T] == "error", msg)
    # if errid !== nothing
    #     @error msg[errid][:msg]
    # end
end
                              
function Base.string(::AlpacaBroker, timeframe::Period)
    if timeframe isa Minute
        period_string = "Min"
    else
        period_string = string(typeof(timeframe))
    end
    return "$(timeframe.value)$period_string"
end

Base.string(::AlpacaBroker, a) = string(a)

function stock_query(broker::AlpacaBroker, symbol, start, stop=nothing, ::Type{T} = Any; section, limit=1000, kwargs...) where {T}
    
    query = Dict{String, Any}("start" => string(broker, start))
    if stop !== nothing
        query["end"] = string(broker, stop)
    end
    query["limit"] = limit
    for (k, v) in kwargs
        query[string(k)] = string(broker, v)
    end
    
    make_uri = () -> URI(ALPACA_HISTORICAL_DATA_URL, path = "/v2/stocks/$symbol/$section", query=query)

    out = Dict()
    timestamps = TimeDate[] 

    dat_keys = nothing
    section_symbol = Symbol(section)
    
    while true
        
        if broker.nrequests == broker.rate
            st = Minute(1) - (clock() - broker.last)
            if st < Minute(0)
                broker.nrequests=0
                broker.last = clock()
            else
                @info "Account request limit reached, throttling..."
                sleep(convert(Microsecond, st))
            end
        end
        
        if clock() - broker.last > Minute(1)
            broker.nrequests = 0
            broker.last = clock()
        end
        
        resp = HTTP.get(make_uri(), header(broker))
        broker.nrequests += 1
        if resp.status == 200
            t = JSON3.read(resp.body)
            if t[section_symbol] === nothing
                if t["next_page_token"] === nothing
                    return
                else
                    continue
                end
            end

            data = t[section_symbol]

            n_dat = length(data)
            dat_keys = sort(collect(filter(!isequal(:t), keys(data[1]))))
            t_dat = Dict([k => Vector{T}(undef, n_dat) for k in dat_keys])
            t_timestamps = Vector{TimeDate}(undef, n_dat)

            Threads.@threads for i in 1:n_dat
                d = data[i]
                t_timestamps[i] = TimeDate(d[:t][1:end-1])
                
                for k in dat_keys
                    t_dat[k][i] = d[k]
                end
                
            end

            for (k, vals) in t_dat
                if haskey(out, k)
                    append!(out[k], vals)
                else
                    out[k] = vals
                end
            end
            append!(timestamps, t_timestamps)
            
            if haskey(t, :next_page_token) && t[:next_page_token] !== nothing
                query["page_token"] = t[:next_page_token]
            else
                break
            end
        else
            @warn """
            Something went wrong querying $section data for ticker $symbol
            leading to status: $(resp.status)
            """
            break
        end
    end
    
    delete!(query, "page_token")
    
    return TimeArray(timestamps, hcat([out[k] for k in dat_keys]...), collect(dat_keys))
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
                 parse(Float64,parse_body[:qty]))
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

function receive_order(b::AlpacaBroker, ws)
    msg = JSON3.read(receive(ws))
    if msg[:stream] == "trade_updates" && msg[:data][:event] == "fill"
        return parse_order(b, msg[:data][:order])
    end
end

function latest_quote(b::AlpacaBroker, ticker::String)
    resp = HTTP.get(quote_url(b, ticker), header(b))
    
    if resp.status != 200
        error("something went wrong while asking latest quote")
    end
    
    return parse_quote(b, JSON3.read(resp.body)[:quote])
end

function parse_quote(b, q)
    (ask_price = q[:ap], bid_price=q[:bp])
end

function bar_stream(func::Function, broker::AlpacaBroker)
    HTTP.open(data_stream_url(broker)) do ws
        
        if !authenticate_data(broker, ws)
            error("couldn't authenticate")
        end
        
        try
            func(BarStream(broker, ws))
        catch e
            showerror(stdout, e, catch_backtrace())
            if !(e isa InterruptException)
                rethrow(e)
            end
        end
        
    end
end

current_time(::AlpacaBroker) = clock()

function failed_order(broker, order)
    t = current_time(broker)
    return Order(order.ticker, uuid1(), uuid1(), t, t, t, nothing, nothing, nothing, t, 0.0, 0.0, "failed", order.quantity)
end

function submit_order(broker::AlpacaBroker, order)
    uri  = Data.order_url(broker)
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

function trading_link(f::Function, broker::AlpacaBroker)
    HTTP.open(trading_stream_url(broker)) do ws
        if !authenticate_trading(broker, ws)
            error("couldn't authenticate")
        end
        @info "Authenticated trading"
        send(ws, JSON3.write(Dict("action" => "listen",
                                  "data"  => Dict("streams" => ["trade_updates"]))))
        try
            f(TradingLink(broker, ws))
        catch e
            showerror(stdout, e, catch_backtrace())
            if !(e isa InterruptException)
                rethrow(e)
            end
        end
    end
end

