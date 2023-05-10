using TestItems

@testitem "Mock" begin
    using Trading: update
    using MarketTechnicals
    using Trading.Strategies
    using Trading.Basic
    using Trading.Indicators
    using Trading.Portfolio

    struct SlowFast <: System end

    function Overseer.requested_components(::SlowFast)
        return (SMA{50,Close}, SMA{200,Close}, Bollinger{20,Close}, RSI{14,Close},
                Sharpe{20,Close}, LogVal{Close}, RelativeDifference{Volume})
    end


    function Overseer.update(s::SlowFast, t::Trader, asset_ledgers)
        for asset_ledger in asset_ledgers
            asset = asset_ledger.asset
            for e in new_entities(asset_ledger, s)
                prev_e = prev(e, 1)

                if prev_e === nothing
                    continue
                end
                curpos = current_position(t, asset)

                sma_50  = e[SMA{50,Close}].sma
                sma_200 = e[SMA{200,Close}].sma

                prev_sma_50 = prev_e[SMA{50,Close}].sma
                prev_sma_200 = prev_e[SMA{200,Close}].sma

                if sma_50 > sma_200 && prev_sma_50 < prev_sma_200
                    Entity(t, Sale(asset, 1.0))
                elseif sma_50 < sma_200 && prev_sma_50 > prev_sma_200
                    Entity(t, Purchase(asset, 1.0))
                end
            end
        end
    end
    
    broker = Trading.HistoricalBroker(Trading.MockBroker())

    trader = Trading.BackTester(broker;
                                strategies = [Strategy(:slowfast, [SlowFast()];
                                                       assets = [Stock("stock1")])],
                                start = DateTime("2023-01-01T00:00:00"),
                                stop = DateTime("2023-01-06T00:00:00"),
                                dt = Minute(1),
                                only_day = false)

    Trading.start(trader)
    for (asset, l) in trader.asset_ledgers
        for c in (Open, Close, High, Low, Volume, TimeStamp)
            @test length(l[c]) == length(bars(broker)[(asset, Minute(1))])
        end
    end

    @test !isempty(trader[Stock("stock1")][SMA{50,Close}])

    ta = TimeArray(trader)
    close = dropnan(ta[:stock1_Close])

    @test TimeSeries.values(all(isapprox.(dropnan(ta[Symbol("stock1_RSI_14_Close")]),
                                          rsi(close), atol = 1e-10)))[1]

    bollinger_up = dropnan(ta[Symbol("stock1_Bollinger_20_up_Close")])
    bollinger_down = dropnan(ta[Symbol("stock1_Bollinger_20_down_Close")])

    bollinger_ta = bollingerbands(close)
    bollinger_ta_up = bollinger_ta[:up]
    bollinger_ta_down = bollinger_ta[:down]

    @test TimeSeries.values(all(isapprox.(bollinger_up, bollinger_ta_up, atol = 1e-10)))[1]
    @test TimeSeries.values(all(isapprox.(bollinger_down, bollinger_ta_down, atol = 1e-10)))[1]

    rets = Trading.returns(trader)
    @test 1e6 + values(sum(rets, dims=1)[:absolute])[1] == trader[PortfolioSnapshot][end].value
    @test isapprox(prod(x->1+x, values(rets[:relative])), trader[PortfolioSnapshot][end].value/1e6, atol=1e-8)
end

