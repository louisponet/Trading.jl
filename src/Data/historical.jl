"""
   HistoricalBroker

Stores and provides data from historical datasets. Data can be streamed fashion by assigning a
[`Clock`](@ref) to the `clock` constructor kwarg, which will be used to determine the next bar to
stream when calling `receive` on this provider.
"""
Base.@kwdef mutable struct HistoricalBroker{B <: AbstractBroker} <: AbstractBroker
    broker::B
    
    bar_data::HistoricalBarDataDict     = HistoricalBarDataDict()
    trade_data::HistoricalTradeDataDict = HistoricalTradeDataDict()
    quote_data::HistoricalQuoteDataDict = HistoricalQuoteDataDict()
    
    clock::Clock = Clock(clock(), Millisecond(1))
    last::TimeDate = TimeDate(0)
    cash::Float64 = 100000.0
    send_bars::Base.Event = Base.Event()
    variable_transaction_fee::Float64 = 0.0
    fee_per_share::Float64 = 0.0
    fixed_transaction_fee::Float64 = 0.0
end

HistoricalBroker(b::AbstractBroker; kwargs...)  = HistoricalBroker(; broker=b, kwargs...)
broker(b::HistoricalBroker) = b.broker

function subscribe_bars(dp::HistoricalBroker, ticker, start=nothing,stop=nothing; timeframe=nothing)
    if !any(x-> first(x) == ticker, keys(dp.bar_data))
        start     = start === nothing ? minimum(x->timestamp(x)[1],   values(dp.bar_data)) : start
        stop      = stop === nothing  ? maximum(x->timestamp(x)[end], values(dp.bar_data)) : stop
        timeframe = timeframe === nothing ? minimum(x->last(x), keys(dp.bar_data)) : timeframe
        bars(dp, ticker, start, stop, timeframe=timeframe)
    end
    return nothing
end
            
function latest_quote(provider::HistoricalBroker, ticker)
    qs = retrieve_data(provider, provider.quote_data, ticker, provider.clock.time, provider.clock.time+Second(1); section="quotes")
    if isempty(qs)
        return nothing
    end
    q = qs[1]
    return parse_quote(provider.broker, NamedTuple([s => v for (s,v) in zip(colnames(q), values(q))]))
end

# TODO requires :c , :o etc
function price(provider::HistoricalBroker, price_t, ticker)
    @assert haskey(provider.bar_data, (ticker, provider.clock.dtime)) "Ticker $ticker not in historical bar data"
    
    bars = provider.bar_data[(ticker, provider.clock.dtime)]
    first_t = timestamp(bars)[1]

    price_t = provider.clock.time
    
    if price_t < first_t
        return values(bars[1][:o])[1]
    end

    last_t = timestamp(bars)[end]
    if price_t > last_t
        return values(bars[end][:c])[1]
    end

    tdata = bars[price_t]
    while tdata === nothing
        price_t -= provider.clock.dtime
        tdata = bars[price_t]
    end
    return values(tdata[:o])[1]
end

current_time(provider::HistoricalBroker) = provider.clock.time

#TODO Not Broker Agnostic
function receive_bars(dp::HistoricalBroker, args...)
    wait(dp.send_bars)
    curt = dp.clock.time
    
    msg = NamedTuple[]
    while isempty(msg) && dp.clock.time <= maximum(x->timestamp(x)[end], values(dp.bar_data))
        dp.clock.time += dp.clock.dtime
        for (ticker, frame) in dp.bar_data
            
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

function bar_stream(func::Function, broker::HistoricalBroker)
    try
        func(BarStream(broker, nothing))
    catch e
        if !(e isa InterruptException)
            rethrow(e)
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

function receive_order(broker::HistoricalBroker, args...)
    sleep(1)
    return nothing
end

trading_link(f::Function, broker::HistoricalBroker) = f(TradingLink(broker, nothing))

account_details(b::HistoricalBroker) = (b.cash, ())

delete_all_orders!(::HistoricalBroker) = nothing

