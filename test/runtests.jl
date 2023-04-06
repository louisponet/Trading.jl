using Trading
using Test

using Trading.Strategies
using Trading.Core
using Trading.Indicators
using Trading.Portfolio

struct SlowFast <: System end
Overseer.requested_components(::Type{SlowFast}) = (SMA{50, Close}, SMA{200, Close}, Close, Volume)

@testset "Ticker Ledger" begin
    l = Trading.TickerLedger("AAPL")
    Trading.register_strategy!(l, SlowFast())

    for CT in Overseer.requested_components(SlowFast)
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

@testset "Full Backtesting run" begin
    broker = Trading.HistoricalBroker(Trading.MockBroker())


    struct SlowFast <: System end
    Overseer.requested_components(::Type{SlowFast}) = (SMA{50, Close}, SMA{200, Close}, Close, Volume)

    function Overseer.update(s::SlowFast, t::Trader)
        for (ticker, ticker_ledger) in t.ticker_ledgers
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

    trader = Trading.BackTester(broker;
                                strategies = [Strategy(:slowfast, [SlowFast()], false) => ["stock1", "stock2"]],
                                start = DateTime("2023-01-01T00:00:00"),
                                stop = DateTime("2023-01-06T00:00:00"),
                                dt=Minute(1),
                                only_day=false)

    Trading.start(trader)
    for (ticker, l) in trader.ticker_ledgers
        for c in (Open, Close, High, Low, Volume, TimeStamp)
            @test length(l[c]) == length(bars(broker)[(ticker, Minute(1))]) - 1
        end
    end

    @test !isempty(trader["stock1"][SMA{50, Close}])
    n_bars_in_day = length(findall(x->Trading.in_day(x), timestamp(Trading.bars(broker)[("stock1", Minute(1))])))

    @test n_bars_in_day == length(trader[Trading.PortfolioSnapshot])
end

