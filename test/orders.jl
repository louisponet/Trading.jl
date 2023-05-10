using TestItems

@testitem "Alpaca" begin
    using Trading.Portfolio
    if haskey(ENV, "ALPACA_KEY_ID")
        broker = AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"])

        trader = Trader(broker)

        Trading.start(trader)

        while !trader.is_trading
            sleep(0.1)
        end
        e = Entity(trader, Purchase(Stock("AAPL"), 1))
        while e ∉ trader[Trading.Order]
            sleep(0.001)
        end

        Trading.delete_all_orders!(trader)
        tries = 0
        while trader[Trading.Order][e].status ∈ ("accepted", "new") && tries <= 300
            sleep(0.1)
            global tries += 1
        end
        @test tries <= 300

        @test trader[Trading.Order][e].status ∈ ("filled", "canceled")
        if trader[Trading.Order][e].status == "filled"
            e2 = Entity(trader, Trading.Sale(Stock("AAPL"), 1))
            while e ∉ trader[Trading.Order]
                sleep(0.001)
            end
        end
    else
        @warn "Couldn't test alpaca based orders. Set ALPACA_KEY_ID and ALPACA_SECRET environment variables to trigger then."
    end
end
