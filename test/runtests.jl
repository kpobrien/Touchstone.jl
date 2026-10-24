using Aqua
using Documenter
using Test
using Touchstone

@testset "Method ambiguities" begin
    @test isempty(Test.detect_ambiguities(Touchstone; recursive=true))
end

# Skip Aqua and doctests on Julia development builds.
if !occursin("DEV", string(VERSION))
    @testset verbose=true "Code quality (Aqua.jl)" begin
        using Aqua
        Aqua.test_all(Touchstone; ambiguities = false, persistent_tasks=false)
    end

    @testset verbose = true "Doctests (Documenter.jl)" begin
        using Documenter

        DocMeta.setdocmeta!(Touchstone,
            :DocTestSetup,
            :(using Touchstone);
            recursive=true)
        makedocs(
            remotes = nothing,
            root = joinpath(dirname(pathof(Touchstone)), "..", "docs"),
            modules=[Touchstone],
            doctest = :only,
            sitename="Touchstone",
            format = Documenter.HTML(edit_link = nothing, disable_git = true),
            )
    end
end

include("core.jl")
