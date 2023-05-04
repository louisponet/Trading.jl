using Trading
using Trading.Strategies
using Trading.Basic
using Trading.Indicators
using Trading.Portfolio

using Plots
using GLM
using HypothesisTests
using Statistics
using ThreadPools

# using TimeSeries: rename
using Trading.Strategies: prev

function fit_γμ(account, asset1, asset2, start, stop; timeframe=Minute(1), only_day=true)
    df1 = bars(account, asset1, start, stop, timeframe=Minute(1))
    df2 = bars(account, asset2, start, stop, timeframe=Minute(1))

    if only_day
        df1 = df1[findall(x->in_day(x), timestamp(df1))]
        df2 = df2[findall(x->in_day(x), timestamp(df2))]
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

function mean_daily_γ(acc, asset1, asset2, start, stop; timeframe=Minute(1))
    df1 = bars(acc, asset1, start, stop, timeframe=Minute(1), normalize=false)
    df2 = bars(acc, asset2, start, stop, timeframe=Minute(1), normalize=false)
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

function cointegration_timearray(account, asset1, asset2, start, stop; γ=0.78, z_thr=1.5,window=20, timeframe=Minute(1), only_day=true)
    
    df1 = bars(account, asset1, start, stop, timeframe=timeframe)
    df2 = bars(account, asset2, start, stop, timeframe=timeframe)

    if only_day
        df1 = df1[findall(x->in_day(x), timestamp(df1))]
        df2 = df2[findall(x->in_day(x), timestamp(df2))]
    end
    ticksym1 = Symbol(asset1)
    ticksym2 = Symbol(asset2)
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
    
        if !in_day(timestamp)
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

@component struct Spread <: Trading.SingleValIndicator{Float64}
    v::Float64
end

struct SpreadCalculator <: System
    γ::NTuple{5, Float64}
end

Overseer.requested_components(::SpreadCalculator) = (LogVal{Close},)

function Overseer.update(s::SpreadCalculator, m::Trading.Trader, asset_ledgers)

    @assert length(asset_ledgers) == 3 "Pairs Strategy only implemented for 2 assets at a time"
    combined_ledger = asset_ledgers[end]

    curt = current_time(m)

    # We clear all data at market open
    if Trading.is_market_open(curt)
        for l in asset_ledgers[1:2]
            reset!(l, s)
        end
    end

    new_bars1 = new_entities(asset_ledgers[1], s)
    new_bars2 = new_entities(asset_ledgers[2], s)

    assets = map(x->x.asset, asset_ledgers[1:2])
    
    if length(new_bars1) != length(new_bars2)
        return
    end
    
    γ = s.γ[dayofweek(curt)]
    for (b1, b2) in zip(new_bars1, new_bars2)
        Entity(combined_ledger, Trading.TimeStamp(curt), Spread(b1.v - γ * b2.v))
    end
    update(combined_ledger)
end


function Overseer.update(s::PairStrat, m::Trading.Trader, asset_ledgers)

    curt = current_time(m)
    if Trading.is_market_open(curt)
        reset!(asset_ledgers[end], s)
    end

    cash = m[PurchasePower][1].cash
    new_pos = false
    pending_order = any(x -> x ∉ m[Filled], @entities_in(m, Purchase || Sale))

    pending_order || !in_day(curt) && return
    
    z_comp = asset_ledgers[end][ZScore{Spread}]

    asset1 = asset_ledgers[1].asset
    asset2 = asset_ledgers[2].asset
    
    γ = s.γ[dayofweek(curt)]
    
    for e in new_entities(asset_ledgers[end], s)

        v         = e.v
        sma       = e.sma
        σ         = e.σ 
        z_score   = (v - sma) / σ
        z_comp[e] = ZScore{Spread}(z_score)
        
        curpos1 = current_position(m, asset1)
        curpos2 = current_position(m, asset2)

        p1 = current_price(m, asset1)
        p2 = current_price(m, asset2)

        quantity2(n1) = round(Int, n1 * p1 * γ / p2)
        # quantity2(n1) = round(Int, n1 * pair.γ)
        in_bought_leg = curpos1 > 0
        in_sold_leg = curpos1 < 0

        new_pos && continue
            
        if z_score < -s.z_thr&& (in_sold_leg || curpos1 == 0)
            new_pos = true
            if in_sold_leg
                q = -2*curpos1
            else
                q = cash/p1
            end
            Entity(m, Purchase(asset1, q))
            Entity(m, Sale(asset2, quantity2(q)))
                

        elseif z_score > s.z_thr && (in_bought_leg || curpos1 == 0)
            new_pos = true
            if in_bought_leg 
                q = 2*curpos1
            else
                q = cash / p1
            end
            Entity(m, Purchase(asset2, quantity2(q)))
            Entity(m, Sale(asset1, q))
        end

        prev_e = prev(e, 1)
        prev_e === nothing && continue
        
        if new_pos
            continue
        end

        going_up = z_score - z_comp[prev_e].v > 0

        if z_score > 0 && in_bought_leg && !going_up
            Entity(m, Sale(asset1, curpos1))
            Entity(m, Purchase(asset2, -curpos2))
            new_pos = true
        elseif z_score < 0 && in_sold_leg && going_up
            Entity(m, Purchase(asset1, -curpos1))
            Entity(m, Sale(asset2, curpos2))
            new_pos = true
        end
    end
