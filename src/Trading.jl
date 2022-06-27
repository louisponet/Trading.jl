module Trading
using Reexport
@reexport using TimesDates
@reexport using MarketTechnicals
@reexport using Overseer
using Overseer: update
using Dates
using Statistics
using LinearAlgebra
using HTTP
using JSON3
using JLD2
using TimeSeries
using BinaryTraits
using BinaryTraits.Prefix: Can, Cannot, Is, IsNot

include("Components/traits.jl")
include("Components/core.jl")
include("Components/indicators.jl")
include("dates.jl")
include("constants.jl")
include("types.jl")
include("queries.jl")
include("data.jl")
include("Systems/core.jl")
include("Systems/indicators.jl")

export Trade, Bar, Quote, AccountInfo

export query_trades, query_bars, query_quotes

function __init__()
    init_traits(@__MODULE__)
end

end # module Trading
