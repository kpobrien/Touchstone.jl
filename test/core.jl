# Functional tests; runtests.jl also runs Aqua and Documenter.
module TouchstoneTests
using Test, Touchstone
import UUIDs

include("helpers.jl")
include("fixtures.jl")

@testset "Touchstone" begin
    include("numbers.jl")
    include("normalization.jl")
    include("parsing.jl")
    include("mixedmode.jl")
    include("writing.jl")
    include("files.jl")
    include("buffering.jl")
end
end
