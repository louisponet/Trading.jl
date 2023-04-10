using Trading
using Trading: update
using Test
using MarketTechnicals
using Trading.Strategies
using Trading.Basic
using Trading.Indicators
using Trading.Portfolio

struct SlowFast <: System end
    
Overseer.requested_components(::SlowFast) = (SMA{50, Close}, SMA{200, Close}, Bollinger{20, Close}, RSI{14, Close}, Sharpe{20, Close}, LogVal{Close}, RelativeDifference{Volume})


@testset "Ticker Ledger" begin
    l = Trading.TickerLedger("AAPL")
    Trading.register_strategy!(l, SlowFast())

    for CT in Overseer.requested_components(SlowFast())
        @test CT in l
    end

    ss = stages(l) 
    @test any(x->x.name == :indicators, ss)
    @test Trading.SMACalculator() in ss[1].steps

    for i = 1:3000
        Trading._Entity(l, Close(rand()), Volume(rand(Int)))
    end
    update(l)
    @test length(l[Close]) == 3000
    @test length(l[SMA{200, Close}]) == 2801
    @test length(l[SMA{50, Close}])  == 2951

    c = 0
    for e in new_entities(l, SlowFast())
        c += 1
    end
    @test c == 2801
end

if haskey(ENV, "ALPACA_KEY_ID")
    @testset "Brokers" begin

        @test_throws Trading.AuthenticationException AlpacaBroker("asdfasf", "Adsfasdf")
        alpaca_broker = AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"])

        b = bars(alpaca_broker, "AAPL", DateTime("2023-01-10T15:30:00"), DateTime("2023-01-10T15:35:00"), timeframe=Minute(1), normalize=false)
        @test length(b) == 6

        @test haskey(bars(alpaca_broker), ("AAPL", Minute(1)))
        b = bars(alpaca_broker, "AAPL", DateTime("2023-01-10T15:28:00"), DateTime("2023-01-10T15:37:00"), timeframe=Minute(1), normalize=false)
        @test length(b) == 10
        @test timestamp(b)[1] == DateTime("2023-01-10T15:28:00")
        @test timestamp(b)[end] == DateTime("2023-01-10T15:37:00")

        b = bars(alpaca_broker, "AAPL", DateTime("2023-01-10T16:28:00"), DateTime("2023-01-10T16:37:00"), timeframe=Minute(1), normalize=false)
        @test length(b)==10
        @test length(bars(alpaca_broker)[("AAPL", Minute(1))]) == 20

        int_b = Trading.interpolate_timearray(bars(alpaca_broker)[("AAPL", Minute(1))])
        @test length(int_b) == 70
        tstamps = timestamp(int_b)
        @test all(x-> x ∈ tstamps, DateTime("2023-01-10T15:28:00"):Minute(1):DateTime("2023-01-10T16:37:00"))
    end
else
    @warn "Couldn't test ALPACA functionality. Set ALPACA_KEY_ID and ALPACA_SECRET environment variables to trigger then."
end

function Overseer.update(s::SlowFast, t::Trader, ticker_ledgers)
    for ticker_ledger in ticker_ledgers
        ticker = ticker_ledger.ticker
        for e in new_entities(ticker_ledger, s)
            lag_e = lag(e, 1)
            
            if lag_e === nothing
                continue
            end
            curpos = current_position(t, ticker)

            sma_50  = e[SMA{50, Close}].sma
            sma_200 = e[SMA{200, Close}].sma
            
            lag_sma_50 = lag_e[SMA{50, Close}].sma
            lag_sma_200 = lag_e[SMA{200, Close}].sma

            if sma_50 > sma_200 && lag_sma_50 < lag_sma_200
                Entity(t, Sale(ticker, 1.0))
            elseif sma_50 < sma_200 && lag_sma_50 > lag_sma_200
                Entity(t, Purchase(ticker, 1.0))
            end
        end
    end
end