@testitem "Alpaca" begin
    using Trading: update
    using MarketTechnicals
    using Trading.Strategies
    using Trading.Basic
    using Trading.Indicators
    using Trading.Portfolio

    struct SlowFast <: System end

    function Overseer.requested_components(::SlowFast)
        return (SMA{50,Close}, SMA{200,Close}, Bollinger{20,Close}, RSI{14,Close},
                Sharpe{20,Close}, LogVal{Close}, RelativeDifference{Volume})
    end


    function Overseer.update(s::SlowFast, t::Trader, asset_ledgers)
        for asset_ledger in asset_ledgers
            asset = asset_ledger.asset
            for e in new_entities(asset_ledger, s)
                prev_e = prev(e, 1)

                if prev_e === nothing
                    continue
                end
                curpos = current_position(t, asset)

                sma_50  = e[SMA{50,Close}].sma
                sma_200 = e[SMA{200,Close}].sma

                prev_sma_50 = prev_e[SMA{50,Close}].sma
                prev_sma_200 = prev_e[SMA{200,Close}].sma

                if sma_50 > sma_200 && prev_sma_50 < prev_sma_200
                    Entity(t, Sale(asset, 1.0))
                elseif sma_50 < sma_200 && prev_sma_50 > prev_sma_200
                    Entity(t, Purchase(asset, 1.0))
                end
            end
        end
    end
    Overseer.requested_components(::SlowFast) = (SMA{50,Close}, SMA{200,Close}, Close, Volume)

    if haskey(ENV, "ALPACA_KEY_ID")
        @testset "Real Backtesting run" begin
            broker = HistoricalBroker(AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"]))

            trader = BackTester(broker;
                                strategies = [Strategy(:slowfast, [SlowFast()];
                                                       assets = [Stock("AAPL")]),
                                              Strategy(:slowfast, [SlowFast()];
                                                       assets = [Stock("MSFT")])],
                                start = DateTime("2023-01-01T00:00:00"),
                                stop = DateTime("2023-02-01T00:00:00"),
                                dt = Minute(1),
                                only_day = false)

            Trading.start(trader)

            totval = trader[PortfolioSnapshot][end].value
            tsnap = map(x -> x.value, trader[PortfolioSnapshot])
            tstamps = map(x -> x.t,
                          @entities_in(trader, Trading.TimeStamp && Trading.PortfolioSnapshot))

            positions = sum(x -> x.quantity, trader[PortfolioSnapshot][end].positions)
            n_purchases = length(trader[Purchase])
            n_sales = length(trader[Sale])

            @test length(trader[Trading.Filled]) == n_purchases + n_sales

            Trading.reset!(trader)

            Trading.start(trader)
            tsnap2 = map(x -> x.value, trader[PortfolioSnapshot])
            tstamps2 = map(x -> x.t,
                           @entities_in(trader, Trading.TimeStamp && Trading.PortfolioSnapshot))

            @test totval == trader[PortfolioSnapshot][end].value == 999977.1158727548
            @test positions == sum(x -> x.quantity, trader[PortfolioSnapshot][end].positions) ==
                  -2.0
            @test n_purchases == length(trader[Purchase]) == 143
            @test n_sales == length(trader[Sale]) == 145
            @test sum(tsnap .- tsnap2) == 0
            @test tstamps == tstamps2

            ta = TimeArray(trader)

            @test :AAPL_position ∈ colnames(ta)
            @test :MSFT_position ∈ colnames(ta)
            @test Symbol("AAPL_SMA_50_Close") ∈ colnames(ta)
            @test Symbol("MSFT_SMA_50_Close") ∈ colnames(ta)
            @test :portfolio_value ∈ colnames(ta)
            @test values(ta[:portfolio_value][end])[1] == trader[PortfolioSnapshot][end].value

            @test length(Trading.split(ta, day)) == 30
            @test TimeSeries.values(Trading.relative(ta)[:portfolio_value])[1] == 1

            @test Trading.sharpe(trader) == -0.23122570003378665
            @test Trading.downside_risk(trader) == 3.8349532755480495e-6
            @test Trading.value_at_risk(trader) == -6.805674895443703e-6
            @test Trading.maximum_drawdown(trader) == 3.625591382839291e-5
        end
    else
        @warn "Couldn't test alpaca based real backtesting functionality. Set ALPACA_KEY_ID and ALPACA_SECRET environment variables to trigger then."
    end
end
