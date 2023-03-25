module Trading
using Reexport
@reexport using TimesDates
@reexport using MarketTechnicals
@reexport using Overseer
using Overseer: AbstractComponent

using Overseer: update
using Dates
using Statistics
using LinearAlgebra
using HTTP
using HTTP.WebSockets
using JSON3
using JLD2
using TimeSeries
using BinaryTraits
using BinaryTraits.Prefix: Can, Cannot, Is, IsNot
using Base.Threads
using HTTP: URI
using EnumX
using UUIDs

using ProgressMeter
using PrettyTables

const PAPER_TRADING_URL = URI("https://paper-api.alpaca.markets")
const DATA_URL          = URI("https://data.alpaca.markets")

const TRADING_STREAM_PAPER = URI("wss://paper-api.alpaca.markets/stream")
const MARKET_DATA_STREAM = URI("wss://stream.data.alpaca.markets/v2/iex")

include("utils.jl")
include("types.jl")
include("spmc_queue.jl")
include("Data/Data.jl")
include("Components/traits.jl")
include("Components/core.jl")
include("Components/indicators.jl")
include("Components/portfolio.jl")
include("logging.jl")
include("dates.jl")
include("constants.jl")
include("queries.jl")
include("data.jl")
include("trader.jl")
include("realtime.jl")
include("simulation.jl")
include("Systems/core.jl")
include("Systems/indicators.jl")
include("Systems/portfolio.jl")

export Trade, Quote, AccountInfo

export query_trades, query_bars, query_quotes

function __init__()
    init_traits(@__MODULE__)
end

end
