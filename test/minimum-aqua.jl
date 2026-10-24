using Pkg

Pkg.activate(; temp=true)
Pkg.develop(path=dirname(@__DIR__))
Pkg.add([PackageSpec(name="Aqua", version=v"0.8.0"),
    PackageSpec(name="Documenter", version="1"),
    PackageSpec(name="Test"), PackageSpec(name="UUIDs")])

using Aqua
@assert pkgversion(Aqua) == v"0.8.0"
include("runtests.jl")
