"""
    TouchstoneFile{F<:AbstractVector{Float64}, A<:AbstractArray{ComplexF64,3}}
    TouchstoneFile(f::F, N::A, frequencyunit::String, parameter::String,
        format::String, R::Float64, version::Float64, numberofports::Int,
        twoportdataorder::String, numberoffrequencies::Int,
        numberofnoisefrequencies::Int, reference::Vector{Float64},
        information::Vector{String}, matrixformat::String,
        mixedmodeorder::Vector{Tuple{Char, Vector{Int}}},
        comments::Vector{String}, noisedata::Vector{Float64})

Store network parameters and Touchstone metadata. The type parameters `F`
and `A` are the storage types of `f` and `N`, respectively. Use
[`touchstone_load`](@ref), [`touchstone_parse`](@ref), or
[`touchstone_file`](@ref) to construct a validated object; the positional
constructor stores its arguments without validation or copying.

The fields, in constructor order, are:

- `f`: network frequencies in Hz, regardless of `frequencyunit`.
- `N`: complex network parameters with size
  `(numberofports, numberofports, numberoffrequencies)`. S parameters are
  dimensionless, Z parameters are in ohms, and Y parameters are in siemens.
  For H parameters, `N[1,1,:]` is in ohms and `N[2,2,:]` in siemens;
  for G parameters these units are reversed. Off-diagonal H/G entries are
  dimensionless. Version 1 normalization is removed when reading.
- `frequencyunit`: the file unit, `"Hz"`, `"kHz"`, `"MHz"`, or `"GHz"`.
  This also specifies the units of frequencies in `noisedata`; `f` remains in Hz.
- `parameter`: the parameter family, `"S"`, `"Y"`, `"Z"`, `"H"`, or `"G"`.
  H and G require two ports. Parameter, frequency-unit, and format names are
  case insensitive.
- `format`: the file representation, `"RI"` (real/imaginary), `"MA"`
  (magnitude/angle), or `"DB"` (20 log10 magnitude/angle). Angles are in degrees.
- `R`: the positive option-line reference resistance in ohms. For version 1.1,
  this is the reference resistance of port 1.
- `version`: `1.0`, `1.1`, `2.0`, or `2.1`. Multiple option-line resistances identify
  version 1.1 on reading. A single resistance is indistinguishable from version
  1.0, including for one-port files, and is reported as `1.0`.
- `numberofports`: the number of rows and columns of each network matrix.
- `twoportdataorder`: `"12_21"` or `"21_12"`, specifying the order of the
  off-diagonal entries in two-port data. Version 1 uses `"21_12"` for two
  ports; other port counts use `"12_21"`.
- `numberoffrequencies`: the number of network frequency records, `length(f)`.
- `numberofnoisefrequencies`: the number of noise records, `length(noisedata) ÷ 5`.
- `reference`: one positive reference impedance in ohms per physical port.
  Version 1.0 requires every value to equal `R`. Version 1.1 stores these
  values on the option line and uses them for normalization; version 2 stores
  them under `[Reference]` and uses them only for port references.
- `information`: lines in the version 2 information section, with their case
  preserved and comments stored separately.
- `matrixformat`: `"Full"`, `"Upper"`, or `"Lower"`. Triangular file formats
  represent transpose-symmetric matrices; `N` always contains the full matrix.
  Version 1 requires `"Full"`.
- `mixedmodeorder`: version 2 descriptors `(mode, ports)` in matrix order.
  Mode `'S'` has one physical port; modes `'D'` and `'C'` have an ordered
  pair of physical ports. An empty vector denotes single-ended data.
  The array `N` is already in the specified basis; no basis conversion is made.
- `comments`: comment text without the leading `!`, with its case preserved.
- `noisedata`: flat five-value records: frequency in `frequencyunit`, minimum
  noise figure in dB, optimum source reflection-coefficient magnitude, its
  angle in degrees, and effective noise resistance in ohms. Noise data require
  two ports. Version 1 noise resistance is converted to ohms when reading and
  normalized by `R` when writing (port 1 in version 1.1).
"""
struct TouchstoneFile{F<:AbstractVector{Float64}, A<:AbstractArray{ComplexF64,3}}
    f::F
    N::A
    frequencyunit::String
    parameter::String
    format::String
    R::Float64
    version::Float64
    numberofports::Int
    twoportdataorder::String
    numberoffrequencies::Int
    numberofnoisefrequencies::Int
    reference::Vector{Float64}
    information::Vector{String}
    matrixformat::String
    mixedmodeorder::Vector{Tuple{Char, Vector{Int}}}
    comments::Vector{String}
    noisedata::Vector{Float64}
end

"""
    TouchstoneOptionLine(frequencyunit::String, parameter::String,
        format::String, R::Float64, reference::Vector{Float64}=Float64[])

Store option-line values: the file frequency unit, network parameter family,
numeric representation, and reference resistance `R` in ohms. `reference`
holds version 1.1 per-port values, with `R` equal to the first value, or is
empty for a scalar option-line resistance. Use
[`parseoptionline`](@ref) to parse and validate text.
"""
struct TouchstoneOptionLine
  frequencyunit::String
  parameter::String
  format::String
  R::Float64
  reference::Vector{Float64}
end
TouchstoneOptionLine(frequencyunit, parameter, format, R) =
    TouchstoneOptionLine(frequencyunit, parameter, format, R, Float64[])
