using TestItems

@testitem "basics" begin
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
    l = Trading.AssetLedger(Stock("AAPL"))
    Trading.register_strategy!(l, SlowFast())

    for CT in Overseer.requested_components(SlowFast())
        @test CT in l
    end

    ss = stages(l)
    @test any(x -> x.name == :indicators, ss)
    @test Trading.SMACalculator() in ss[1].steps

    start_t = DateTime("2023-01-01T00:00:00")
    for i in 1:3000
        Trading.new_bar!(l, TimeStamp(start_t + Minute(1) * i), Open(rand()), High(rand()),
                         Low(rand()), Close(rand()), Volume(rand(Int)))
    end
    update(l)
    @test length(l[Close]) == 3000
    @test length(l[SMA{200,Close}]) == 2801
    @test length(l[SMA{50,Close}]) == 2951

    c = 0
    for e in new_entities(l, SlowFast())
        global c += 1
    end
    @test c == 2801

    new_v = rand()
    old_v = l[Open][end].v
    Trading.new_bar!(l, TimeStamp(start_t + Minute(1) * 3002), Open(new_v), High(rand()),
                     Low(rand()), Close(rand()), Volume(rand(Int)))

    @test length(l[Close]) == 3002
    @test l[Open][end].v == new_v
    @test l[Open][end-1].v == (new_v + old_v) / 2
    @test l[TimeStamp][end-1].t == start_t + Minute(1) * 3001
end
