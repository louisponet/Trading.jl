using Pkg
Pkg.add(url="https://github.com/louisponet/Trading.jl")
Pkg.add(["Plots", "GLM", "HypothesisTests", "Statistics", "ThreadPools"])

using Trading
using Plots
using GLM
using HypothesisTests
using Statistics
using ThreadPools

using Trading.TimeSeries: rename

using Trading: Purchase, Sale, Close, LogVal, Filled, Order, TimeStamp, PortfolioSnapshot,
               OrderType, TimeInForce, PurchasePower, Strategy, Trader,
               AlpacaBroker, HistoricalBroker, Position, BackTester
               
using Trading: bars, in_trading, only_trading, current_position, current_time, current_price, start

function fit_γμ(account, ticker1, ticker2, start, stop; timeframe=Minute(1), only_day=true)
    df1 = bars(account, ticker1, start, stop, timeframe=Minute(1))
    df2 = bars(account, ticker2, start, stop, timeframe=Minute(1))

    if only_day
        df1 = df1[findall(x->in_trading(x), timestamp(df1))]
        df2 = df2[findall(x->in_trading(x), timestamp(df2))]
    end
    fit_γμ(df1, df2)
end

function fit_γμ(df1, df2)
    df1 = rename!(df1[:c], :t1)
    df2 = rename!(df2[:c], :t2)

    df = log.(merge(df1, df2))
    train_df = df 
    ols = lm(@formula(t1 ~ t2), train_df)
    test = ADFTest(residuals(ols), :none, 0)

    μ = coef(ols)[1]
    γ = coef(ols)[2]
    return γ, μ, test
end

function mean_daily_γ(acc, ticker1, ticker2, start, stop; timeframe=Minute(1))
    df1 = bars(acc, ticker1, start, stop, timeframe=Minute(1), normalize=false)
    df2 = bars(acc, ticker2, start, stop, timeframe=Minute(1), normalize=false)
    return mean_daily_γ(df1, df2)
end

function mean_daily_γ(df1, df2)
    df1 = Trading.only_trading(df1)
    df2 = Trading.only_trading(df2)

    df1 = Trading.interpolate_timearray(df1, daily=true)
    df2 = Trading.interpolate_timearray(df2, daily=true)

    df1 = Trading.split_days(df1)
    df2 = Trading.split_days(df2)

    coint_params = tmap(zip(df1, df2)) do (msft, aapl)
        γ, μ, res = fit_γμ(msft, aapl)
        return dayofweek(timestamp(msft)[1]), γ, μ, res
    end

    return (map(i -> mean(map(x->x[2], filter(x->x[1] == i, coint_params))), 1:5)...,)
end

function cointegration_timearray(account, ticker1, ticker2, start, stop; γ=0.78, z_thr=1.5,window=20, timeframe=Minute(1), only_day=true)
    
    df1 = bars(account, ticker1, start, stop, timeframe=timeframe)
    df2 = bars(account, ticker2, start, stop, timeframe=timeframe)

    if only_day
        df1 = df1[findall(x->in_trading(x), timestamp(df1))]
        df2 = df2[findall(x->in_trading(x), timestamp(df2))]
    end
    ticksym1 = Symbol(ticker1)
    ticksym2 = Symbol(ticker2)
    df1 = rename!(df1[:c], ticksym1)
    df2 = rename!(df2[:c], ticksym2)
    df = log.(merge(df1, df2))

    df = merge(df, rename(df[ticksym1] .- γ .* df[ticksym2], :s))
    df = merge(df, rename(moving(mean, df[:s], window), :s_mean), rename(moving(std, df[:s], window), :s_std))
    df = merge(df, rename((df[:s] .- df[:s_mean]) ./df[:s_std], :z))
    
    signal = map(df[:z]) do timestamp, z
        if z < -z_thr
            return timestamp, 1
        elseif z > z_thr
            return timestamp, -1
        else
            return timestamp, 0
        end
    end
    df = merge(df, rename(signal, :EntrySignal))
    df = merge(df, rename(Float64.(sign.(df[:z]) .* sign.(TimeSeries.lag(df[:z], 1)) .== -1), :ExitSignal))
    
    df = merge(exp.(df[ticksym1]), exp.(df[ticksym2]), df[:z], df[:EntrySignal], df[:ExitSignal], TimeArray((Time=TimeSeries.timestamp(df), position1=zeros(length(df[ticksym1])), position2=zeros(length(df[ticksym2]))), timestamp=:Time), df[:s], df[:s_mean], df[:s_std])
    
    in_position = false
    prev_signal = 0.0
    
    df = map(df) do timestamp, row
    
        if !in_trading(timestamp)
            return timestamp, row
        end
        
        entry_signal = row[4]
        if !iszero(entry_signal) && !in_position
            in_position = true
            prev_signal = entry_signal
            row[6] = entry_signal
            row[7] = - γ * entry_signal 
        end
        exit_signal = row[5]
        if (!iszero(exit_signal)) && in_position
            in_position = false
            row[6] = 0.0
            row[7] = 0.0
        elseif in_position
            row[6] = prev_signal 
            row[7] = - γ * prev_signal 
        end
        return timestamp, row
    end

    df = merge(df, rename(basecall(diff(df[ticksym1]) .* TimeSeries.lag(df[:position1],1), cumsum), :gains1))
    df = merge(df, rename(basecall(diff(df[ticksym2]) .* TimeSeries.lag(df[:position2],1), cumsum), :gains2))
    df = merge(df, rename(df[:gains2] .+ df[:gains1], :tot_value))

    df = TimeArray(DateTime.(timestamp(df)), values(df), colnames(df))
    return df
