"""
    DataLedger

Represents the tick data of a given `ticker`. A `DataLedger` can be attached to a [`DataPipeline`](@ref) with [`attach!`](@ref), which will cause data to flow in as soon as it is available.
"""
mutable struct DataLedger <: AbstractLedger
    ticker::String
    l::Ledger
end 

DataLedger(ticker::String) = DataLedger(ticker, Ledger())

Overseer.ledger(d::DataLedger) = d.l

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

"""
    DataPipeline

Handles distribution of data to the different [`DataLedgers`](@ref DataLedger) through the associated
`queues`.
By using either a [`HistoricalDataSource`](@ref) or [`RealtimeDataSource`](@ref) one can exchange
whether data is streamed from a historical dataset or streamed realtime through a connection to
an external data broker.
"""
Base.@kwdef struct DataPipeline{B <: AbstractBroker}
    broker::B
    ticker_ledgers::Dict{String, DataLedger} = Dict{String,DataLedger}()
    new_ticker::Threads.Condition = Threads.Condition()
end

DataPipeline(broker::AbstractBroker; kwargs...) = DataPipeline(;broker=broker, kwargs...)

"""
    attach!(ds::DataPipeline, l::DataLedger, args...; kwargs...)

Registers a [`DataLedger`](@ref) to `ds`. This creates a `Channel` through which the correct tick data
flows into `l`.
"""
function attach!(ds::DataPipeline, l::DataLedger, args...; kwargs...)
    ds.ticker_ledgers[l.ticker] = l
    lock(ds.new_ticker)
    notify(ds.new_ticker, l.ticker)
    unlock(ds.new_ticker)
end

function start_stream(ds::DataPipeline, stopevent, new_data_event)
    bar_stream(ds.broker) do stream

        for (ticker, q) in ds.ticker_ledgers
            register!(stream, ticker)
        end
        stop = false
        
        t1 = Threads.@spawn @stoppable stop while !stop
            lock(ds.new_ticker)
            try
                ticker = wait(ds.new_ticker)
                register!(stream, ticker)
                @info "Registered ticker"
            finally
                unlock(ds.new_ticker)
            end
        end
        
        t2 = Threads.@spawn @stoppable stop while !stop
            try
                bars = receive(stream)
                updated_tickers = Set{String}()
                for (ticker, tbar) in bars
                    time, bar  = tbar
                    Entity(ds.ticker_ledgers[ticker], TimeStamp(time), Open(bar[1]), High(bar[2]), Low(bar[3]), Close(bar[4]), Volume(round(Int,bar[5])))
                    push!(updated_tickers, ticker)
                end
                
                @sync for ticker in updated_tickers
                    Threads.@spawn begin
                        Overseer.update(ds.ticker_ledgers[ticker])
                    end
                end
                lock(new_data_event) do 
                    notify(new_data_event)
                end
                    
            catch e
                if !(e isa InvalidStateException) && !(e isa EOFError)
                    showerror(stdout, e, catch_backtrace())
                end
            end
        end
        
        stop_task = Threads.@spawn begin
            lock(stopevent)
            try
                while !stop
                    stop = wait(stopevent)
                end
            finally
                unlock(stopevent)
            end
            stream.ws !== nothing && close(stream.ws)
            stop=true
            lock(ds.new_ticker)
            notify(ds.new_ticker, error=true)
            unlock(ds.new_ticker)
            @info "Closing Data Stream"
        end
        fetch(t1)
        fetch(t2)
        fetch(stop_task)
        @info "Closed Data Stream"
    end
end

