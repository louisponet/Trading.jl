using Trading
using Test

using Trading.Strategies
using Trading.Basic
using Trading.Indicators
using Trading.Portfolio

struct SlowFast <: System end
    
Overseer.requested_components(::SlowFast) = (SMA{50, Close}, SMA{200, Close}, Close, Volume)

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
end

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
    tstamps = map(x->x.t, trader[Trading.TimeStamp])
    
    positions = sum(x->x.quantity, trader[PortfolioSnapshot][end].positions)
    n_purchases = length(trader[Purchase]) 
    n_sales = length(trader[Sale])

    @test length(trader[Trading.Filled]) == n_purchases + n_sales

    Trading.reset!(trader)

    Trading.start(trader)
    tsnap2 = map(x->x.value, trader[PortfolioSnapshot])
    tstamps2 = map(x->x.t, trader[Trading.TimeStamp])


    @test totval == trader[PortfolioSnapshot][end].value == 99977.11587275469
    @test positions == sum(x->x.quantity, trader[PortfolioSnapshot][end].positions) == -2.0
    @test n_purchases == length(trader[Purchase]) == 143
    @test n_sales == length(trader[Sale]) == 145
    @test sum(tsnap .- tsnap2) == 0
    @test tstamps == tstamps2 

    
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
    while trader[Trading.Order][e].status == "accepted" && tries <= 300
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