end


@pooled_component mutable struct Pair
    ticker1::String
    ticker2::String
    γ::NTuple{5,Float64}
    z_thr::Float64
end

@component struct Spread <: Trading.SingleValIndicator
    v::Float64
end

@component struct Seen end

struct PairStrat <: System end

@component struct ZScore{T} <: Trading.SingleValIndicator
    v::T
end

Overseer.requested_components(::PairStrat) = (Spread, Seen, Trading.MovingStdDev{20, Spread},
                                               Trading.SMA{20, Spread}, Close, LogVal{Close}, ZScore{Spread})

Overseer.prepare(::PairStrat, l::Overseer.AbstractLedger) = Overseer.ensure_component!(l, Pair)
function Overseer.update(::PairStrat, m::Trading.Trader)
    
    pairs_comp  = m[Pair]
    spread_comp = m[Spread]
    seen_comp   = m[Seen]
    sma_comp    = m[Trading.SMA{20, Spread}]
    z_comp      = m[ZScore{Spread}]
    stddev_comp = m[Trading.MovingStdDev{20, Spread}]

    curt = current_time(m)

    # We clear all data at market open
    if Trading.is_market_open(curt)
        
        for (pair, pair_es) in pools(pairs_comp)
            empty_entities!(m.ticker_ledgers[pair.ticker1])
            empty_entities!(m.ticker_ledgers[pair.ticker2])
        end
    
        empty!(spread_comp)
        empty!(seen_comp)
        empty!(sma_comp)
        empty!(z_comp)
        empty!(stddev_comp)
        
    end

    new_pos = false
    cash = m[PurchasePower][1].cash

    pending_order = any(x -> x ∉ m[Filled], @entities_in(m, Purchase || Sale))

    for ie in length(seen_comp)+1:length(spread_comp)

        # Even if an order is already pending we still need to "see" the remaining entities
        e = entity(spread_comp, ie)
        m[e] = Seen()
        
        if e ∉ sma_comp || pending_order || !in_trading(curt)
            continue
        end
        
        v         = spread_comp[ie].v
        sma       = sma_comp[e].sma
        σ         = stddev_comp[e].σ 
        z_score   = (v - sma) / σ
        z_comp[e] = ZScore{Spread}(z_score)
        
        pair      = pairs_comp[e]
        
        curpos1 = current_position(m, pair.ticker1)
        curpos2 = current_position(m, pair.ticker2)

        p1 = current_price(m, pair.ticker1)
        p2 = current_price(m, pair.ticker2)

        quantity2(n1) = round(Int, n1 * p1 * pair.γ[dayofweek(curt)] / p2)
        # quantity2(n1) = round(Int, n1 * pair.γ)

        new_pos && continue
        if curpos1 == curpos2 == 0
            
            if z_score < -pair.z_thr
                new_pos = true
                q = cash / p1 
                Entity(m, Purchase(pair.ticker1, q, OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
                Entity(m, Sale(pair.ticker2, quantity2(q), OrderType.Market, TimeInForce.GTC, 0.0, 0.0))

            elseif z_score > pair.z_thr
                new_pos = true
                q = cash / p1 
                
                Entity(m, Purchase(pair.ticker2, quantity2(q), OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
                Entity(m, Sale(pair.ticker1, q, OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
            end
        end
        
        ie - 1 == 0 && continue
        
        if any(x -> x ∉ m[Filled], @entities_in(m, Purchase || Sale))
            continue
        end
        lag_e = entity(spread_comp, ie-1)
        
        if lag_e in spread_comp && sign(v - sma.v) != sign(spread_comp[lag_e].v - sma.v)

            if curpos1 < 0.0
                Entity(m, Purchase(pair.ticker1, -curpos1, OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
            elseif curpos1 > 0.0
                Entity(m, Sale(pair.ticker1, curpos1, OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
            end

            if curpos2 < 0.0
                Entity(m, Purchase(pair.ticker2, -curpos2, OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
            elseif curpos2 > 0.0
                Entity(m, Sale(pair.ticker2, curpos2, OrderType.Market, TimeInForce.GTC, 0.0, 0.0))
            end
            new_pos = true
        end
    end
   
    for (pair, pair_es) in pools(pairs_comp)
        ledger1 = m.ticker_ledgers[pair.ticker1]
        ledger2 = m.ticker_ledgers[pair.ticker2]
        logcomp1 = ledger1[LogVal{Close}]
        logcomp2 = ledger2[LogVal{Close}]
        
        @inbounds for ie in length(spread_comp)+1:length(logcomp1)
            e1 = logcomp1[ie]
            e2 = logcomp2[ie]
            new_e = Entity(m, Spread(e1.v - pair.γ[dayofweek(curt)] * e2.v))
            pairs_comp[new_e] = pair_es[1]
        end
    end

end


function plot_simulation(l::AbstractLedger, plot_day=nothing; kwargs...)
    tstamps = map(x->DateTime(x.t), @entities_in(l, TimeStamp && PortfolioSnapshot))
    values = map(x->x.value, @entities_in(l, TimeStamp && PortfolioSnapshot))
    p = plot(tstamps, values, label="total value"; kwargs...)

    purchase_es      = filter(x->x[Order].ticker == "MSFT", @entities_in(l, Purchase && Filled && Order))
    purchase_times   = map(x->DateTime(x.filled_at), purchase_es)
    purchase_tickers = map(x->x[Order].ticker, purchase_es)

    sale_es      = filter(x->x[Order].ticker == "MSFT", @entities_in(l, Sale && Filled && Order))
    sale_times   = map(x->DateTime(x.filled_at), sale_es)
    sale_tickers = map(x->x[Order].ticker, sale_es)

    purchase_total_values = map(purchase_times) do t
        values[findmin(x -> abs(x-t), tstamps)[2]]
    end
    sale_total_values = map(sale_times) do t
        values[findmin(x -> abs(x-t), tstamps)[2]]
    end

    scatter!(p, purchase_times, purchase_total_values, marker = :utriangle, color=:green, label="purchases")
    scatter!(p, sale_times, sale_total_values, marker = :dtriangle, color=:red, label="sales")

    p = plot_day === nothing ? p : plot!(p,xlims=(DateTime.(Trading.market_open_close(plot_day))...,))
    return plot(p, plot_indicators(l,plot_day), layout=(2,1), size=(800,1200)) 
end

function plot_indicators(l::AbstractLedger, plot_day=nothing)
    ta = TimeArray(l)
    if plot_day !== nothing
        to_ = DateTime(Date(plot_day)+Day(1))
        from_ = DateTime(Date(plot_day))
        ta = to(from(ta, from_), to_)
    end
    p = plot(ta["MovingStdDev{20, Spread}"])
    plot!(p,  ta["SMA{20, Spread}"])

    plot!(p, ta["Spread"])

    plot!(p, ta["ZScore{Spread}"])
    hline!(p,  [-l[Pair][1].z_thr,l[Pair][1].z_thr], color=[:blue,:red], label="")

    for i in 1:length(l[Position])
        tstamps = map(x->DateTime(x.t), @entities_in(l, PortfolioSnapshot && TimeStamp))
        vals = map(x->x.positions[i].quantity/100, l[PortfolioSnapshot])
        if plot_day !== nothing
            to_plot = findall(x -> from_ <= x <= to_, tstamps)
            plot!(p, tstamps[to_plot], vals[to_plot], label=l[Position][i].ticker)
        else
            plot!(p, tstamps, vals, label=l[Position][i].ticker)
        end
    end
    return p
end

function pair_trader(broker, ticker1::String, ticker2::String, γ; z_thr=1.5)
    
    t = Trader(broker; tickers=[ticker1, ticker2], strategies=[Strategy(Stage(:pair, [PairStrat()]), true)])
    Entity(t, Pair(ticker1, ticker2, γ, z_thr))
   
    return t
end

function pair_trader(broker, ticker1::String, ticker2::String, start, stop, γ; z_thr=1.5)
    
    t = BackTester(broker, tickers=[ticker1, ticker2], strategies=[Strategy(Stage(:pair, [PairStrat()]), true)]; start=start, stop=stop)
    Entity(t, Pair(ticker1, ticker2, γ, z_thr))
    
    return t
end


acc = HistoricalBroker(AlpacaBroker("<key_id>", "<secret_key>"))

acc.variable_transaction_fee = 0.0
acc.fee_per_share = 0.005
acc.fixed_transaction_fee = 0.0


γ_2022 = (0.83971041721211, 0.7802162996942561, 0.8150936011572303, 0.8665354500999517, 0.8253480013737815)
γ_2021 = (0.4536879929628027, 0.6749271852655075, 0.6814251210894734, 0.44395679460564247, 0.5103055699026341)

# msft_aapl_γ = mean_daily_γ(acc, "MSFT", "AAPL", TimeDate("2023-03-01T00:00:00"), TimeDate("2023-03-31T23:59:59"))

msft_aapl_γ = γ_2021

trader = pair_trader(acc, "MSFT", "AAPL", TimeDate("2022-01-01T00:00:00"), TimeDate("2022-12-30T23:59:59"), msft_aapl_γ, z_thr=3.0)
start(trader)
plot_simulation(trader)
