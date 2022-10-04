function stock_query(f::Function, account::AccountInfo, symbol, section, query)
    make_uri = () -> HTTP.URI(scheme="https", host="data.alpaca.markets", path = "/v2/stocks/$symbol/$section", query=query)
    done = false
    while !done
        if account.nrequests == account.rate
            @info "Account request limit reached, throttling..."
            sleep(convert(Millisecond, Minute(1) - (now() - account.last)))
        end
        if now() - account.last > Minute(1)
            account.nrequests = 0
            account.last = now()
        end
        resp = HTTP.get(make_uri(), header(account))
        account.nrequests += 1
        
        if resp.status == 200
            t = JSON3.read(resp.body)
            
            f(t)
            
            if haskey(t, :next_page_token) && t[:next_page_token] !== nothing
                query["page_token"] = t[:next_page_token]
            else
                done = true
            end
        else
            @warn """
            Something went wrong querying $section data for ticker $symbol
            leading to status: $(resp.status)
            """
            done = true
        end
    end
    delete!(query, "page_token")
end

function query_trades(account::AccountInfo, symbol, start::TimeDate; stop::Union{TimeDate, Nothing}=nothing, limit=10000) 
    query = Dict{String, Any}("start" => string(start)*"Z")
    if stop !== nothing
        query["end"] = string(stop) * "Z"
    end
    query["limit"] = limit

    trades = Trade[]
    stock_query(account, symbol, "trades", query) do t
        for tr in t[:trades]
            push!(trades, Trade(TimeDate(tr[:t][1:end-1]), tr[:x], tr[:p], tr[:s], tr[:c]))
        end
    end
    return trades
end

function query_quotes(account::AccountInfo, symbol, start::TimeDate; stop::Union{TimeDate, Nothing}=nothing, limit=10000) 
    query = Dict{String, Any}("start" => string(start)*"Z")
    if stop !== nothing
        query["end"] = string(stop) * "Z"
    end
    query["limit"] = limit

    quotes = Quote[]
    stock_query(account, symbol, "quotes", query) do t
        for tr in t[:quotes]
            push!(quotes, Quote(TimeDate(tr[:t][1:end-1]), tr[:ax], tr[:ap], tr[:as], tr[:bx], tr[:bp], tr[:bs], tr[:c]))
        end
    end
    return quotes
end

function query_bars(account::AccountInfo, symbol, start::DateTime; stop::Union{DateTime, Nothing}=nothing, timeframe::String="1Min", limit=10000)
    query = Dict{String, Any}("start" => string(start)*"Z")
    if stop !== nothing
        query["end"] = string(stop) * "Z"
    end
    query["limit"] = limit
    query["timeframe"] = timeframe

    bars = []
    times = TimingData[]
    stock_query(account, symbol, "bars", query) do t
        if t[:bars] !== nothing
            for tr in t[:bars]
                push!(bars, (Open(tr[:o]), High(tr[:h]), Low(tr[:l]), Close(tr[:c]), Volume(tr[:v])))
                push!(times, TimingData(time=DateTime(tr[:t][1:end-1])))
            end
        end
    end
    return times, bars
end


