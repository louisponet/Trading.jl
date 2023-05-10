using TestItems

@testitem "api" begin
    if haskey(ENV, "ALPACA_KEY_ID")
        @testset "Brokers" begin
            @test_throws Trading.AuthenticationException AlpacaBroker("asdfasf", "Adsfasdf")
            alpaca_broker = AlpacaBroker(ENV["ALPACA_KEY_ID"], ENV["ALPACA_SECRET"])
            b = bars(alpaca_broker, Stock("AAPL"), DateTime("2023-01-10T15:30:00"),
                     DateTime("2023-01-10T15:35:00"); timeframe = Minute(1), normalize = false)
            @test length(b) == 6
            @test haskey(bars(alpaca_broker), (Stock("AAPL"), Minute(1)))
            b = bars(alpaca_broker, Stock("AAPL"), DateTime("2023-01-10T15:28:00"),
                     DateTime("2023-01-10T15:37:00"); timeframe = Minute(1), normalize = false)
            @test length(b) == 10
            @test timestamp(b)[1] == DateTime("2023-01-10T15:28:00")
            @test timestamp(b)[end] == DateTime("2023-01-10T15:37:00")
            b = bars(alpaca_broker, Stock("AAPL"), DateTime("2023-01-10T16:28:00"),
                     DateTime("2023-01-10T16:37:00"); timeframe = Minute(1), normalize = false)
            @test length(b) == 10
            @test length(bars(alpaca_broker)[(Stock("AAPL"), Minute(1))]) == 20
            int_b = Trading.interpolate_timearray(bars(alpaca_broker)[(Stock("AAPL"), Minute(1))])
            @test length(int_b) == 70
            tstamps = timestamp(int_b)
            @test all(x -> x ∈ tstamps,
                      DateTime("2023-01-10T15:28:00"):Minute(1):DateTime("2023-01-10T16:37:00"))
        end
    else
        @warn "Couldn't test ALPACA functionality. Set ALPACA_KEY_ID and ALPACA_SECRET environment variables to trigger then."
    end
end
