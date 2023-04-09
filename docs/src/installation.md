# Getting Started
```@meta
CurrentModule=Trading
```
Since the package is registered, you can simply install it using
```julia
using Pkg
Pkg.add("Trading")
```

After this, it is recommended to set up a [`Broker`](@ref Brokers).
For the moment only [Alpaca](https://alpaca.markets) is supported, and to make the
API work, you'll need to [generate a set of api keys](https://alpaca.markets/docs/market-data/getting-started/#creating-an-alpaca-account-and-finding-your-api-keys).

Then you can create an [`AlpacaBroker`](@ref) and you're good to go.

See [`the strategies tutorial`](@ref Strategies) to continue with creating and backtesting a strategy.