@testset "Mock Backtesting run" begin
    broker = Trading.HistoricalBroker(Trading.MockBroker())


    trader = Trading.BackTester(broker;
                                strategies = [Strategy(:slowfast, [SlowFast()], tickers=["stock1"])],
                                start = DateTime("2023-01-01T00:00:00"),
                                stop = DateTime("2023-01-06T00:00:00"),
                                dt=Minute(1),
                                only_day=false)

    Trading.start(trader)
    for (ticker, l) in trader.ticker_ledgers
        for c in (Open, Close, High, Low, Volume, TimeStamp)
            @test length(l[c]) == length(bars(broker)[(ticker, Minute(1))])
        end
    end

    @test !isempty(trader["stock1"][SMA{50, Close}])

    ta = TimeArray(trader)
    close = dropnan(ta[:stock1_Close])

    @test TimeSeries.values(all(isapprox.(dropnan(ta[Symbol("stock1_RSI{14, Close}")]), rsi(close), atol=1e-10)))[1]

    bollinger_up = dropnan(ta[Symbol("stock1_Bollinger{20, Close}_up")])
    bollinger_down = dropnan(ta[Symbol("stock1_Bollinger{20, Close}_down")])

    bollinger_ta = bollingerbands(close)
    bollinger_ta_up = bollinger_ta[:up]
    bollinger_ta_down = bollinger_ta[:down]
    
    @test TimeSeries.values(all(isapprox.(bollinger_up, bollinger_ta_up, atol=1e-10)))[1]
    @test TimeSeries.values(all(isapprox.(bollinger_down, bollinger_ta_down, atol=1e-10)))[1]
end

Overseer.requested_components(::SlowFast) = (SMA{50, Close}, SMA{200, Close}, Close, Volume)
if haskey(ENV, "ALPACA_KEY_ID")
    @testset "Real Backtesting run" begin
        broker = HistoricalBroker(AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"]))


        trader = BackTester(broker;
                            strategies = [Strategy(:slowfast, [SlowFast()], tickers=["AAPL"]),
                                          Strategy(:slowfast, [SlowFast()], tickers=["MSFT"])],
                            start = DateTime("2023-01-01T00:00:00"),
                            stop = DateTime("2023-02-01T00:00:00"),
                            dt=Minute(1),
                            only_day=false)

        Trading.start(trader)

        totval = trader[PortfolioSnapshot][end].value
        tsnap = map(x->x.value, trader[PortfolioSnapshot])
        tstamps = map(x->x.t, @entities_in(trader, Trading.TimeStamp && Trading.PortfolioSnapshot))
        
        positions = sum(x->x.quantity, trader[PortfolioSnapshot][end].positions)
        n_purchases = length(trader[Purchase]) 
        n_sales = length(trader[Sale])

        @test length(trader[Trading.Filled]) == n_purchases + n_sales

        Trading.reset!(trader)

        Trading.start(trader)
        tsnap2 = map(x->x.value, trader[PortfolioSnapshot])
        tstamps2 = map(x->x.t, @entities_in(trader, Trading.TimeStamp && Trading.PortfolioSnapshot))

        @test totval == trader[PortfolioSnapshot][end].value == 999977.1158727548
        @test positions == sum(x->x.quantity, trader[PortfolioSnapshot][end].positions) == -2.0
        @test n_purchases == length(trader[Purchase]) == 143
        @test n_sales == length(trader[Sale]) == 145
        @test sum(tsnap .- tsnap2) == 0
        @test tstamps == tstamps2

        ta = TimeArray(trader)

        @test :AAPL_position ∈ colnames(ta)
        @test :MSFT_position ∈ colnames(ta)
        @test Symbol("AAPL_SMA{50, Close}") ∈ colnames(ta)
        @test Symbol("MSFT_SMA{50, Close}") ∈ colnames(ta)
        @test :value ∈ colnames(ta)
        @test values(ta[:value][end])[1] == trader[PortfolioSnapshot][end].value

        @test length(Trading.split_days(ta)) == 30
        @test values(Trading.relative(ta)[:value])[1] == 1
        
    end

    @testset "Order" begin
        broker = AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"])

        trader = Trader(broker)

        Trading.start(trader)

        while !trader.is_trading
            sleep(0.1)
        end
        e = Entity(trader, Purchase("AAPL", 1))
        while e ∉ trader[Trading.Order]
            sleep(0.001)
        end

        Trading.delete_all_orders!(trader)
        tries = 0
        while trader[Trading.Order][e].status ∈ ("accepted", "new") && tries <= 300
            sleep(0.1)
            tries += 1
        end
        @test tries <= 300

        @test trader[Trading.Order][e].status ∈ ("filled", "canceled")
        if trader[Trading.Order][e].status == "filled"
            e2 = Entity(trader, Trading.Sale("AAPL", 1))
            while e ∉ trader[Trading.Order]
                sleep(0.001)
            end
        end
        
        
    end
end

using Documenter
usings = quote
    using Trading
    using Trading.Strategies
    using Trading.Basic
    using Trading.Indicators
    using Trading.Portfolio
end 

DocMeta.setdocmeta!(Trading, :DocTestSetup, usings; recursive=true)
doctest(Trading)
