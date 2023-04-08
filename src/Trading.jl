module Trading
using Reexport

@reexport using Dates
@reexport using TimeSeries
const TimeDate = DateTime
export TimeDate

@reexport using Overseer
using Overseer: AbstractComponent, EntityState
using Overseer: update

using Statistics
using LinearAlgebra
using HTTP
using HTTP.WebSockets
using HTTP.WebSockets: isclosed
using JSON3
using JLD2
using BinaryTraits
using BinaryTraits.Prefix: Can, Cannot, Is, IsNot
using Base.Threads
using HTTP: URI
using EnumX
using UUIDs
using ProgressMeter
using PrettyTables

include("utils.jl")

include("Components/core.jl")
include("Components/indicators.jl")
include("Components/portfolio.jl")
include("timearrays.jl")
include("datacache.jl")
include("brokers.jl")
include("ticker_ledger.jl")
include("trader.jl")

include("account.jl")
include("running.jl")
include("bars.jl")
include("orders.jl")
include("quotes.jl")
include("time.jl")

include("Systems/core.jl")
include("Systems/indicators.jl")
include("Systems/portfolio.jl")


export Trader, BackTester, start, stop_all, stop_main, stop_trading, stop_data
export AlpacaBroker, HistoricalBroker
export bars, quotes, trades


function __init__()
    init_traits(@__MODULE__)
end

module Indicators
    using ..Trading: SMA, EMA, MovingStdDev, RSI, Bollinger, Sharpe
    export SMA, EMA, MovingStdDev, RSI, Bollinger, Sharpe
end

module Basic
    using ..Trading: Open, High, Low, Close, Volume, TimeStamp, LogVal, Difference, RelativeDifference
    export Open, High, Low, Close, Volume, TimeStamp, LogVal, Difference, RelativeDifference
end

module Portfolio
    using ..Trading: Purchase, Sale, Position, PortfolioSnapshot, Filled,
                     current_position
    export Purchase, Sale, Position, PortfolioSnapshot, Filled,
           current_position
end

module Strategies
    using ..Trading: Strategy, current_price, current_time, new_entities,  reset!
    export Strategy, current_price, current_time, new_entities, reset!
    
    using TimeSeries: lag
    export lag
end

end