end

@component struct ZScore{T} <: Trading.SingleValIndicator{Float64}
    v::T
end

struct MomentumPairStrat{horizon} <: System
    γ::NTuple{5,Float64}
    z_thr::Float64
end
Overseer.requested_components(::MomentumPairStrat{horizon}) where {horizon} = (Spread, SMA{horizon, Spread},MovingStdDev{horizon, Spread})

function Overseer.update(s::MomentumPairStrat, m::Trading.Trader, asset_ledgers)

    curt = current_time(m)
    if Trading.is_market_open(curt)
        reset!(asset_ledgers[end], s)
    end
    
    !in_day(curt) && return

    cash = m[Trading.PurchasePower][1].cash
    new_pos = any(x -> x ∉ m[Filled], @entities_in(m, Purchase || Sale))
    
    asset1 = asset_ledgers[1].asset
    asset2 = asset_ledgers[2].asset
    
    γ = s.γ[dayofweek(curt)]
     
    for e in new_entities(asset_ledgers[end], s)

        v         = e.v
        sma       = e.sma
        σ         = e.σ 
        z_score   = (v - sma) / σ
        Entity(asset_ledgers[end], ZScore{Spread}(z_score))
        new_pos && continue
        
        curpos1 = current_position(m, asset1)
        curpos2 = current_position(m, asset2)

        p1 = current_price(m, asset1)
        p2 = current_price(m, asset2)

        quantity2(n1) = round(Int, n1 * p1 * γ / p2)
        # quantity2(n1) = round(Int, n1 * pair.γ)

        if curpos1 == curpos2 == 0
            
            if z_score < -s.z_thr
                new_pos = true
                q = cash / p1 
                Entity(m, Sale(asset1, q))
                Entity(m, Purchase(asset2, quantity2(q)))

            elseif z_score > s.z_thr
                new_pos = true
                q = cash / p1 
                
                Entity(m, Sale(asset2, quantity2(q)))
                Entity(m, Purchase(asset1, q))
            end
        end

        prev_e = prev(e, 1)
        @info prev_e
        prev_e === nothing && continue
        
        if new_pos
            continue
        end
        @info prev_e
        if sign(v - sma.v) != sign(prev_e.v - prev_e.sma.v)

            if curpos1 < 0.0
                Entity(m, Purchase(asset1, -curpos1))
                new_pos = true
            elseif curpos1 > 0.0
                Entity(m, Sale(asset1, curpos1))
                new_pos = true
            end

            if curpos2 < 0.0
                Entity(m, Purchase(asset2, -curpos2))
                new_pos = true
            elseif curpos2 > 0.0
                Entity(m, Sale(asset2, curpos2))
                new_pos = true
            end
            
        end
    end
end


