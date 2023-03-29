const ALPACA_HISTORICAL_DATA_URL = URI("https://data.alpaca.markets")

 Base.@kwdef mutable struct AlpacaBroker <: AbstractBroker
    key_id::String
    secret_key::String
    rate::Int = 200
    last::TimeDate = clock()
    nrequests::UInt64 = 0
    function AlpacaBroker(key_id, secret_key, rate, last, nrequests)
        try
            header = ["APCA-API-KEY-ID" => key_id, "APCA-API-SECRET-KEY" => secret_key]
            testpath = "/v2/stocks/AAPL/trades"
            resp = HTTP.get(URI(ALPACA_HISTORICAL_DATA_URL, path=testpath), header)
        catch e
            throw(AuthenticationException(e))
        end
        return new(key_id, secret_key, rate, last, nrequests)
    end
end

AlpacaBroker(key_id, secret_key; kwargs...) = AlpacaBroker(; key_id=key_id, secret_key=secret_key, kwargs...)

Base.string(::AlpacaBroker, start::TimeDate) = string(start) * "Z"
header(b::AlpacaBroker) = ["APCA-API-KEY-ID" => b.key_id, "APCA-API-SECRET-KEY" => b.secret_key]

data_stream_url(::AlpacaBroker)    = URI("wss://stream.data.alpaca.markets/v2/iex")
trading_stream_url(::AlpacaBroker) = URI("wss://paper-api.alpaca.markets/stream") 
trading_url(::AlpacaBroker) = URI("https://paper-api.alpaca.markets")
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
function subscribe(::AlpacaBroker, ws::WebSocket, ticker::String)
    send(ws, JSON3.write(Dict("action" => "subscribe",
                              "bars"  => [ticker])))
    msg = JSON3.read(receive(ws))
    errid = findfirst(x->x[:T] == "error", msg)
    if errid !== nothing
        @error msg[errid][:msg]
    end
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

function stock_query(broker::AlpacaBroker, symbol, start, stop=clock(), ::Type{T} = Any; section, limit=1000, kwargs...) where {T}
    
    query = Dict{String, Any}("start" => string(broker, start))
    
    query["end"] = string(broker, stop)
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
    resp = HTTP.get(URI(ALPACA_PAPER_TRADING_URL, path="/v2/account"), header(b))

    if resp.status != 200
        return error("Couldn't get Account details")
    end

    acc_parse = JSON3.read(resp.body)
    cash = parse(Float64, acc_parse[:cash])

    resp = HTTP.get(URI(ALPACA_PAPER_TRADING_URL, path="/v2/positions"), header(b))
    if resp.status != 200
        return error("Couldn't get position details")
    end

    pos_parse = JSON3.read(resp.body)
    positions = map(position -> (string(position[:symbol]), parse(Float64, position[:qty])), pos_parse)
    return (;cash, positions)
end


function parse_order(::AlpacaBroker, parse_body)
    Order(parse_body[:symbol],
                 UUID(parse_body[:id]),
                 UUID(parse_body[:client_order_id]),
                 parse_body[:created_at] !== nothing ? TimeDate(parse_body[:created_at][1:end-1])     : nothing,
                 parse_body[:updated_at] !== nothing ? TimeDate(parse_body[:updated_at][1:end-1])     : nothing,
                 parse_body[:submitted_at] !== nothing ? TimeDate(parse_body[:submitted_at][1:end-1]) : nothing,
                 parse_body[:filled_at] !== nothing ? TimeDate(parse_body[:filled_at][1:end-1])       : nothing,
                 parse_body[:expired_at] !== nothing ? TimeDate(parse_body[:expired_at][1:end-1])     : nothing,
                 parse_body[:canceled_at] !== nothing ? TimeDate(parse_body[:canceled_at][1:end-1])   : nothing,
                 parse_body[:failed_at] !== nothing ? TimeDate(parse_body[:failed_at][1:end-1])       : nothing,
                 parse(Float64, parse_body[:filled_qty]),
                 parse_body[:filled_avg_price] !== nothing ? parse(Float64, parse_body[:filled_avg_price]) : 0.0,
                 parse_body[:status],
                 parse_body[:requested_qty])
end

