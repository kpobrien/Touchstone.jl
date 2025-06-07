# Touchstone.jl

[![Code coverage](https://codecov.io/gh/kpobrien/Touchstone.jl/branch/main/graphs/badge.svg)](https://codecov.io/gh/kpobrien/Touchstone.jl)
[![Build Status](https://github.com/kpobrien/Touchstone.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/kpobrien/Touchstone.jl/actions?query=workflow) [![Dev docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://kpobrien.github.io/Touchstone.jl/dev/reference/)

Save and load network parameters in the Touchstone® file format. Touchstone® is a registered trademark of Agilent Technologies, Inc.

# Examples:
## Load and save a Touchstone file
Version 1
```julia
julia> using Touchstone

julia> open("example1.s1p","w") do file
write(file,
"!Example 1:
!1-port S-parameter file, single frequency point
# MHz S MA R 50
!freq magS11 angS11
2.000 0.894 -12.136")
end

julia> example1 = touchstone_load("example1.s1p")
Touchstone.TouchstoneFile([2.0e6], ComplexF64[0.874020294860635 - 0.18794819544685323im;;;], "mhz", "s", "ma", 50.0, 1.0, 1, "12_21", 1, 0, [50.0], String[], "Full", Tuple{Char, Vector{Int64}}[], ["Example 1:", "1-port S-parameter file, single frequency point", "freq magS11 angS11"], [2.0, 0.894, -12.136], Float64[])

julia> touchstone_save("example1_saved.s1p", example1.f, example1.N, version=1.0)
```

Version 2
```julia
julia> using Touchstone

julia> open("example2.ts","w") do file
write(file,
"!Example 1:
!1-port S-parameter file, single frequency point
[Version] 2.0
# Hz S RI R 50.0
[Number of Ports] 1
[Number of Frequencies] 1
[Reference] 50.0
[Network Data]
! freq ReS11 ImS11 
2.0e6 0.874020294860635 -0.18794819544685323
[End]")
end

julia> example2 = touchstone_load("example2.ts")
Touchstone.TouchstoneFile([2.0e6], ComplexF64[0.874020294860635 - 0.18794819544685323im;;;], "mhz", "s", "ma", 50.0, 1.0, 1, "12_21", 1, 0, [50.0], String[], "Full", Tuple{Char, Vector{Int64}}[], ["Example 1:", "1-port S-parameter file, single frequency point", "freq magS11 angS11"], [2.0, 0.894, -12.136], Float64[])

julia> touchstone_save("example2_saved.ts", example2.f, example2.N, version=2.0)
```

# Contributing:

We welcome contributions in the form of issues/bug reports or pull requests. This project uses the [MIT open source license](https://opensource.org/license/MIT). You retain the copyright to any code you contribute.

# References:

1. [Touchstone v1.1](http://www.ibis.org/connector/touchstone_spec11.pdf)
2. [Touchstone v2.0](http://www.ibis.org/touchstone_ver2.0/touchstone_ver2_0.pdf)
3. [Touchstone v2.1](https://ibis.org/touchstone_ver2.1/touchstone_ver2_1.pdf)