function plot_simulation(l::AbstractLedger, start=l[TimeStamp][1].t, stop=l[TimeStamp][end].t; kwargs...)
    tstamps = map(x->DateTime(x.t), @entities_in(l, TimeStamp && PortfolioSnapshot))
    values = map(x->x.value, @entities_in(l, TimeStamp && PortfolioSnapshot))
    values ./= values[1]
    p = plot(tstamps, values, label="total value"; kwargs...)
    
    msft_closes = to(from(bars(l.broker)[("MSFT", Minute(1))][:c], start), stop)
    msft_closes = msft_closes ./ TimeSeries.values(msft_closes)[1]
    aapl_closes = to(from(bars(l.broker)[("AAPL", Minute(1))][:c], start),stop)
    aapl_closes  = aapl_closes ./ TimeSeries.values(aapl_closes)[1]
    plot!(p, msft_closes, label = "MSFT")
    plot!(p, aapl_closes, label = "AAPL")
    
    purchase_es      = filter(x->x[Trading.Order].asset == "MSFT", @entities_in(l, Purchase && Filled && Trading.Order))
    purchase_times   = map(x->DateTime(x.filled_at), purchase_es)
    purchase_assets = map(x->x[Trading.Order].asset, purchase_es)

    sale_es      = filter(x->x[Trading.Order].ticker == "MSFT", @entities_in(l, Sale && Filled && Trading.Order))
    sale_times   = map(x->DateTime(x.filled_at), sale_es)
    sale_assets = map(x->x[Trading.Order].asset, sale_es)

    purchase_total_values = map(purchase_times) do t
        values[findmin(x -> abs(x-t), tstamps)[2]]
    end
    sale_total_values = map(sale_times) do t
        values[findmin(x -> abs(x-t), tstamps)[2]]
    end

    scatter!(p, purchase_times, purchase_total_values, marker = :utriangle, color=:green, label="purchases")
    scatter!(p, sale_times, sale_total_values, marker = :dtriangle, color=:red, label="sales")

    plot!(p, xlims=(start,stop))
    return plot(p, plot_indicators(l,start,stop), layout=(2,1), size=(800,1200)) 
end

function plot_indicators(l::AbstractLedger, start=l[TimeStamp][1].t, stop=l[TimeStamp][end].t)
    
    ta = to(from(TimeArray(l["MSFT_AAPL"]), start), stop)
    p = plot(ta["MovingStdDev{20, Spread}"])
    plot!(p,  ta["SMA{20, Spread}"])

    plot!(p, ta["Spread"])

    plot!(p, ta["ZScore{Spread}"])
    # hline!(p,  [-l[Pair][1].z_thr,l[Pair][1].z_thr], color=[:blue,:red], label="")

    ta2 = TimeArray(l)
    plot!(p, to(from(merge(ta2[:AAPL_position]./1000, ta2[:MSFT_position]./1000, method=:outer), start),stop))
    return p
end

function pair_trader(broker, asset1::String, asset2::String, γ; z_thr=1.5, momentum = true)

    stratsys = momentum ? [SpreadCalculator(γ), MomentumPairStrat{20}(γ, z_thr)] : [SpreadCalculator(γ), PairStrat{20}(γ, z_thr)]
    t = Trader(broker; assets=[asset1, asset2], strategies=[Strategy(:pair, stratsys, assets=[Stock("MSFT"), Stock("AAPL")])])
   
    return t
end

function pair_trader(broker, asset1::String, asset2::String, start, stop, γ; z_thr=1.5, momentum=true)
    
    stratsys = momentum ? [SpreadCalculator(γ), MomentumPairStrat{20}(γ, z_thr)] : [SpreadCalculator(γ), PairStrat{20}(γ, z_thr)]
    
    t = BackTester(broker; strategies=[Strategy(:pair, stratsys, assets=[Stock("MSFT"), Stock("AAPL")])], start=start, stop=stop)
    
    return t
end


# acc = HistoricalBroker(AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"]))

# acc.variable_transaction_fee = 0.0
# acc.fee_per_share = 0.005
# acc.fixed_transaction_fee = 0.0


# γ_2022 = (0.83971041721211, 0.7802162996942561, 0.8150936011572303, 0.8665354500999517, 0.8253480013737815)
# γ_2021 = (0.4536879929628027, 0.6749271852655075, 0.6814251210894734, 0.44395679460564247, 0.5103055699026341)

# msft_aapl_γ = mean_daily_γ(acc, "MSFT", "AAPL", TimeDate("2023-03-01T00:00:00"), TimeDate("2023-03-31T23:59:59"))

# msft_aapl_γ = γ_2021

# trader = pair_trader(acc, "MSFT", "AAPL", TimeDate("2022-01-01T00:00:00"), TimeDate("2022-12-30T23:59:59"), msft_aapl_γ, z_thr=3.0)
# start(trader)
# plot_simulation(trader)
