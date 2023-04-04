quotes(broker::AbstractBroker) = broker.cache.quotes_data 
quotes(broker::AbstractBroker, ticker, args...; kwargs...) =
    retrieve_data(broker, broker.quote_data, ticker, args...; section="quotes", kwargs...)
    
function parse_quote(b::AlpacaBroker, q)
    (ask_price = q[:ap], bid_price=q[:bp])
end

function latest_quote(b::AlpacaBroker, ticker::String)
    resp = HTTP.get(quote_url(b, ticker), header(b))
    
    if resp.status != 200
        error("something went wrong while asking latest quote")
    end
    
    return parse_quote(b, JSON3.read(resp.body)[:quote])
end

function latest_quote(broker::HistoricalBroker, ticker)
    qs = retrieve_data(broker, quotes(broker), ticker, broker.clock.time, broker.clock.time+Second(1); section="quotes")
    if isempty(qs)
        return nothing
    end
    q = qs[1]
    return parse_quote(broker.broker, NamedTuple([s => v for (s,v) in zip(colnames(q), values(q))]))
end

# TODO requires :c , :o etc
function price(broker::HistoricalBroker, price_t, ticker)
    @assert haskey(bars(broker), (ticker, broker.clock.dtime)) "Ticker $ticker not in historical bar data"
    
    bars_ = bars(broker)[(ticker, broker.clock.dtime)]
    
    if isempty(bars_)
        return nothing
    end
    
    first_t = timestamp(bars_)[1]

    price_t = broker.clock.time
    
    if price_t < first_t
        return values(bars_[1][:o])[1]
    end

    last_t = timestamp(bars_)[end]
    if price_t > last_t
        return values(bars_[end][:c])[1]
    end

    tdata = bars_[price_t]
    while tdata === nothing
        price_t -= broker.clock.dtime
        tdata = bars_[price_t]
    end
    return values(tdata[:o])[1]
end

current_price(broker::AbstractBroker, args...) = price(broker, current_time(broker), args...)

function current_price(broker::AlpacaBroker, ticker)
    dat = latest_quote(broker, ticker)
    return dat === nothing ? nothing : (dat[1] + dat[2])/2
end

current_price(t::Trader, ticker) = current_price(t.broker, ticker)
