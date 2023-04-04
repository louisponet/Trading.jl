"""
    MockBroker

Mimics all function of a normal broker but with random data.
"""
Base.@kwdef struct MockBroker <: AbstractBroker
    cache::DataCache = DataCache()
end

bar_fields(::MockBroker) = (:t, :o, :h, :l, :c, :v, :n, :vw)

function data_query(broker::MockBroker, symbol, start, stop=nothing, ::Type{T} = Any; section, timeframe=Minute(1), limit=1000, kwargs...) where {T}
    tstamps = start:timeframe:stop
    
    colnames = [:o, :h, :l, :c, :v, :n, :vw]

    mock_dat = rand(length(tstamps), length(colnames))
    return TimeArray(collect(tstamps), mock_dat, colnames)
end

mock_bar(b::MockBroker, ticker, vals) = merge((T="b", S=ticker), NamedTuple(map(x -> x[1] => x[2], zip(bar_fields(b), vals))))
