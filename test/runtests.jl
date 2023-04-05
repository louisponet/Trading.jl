using Trading
using Test

broker = Trading.HistoricalBroker(Trading.MockBroker())

# @test_throws ErrorException trader = Trading.BackTester(broker;
#                             tickers = ["stock1", "stock2"],
#                             start = DateTime("2023-01-01T00:00:00"),
#                             stop = DateTime("2023-01-02T00:00:00"),
#                             dt=Minute(1))

broker = Trading.HistoricalBroker(Trading.MockBroker())
trader = Trading.BackTester(broker;
                            tickers = ["stock1", "stock2"],
                            start = DateTime("2023-01-01T00:00:00"),
                            stop = DateTime("2023-01-02T00:00:00"),
                            dt=Minute(1),
                            only_day=false)

Trading.start(trader)
for (ticker, l) in trader.ticker_ledgers
    for c in (Trading.Open, Trading.Close, Trading.High, Trading.Low, Trading.Volume, Trading.TimeStamp)
        # -1 because bars start streaming in at minute 1
        @test length(l[c]) == length(Trading.bars(broker)[(ticker, Minute(1))]) - 1
    end
end

n_bars_in_day = length(findall(x->Trading.in_day(x), timestamp(Trading.bars(broker)[("stock1", Minute(1))])))

@test n_bars_in_day == length(trader[Trading.PortfolioSnapshot])
