using Test, Documenter, Touchstone

makedocs(
    root = joinpath(dirname(pathof(Touchstone)), "..", "docs"),
    modules=[Touchstone],
    doctest = false,
    sitename="Touchstone",
    format = Documenter.HTML(edit_link = nothing, disable_git = true,size_threshold_ignore = ["reference.md"]),
    )

deploydocs(
   repo = "github.com/kpobrien/Touchstone.jl.git",
)
