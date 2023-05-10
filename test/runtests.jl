using TestItemRunner
@run_package_tests

using Documenter
usings = quote
    using Trading
    using Trading.Strategies
    using Trading.Basic
    using Trading.Indicators
    using Trading.Portfolio
end
using Trading
DocMeta.setdocmeta!(Trading, :DocTestSetup, usings; recursive = true)
doctest(Trading)
