# Based on documentation of DFControl and DFTK
using LibGit2: LibGit2
using Pkg: Pkg

# To manually generate the docs:
# Run "julia make.jl" to generate the docs

# Set to true to disable some checks and cleanup
DEBUG = false

# Where to get files from and where to build them
SRCPATH = joinpath(@__DIR__, "src")
BUILDPATH = joinpath(@__DIR__, "build")
ROOTPATH = joinpath(@__DIR__, "..")
CONTINUOUS_INTEGRATION = get(ENV, "CI", nothing) == "true"

JLDEPS = [Pkg.PackageSpec(;
                          url = "https://github.com/louisponet/Trading.jl.git",
                          rev = LibGit2.head(ROOTPATH))]

# Setup julia dependencies for docs generation if not yet done
Pkg.activate(@__DIR__)
Pkg.develop(Pkg.PackageSpec(; path = ROOTPATH))
Pkg.instantiate()

# Import packages for docs generation
using Trading
using Documenter

# Generate the docs in BUILDPATH
makedocs(; modules = [Trading],
         format = Documenter.HTML(
                                  # Use clean URLs, unless built as a "local" build
                                  ; prettyurls = CONTINUOUS_INTEGRATION,
                                  canonical = "https://louisponet.github.io/Trading.jl/stable/",
                                  assets = ["assets/favicon.ico"]),
         sitename = "Trading.jl", authors = "Louis Ponet",
         linkcheck_ignore = [
                             # Ignore links that point to GitHub's edit pages, as they redirect to the
                             # login screen and cause a warning:
                             r"https://github.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/edit(.*)"],
         pages = ["Home" => "index.md"])

# Deploy docs to gh-pages branch
deploydocs(; repo = "github.com/louisponet/Trading.jl.git", devbranch = "main")

if !CONTINUOUS_INTEGRATION
    println("\nDocs generated, try $(joinpath(BUILDPATH, "index.html"))")
end
