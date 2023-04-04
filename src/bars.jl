bars(broker::AbstractBroker) = broker.cache.bar_data

function bars(broker::AbstractBroker, ticker, start, stop=current_time(); timeframe::Period, kwargs...)
    
    start = round(start, typeof(timeframe), RoundDown)
    stop  = round(stop, typeof(timeframe), RoundUp)

    t = retrieve_data(broker, bars(broker), (ticker, timeframe), start, stop, Float64; section="bars", timeframe=timeframe, kwargs...)
end

function bars(::AlpacaBroker, msg::AbstractVector)
    return map(filter(x->x[:T] == "b", msg)) do bar
        ticker = bar[:S]
        ticker, (parse_time(bar[:t]), (bar[:o], bar[:h], bar[:l], bar[:c], bar[:v]))
    end
end

function subscribe_bars(::AlpacaBroker, ticker::String, ws::WebSocket)
    send(ws, JSON3.write(Dict("action" => "subscribe",
                              "bars"  => [ticker])))
end

function subscribe_bars(dp::HistoricalBroker, ticker::String, start=nothing,stop=nothing; timeframe=nothing)
    if !any(x-> first(x) == ticker, keys(bars(dp)))
        start     = start === nothing ? minimum(x->timestamp(x)[1],   values(bars(dp))) : start
        stop      = stop === nothing  ? maximum(x->timestamp(x)[end], values(bars(dp))) : stop
        timeframe = timeframe === nothing ? minimum(x->last(x), keys(bars(dp))) : timeframe
        bars(dp, ticker, start, stop, timeframe=timeframe)
    end
    return nothing
end

function receive_bars(b::AlpacaBroker, ws)
    bars(b, JSON3.read(receive(ws)))
end

function receive_bars(dp::HistoricalBroker, args...)
    wait(dp.send_bars)
    curt = dp.clock.time
    
    msg = NamedTuple[]
    while isempty(msg) && dp.clock.time <= maximum(x->timestamp(x)[end], values(bars(dp)))
        dp.clock.time += dp.clock.dtime
        for (ticker, frame) in bars(dp)
            
            dat = frame[dp.clock.time]
            
            dat === nothing && continue
            
            vals = values(dat)
            push!(msg, mock_bar(dp.broker, first(ticker), (string(timestamp(dat)[1]), vals...)))
        end
    end
    dp.last = dp.clock.time
    reset(dp.send_bars)
    return bars(dp.broker, msg)
end
            
"""
    BarStream

Supplies a stream of bars from a broker.
Can be opened by calling [`bar_stream`](@ref) on a [`AbstractBroker`](@ref).
See [`receive`](@ref) and [`register!`](@ref) for more information.
"""
struct BarStream{B<:AbstractBroker, W}
    broker::B
    ws::W
end
HTTP.receive(b::BarStream) = receive_bars(b.broker, b.ws)

register!(b::BarStream, ticker) = subscribe_bars(b.broker, ticker, b.ws)

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

function bar_stream(func::Function, broker::HistoricalBroker)
    try
        func(BarStream(broker, nothing))
    catch e
        if !(e isa InterruptException)
            rethrow(e)
        end
    end
end
