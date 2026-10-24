# Touchstone.jl

[![Code coverage](https://codecov.io/gh/kpobrien/Touchstone.jl/branch/main/graphs/badge.svg)](https://codecov.io/gh/kpobrien/Touchstone.jl)
[![Build Status](https://github.com/kpobrien/Touchstone.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/kpobrien/Touchstone.jl/actions?query=workflow) [![Dev docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://kpobrien.github.io/Touchstone.jl/dev/reference/)

Save and load network parameters in Touchstone® versions 1.0, 1.1, 2.0, and 2.1. Touchstone® is a registered trademark of Agilent Technologies, Inc.

# Installation:

To install the latest release of the package, install Julia using [Juliaup](https://github.com/JuliaLang/juliaup), start Julia, and enter the following command:
```
using Pkg
Pkg.add("Touchstone")
```

To install the development version, start Julia and enter the command:
```
using Pkg
Pkg.add(name="Touchstone",rev="main")
```

If you get errors when running the examples, please try installing the latest version of Julia and updating to the latest version of Touchstone.jl by running:
```
Pkg.update()
```

Then check that you are running the latest version of the package with:
```
Pkg.status()
```

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

julia> example1 = touchstone_load("example1.s1p");

julia> example1.f, example1.version
([2.0e6], 1.0)

julia> touchstone_save("example1_saved.s1p", example1)
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

julia> example2 = touchstone_load("example2.ts");

julia> example2.f, example2.version
([2.0e6], 2.0)

julia> touchstone_save("example2_saved.ts", example2)
```

# Writing and validation

Use keyword arguments `version=2.1` to write `[Version] 2.1` files. Versions 2.0 and
2.1 share the same formatting rules. The constructor and array stream-writer
defaults are version 2.0; the array file-save default is version 1.0. Saving
a `TouchstoneFile` struct preserves the version.

Explicit filename extensions are preserved. When no extension is supplied,
`.sNp` is appended for versions 1.0 and 1.1, and `.ts` for versions 2.0 and 2.1,
where `N` is the number of ports. The Touchstone 2.1 specification permits
`.ts` for all versions and allows other extensions.

`touchstone_save(filename, ts)` and `Touchstone.touchstone_write(io, ts)`
serialize `ts.f` (Hz), `ts.N` (network parameters), and metadata.
They retain the version, representation, references, mixed-mode order, noise,
information, and comments. Use the array forms to select metadata explicitly.
Changing `R` or `reference` does not renormalize S parameters: the references
must describe the supplied `N`. Similarly, `mixedmodeorder` describes the
supplied data without performing a mixed-mode transformation.
The object stores network data as `f` and `N`. `ts.noisedata` uses five values
per frequency: frequency in the selected file unit, minimum noise figure in dB,
reflection-coefficient magnitude, angle in degrees, and noise resistance in ohms.

Use RI or MA for exact zeros (not dB). Upper and Lower matrix formats require
exact transpose symmetry. Use Full to preserve an asymmetric matrix. Inputs
outside the representable Float64 range result in errors.

See [CHANGELOG.md](CHANGELOG.md) for compatibility changes.

# Version 1 normalization

Version 1.0 files use one reference resistance `R` for all ports. Version 1.1
files allow one positive reference resistance per port at the end of the option
line, for example `# GHz S RI R 50 75`. Use keyword arguments `version=1.1, reference=[50.0,75.0]`
when writing a version 1.1 two-port file. The first reference sets `R` and normalizes
the noise resistance. Files with multiple option-line resistances are identified as
version 1.1 while files with a single resistance, including a one-port file,
are reported as 1.0 files.

Loaded parameters use physical units. For file entries `s`, `z`, `y`, `h`,
and `g`, with port resistances `r1`, …, `rn`, the conversions are:

| Parameter | Physical value |
| --- | --- |
| Sij | sij |
| Zij | zij × sqrt(ri rj) |
| Yij | yij / sqrt(ri rj) |
| H11, H22 | h11 × r1, h22 / r2 |
| H12, H21 | h12 × sqrt(r1/r2), h21 × sqrt(r1/r2) |
| G11, G22 | g11 / r1, g22 × r2 |
| G12, G21 | g12 × sqrt(r2/r1), g21 × sqrt(r2/r1) |

For version 1.0, every `ri` equals `R`, so H/G off-diagonal entries are
unscaled. Noise resistance is returned in ohms. Versions 2.0 and 2.1 store physical
parameters directly. These conversions follow the
[IBIS matrix-parameter derivation](https://ibis.org/summits/feb24/ross2.pdf).

# Contributing:

See [source organization](src/README.md) for implementation responsibilities and
[tests](test/README.md) for the test layout and commands.

We welcome contributions in the form of issues/bug reports or pull requests.
This project uses the [MIT open source license](https://opensource.org/license/MIT).

# References:

1. [Legacy Touchstone specification, document revision 1.1](http://www.ibis.org/connector/touchstone_spec11.pdf)
2. [Touchstone v2.0](http://www.ibis.org/touchstone_ver2.0/touchstone_ver2_0.pdf)
3. [Touchstone v2.1](https://ibis.org/touchstone_ver2.1/touchstone_ver2_1.pdf)
