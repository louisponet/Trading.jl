# Trading

## Trader
```@docs
Trading.Trader
```

## Brokers

```@docs
Trading.AbstractBroker
Trading.AlpacaBroker
Trading.HistoricalBroker
Trading.MockBroker
```

## Portfolio

### Data
```@docs
Trading.Cash
Trading.PurchasePower
Trading.Position
Trading.Purchase
Trading.Sale
Trading.Order
Trading.Filled
Trading.PortfolioSnapshot
```
### Systems
```@docs
Trading.Purchaser
Trading.Seller
Trading.Filler
Trading.DayCloser
Trading.SnapShotter
```

## Bars

```@docs
Trading.Open
Trading.High
Trading.Low
Trading.Close
Trading.Volume
```

## Indicators

### Data

```@docs
Trading.SMA
Trading.MovingStdDev
Trading.EMA
Trading.RSI
Trading.Bollinger
Trading.Sharpe
```
### Systems
```@docs
Trading.SMACalculator
Trading.MovingStdDevCalculator
Trading.EMACalculator
Trading.RSICalculator
Trading.BollingerCalculator
Trading.SharpeCalculator
```

## General Data

```@docs
Trading.LogVal
Trading.Difference
Trading.RelativeDifference

Trading.LogValCalculator
Trading.DifferenceCalculator
Trading.RelativeDifferenceCalculator
```

