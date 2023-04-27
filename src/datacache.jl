const HistoricalTradeDataDict = Dict{String,TimeArray{Any,2,TimeDate,Matrix{Any}}}
const HistoricalQuoteDataDict = Dict{String,TimeArray{Any,2,TimeDate,Matrix{Any}}}
const HistoricalBarDataDict = Dict{Tuple{String,Period},
                                   TimeArray{Float64,2,TimeDate,Matrix{Float64}}}

"""
A cache used by [Brokers](@ref) to store previously retrieved historical data.
"""
Base.@kwdef struct DataCache
    bar_data::HistoricalBarDataDict     = HistoricalBarDataDict()
    trade_data::HistoricalTradeDataDict = HistoricalTradeDataDict()
    quote_data::HistoricalQuoteDataDict = HistoricalQuoteDataDict()
end
