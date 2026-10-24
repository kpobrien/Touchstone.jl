"""
    touchstone_file(f::AbstractVector, N::AbstractArray;
        frequencyunit="GHz", parameter="S", format="MA", R=50.0,
        version=2.0, twoportdataorder="", reference=Float64[],
        information=String[], matrixformat="Full",
        mixedmodeorder=Tuple{Char, Vector{Int}}[], comments=String[],
        noisedata=Float64[])

Construct a [`TouchstoneFile`](@ref) from network frequencies `f` in Hz and
physical network parameters `N`. The array has size `(nports, nports, length(f))`;
see [`TouchstoneFile`](@ref) for parameter units and metadata fields.

Inputs must use one-based indexing. Views and ranges are accepted. Arrays
with element types `Float64` for `f` and `ComplexF64` for `N` are retained;
other real frequency and numeric parameter arrays are converted to those
types. Reject negative frequencies, nonfinite values, and nonzero values or
components that become zero during conversion. Frequencies must increase
strictly, including after conversion to the file unit. Numeric keywords `R`
and `version` accept real values; `reference` and `noisedata` accept one-based
real vectors. These values use `Float64` storage and the same checked conversion.
Float16 and Float32 version selectors match supported versions in their input
precision before conversion; adjacent values in those types are rejected.
Canonical `Vector{Float64}` metadata vectors are retained.

The keywords select the file representation. References describe the supplied
`N`; changing `R` or `reference` does not renormalize S parameters.
`mixedmodeorder` describes the supplied data without transforming its basis.
An empty `reference` uses `R`
for every port. In version 1.1, `reference` supplies the option-line values
and its first value sets `R`, including for noise normalization. An empty
`twoportdataorder` selects `"12_21"`; version 1 always
uses `"21_12"` for two ports and `"12_21"` otherwise. `"Upper"` and `"Lower"`
require exact transpose symmetry. Use `"RI"` or `"MA"` for exact zeros, which
have no finite `"DB"` representation. Information and mixed-mode metadata
require version 2. Noise frequencies use `frequencyunit`, and noise resistance
is supplied in ohms. Each comment or information entry must be a single line;
information entries cannot contain `!` or the section terminator.

Validate the selected file representation one record at a time. The result
stores physical arrays and metadata; writing uses their current values.

# Examples
```jldoctest
julia> f = [1.0e9, 2.0e9]; N = fill(0.5 + 0.0im, 1, 1, 2);

julia> ts = Touchstone.touchstone_file(f, N; frequencyunit="GHz", format="RI");

julia> ts.f === f, ts.N === N
(true, true)

julia> ts.f, ts.frequencyunit
([1.0e9, 2.0e9], "GHz")
```
"""
function touchstone_file(f::AbstractVector, N::AbstractArray; kwargs...)
    ts = preparetouchstone(f, N; kwargs...)
    encoding = networkencoding(ts)
    checkencoding(ts, encoding)
    return ts
end

# Check before conversion can erase a negative frequency or a nonzero
# component. Ordinary rounding is allowed; silent underflow is not.
function checkedfloat64(x::Real)
    y = Float64(x)
    iszero(y) && !iszero(x) && error("Numeric input underflows Float64.")
    return y
end
function checkedfrequency(x::Real)
    x >= 0 || error("Network frequencies must be nonnegative.")
    return checkedfloat64(x)
end
checkedcomplex(x::Number) = complex(checkedfloat64(real(x)), checkedfloat64(imag(x)))

# Version numbers are discrete selectors. Preserve their input precision when
# matching decimal versions supplied as Float16 or Float32.
function canonicalversion(version::Real)
    value = checkedfloat64(version)
    for supported in (1.0, 1.1, 2.0, 2.1)
        matches = version isa Union{Float16,Float32} ?
            version == oftype(version, supported) : value == supported
        matches && return supported
    end
    error("Version must be 1.0, 1.1, 2.0, or 2.1")
end

function preparetouchstone(f::AbstractVector{<:Real}, N::AbstractArray{<:Number};
    frequencyunit::String = "GHz",
    parameter::String = "S",
    format::String = "MA",
    R::Real = 50.0,
    version::Real = 2.0,
    twoportdataorder::String = "",
    reference::AbstractVector{<:Real} = Float64[],
    information::Vector{String} = String[],
    matrixformat::String = "Full",
    mixedmodeorder::Vector{Tuple{Char, Vector{Int}}} = Tuple{Char, Vector{Int}}[],
    comments::Vector{String} = String[],
    noisedata::AbstractVector{<:Real} = Float64[]
)

    Base.require_one_based_indexing(f, N, reference, noisedata)
    ndims(N) == 3 || error("Network data must have two port axes and a frequency axis.")
    f = eltype(f) === Float64 ? f : checkedfrequency.(f)
    N = eltype(N) === ComplexF64 ? N : checkedcomplex.(N)

    R = checkedfloat64(R)
    version = canonicalversion(version)
    reference = reference isa Vector{Float64} ? reference : [checkedfloat64(x) for x in reference]
    noisedata = noisedata isa Vector{Float64} ? noisedata : [checkedfloat64(x) for x in noisedata]

    numberoffrequencies = length(f)

    # The network array must contain one square matrix per frequency.
    if numberoffrequencies != size(N,3)
        error(lazy"The size of the last axis of network data N must equal the number of frequencies")
    end

    if size(N,1) != size(N,2)
        error(lazy"Network data matrix must be square")
    end
    numberofports = size(N,1)

    fu = lowercase(frequencyunit)
    if !(fu == "hz" || fu == "khz" || fu == "mhz" || fu == "ghz")
        error(lazy"Unknown frequency unit")
    end

    fmt = lowercase(format)
    if !(fmt == "ma" || fmt == "ri" || fmt == "db")
        error(lazy"Unknown format")
    end

    p = lowercase(parameter)
    if !(p == "s" || p == "y" || p == "z" || p == "h" || p == "g")
        error(lazy"Unknown parameter")
    end
    if (p == "h" || p == "g") && numberofports != 2
        error(lazy"$(uppercase(parameter)) parameters are defined for two-port networks only, not $(numberofports) ports.")
    end

    # Default every port reference to R when none are supplied.
    if isempty(reference)
        reference = fill(R, numberofports)
    end

    if length(reference) != numberofports
        error(lazy"Number of per port impedances must equal number of ports")
    end

    if version == 1.1 && !isempty(reference)
        R = reference[1]
    end

    if version == 1.0
        if !allequal(reference)
            error(lazy"Version 1.0 requires equal port impedances; use version 1.1 or version 2.")
        end
    end

    if version < 2.0
        if lowercase(matrixformat) != "full"
            error(lazy"For Touchstone files with version less than 2.0 only the Full matrix format is required.")
        end
    else
        if !(lowercase(matrixformat) == "full" || lowercase(matrixformat) == "lower" || lowercase(matrixformat) == "upper")
            error(lazy"For Touchstone version 2 the valid formats are Full, Lower, or Upper.")
        end
    end

    if version < 2
        if numberofports == 2
            # Version 1 two-port data use column-major order.
            twoportdataorder = "21_12"
        else
            twoportdataorder = "12_21"
        end
    else
        if isempty(twoportdataorder)
            twoportdataorder = "12_21"
        elseif twoportdataorder == "12_21" || twoportdataorder == "21_12"
            nothing
        else
            error(lazy"Unknown two-port data order.")
        end
    end

    matrixformat = uppercasefirst(lowercase(matrixformat))
    numberofports > 0 || error("The number of ports must be positive.")
    checkmixedmode(mixedmodeorder, numberofports, parameter, reference, version)
    if version < 2.0 && !isempty(information)
        error("Information sections require Touchstone version 2.")
    end
    for comment in comments
        isvalid(comment) || error("Comments must contain valid Unicode text.")
        any(c -> c == '\n' || c == '\r', comment) &&
            error("Each comment must be a single line.")
    end
    for entry in information
        isvalid(entry) || error("Information entries must contain valid Unicode text.")
        any(c -> c in ('\n', '\r', '!'), entry) &&
            error("An information entry cannot contain a line break or comment delimiter.")
        lowercase(rstrip(entry)) == "[end information]" &&
            error("An information entry cannot be the section terminator.")
    end

    numberofnoisefrequencies = 0
    if rem(length(noisedata),5) == 0
        numberofnoisefrequencies = length(noisedata) ÷ 5
    else
        error(lazy"Invalid number of elements in noise data.")
    end
    if numberofnoisefrequencies > 0 && numberofports != 2
        error(lazy"Noise parameters are only included in files of two-port networks, not $(numberofports) ports.")
    end

    # Validate physical values and metadata before the encoding step.
    ts = TouchstoneFile(f, N, frequencyunit, parameter, format, R, version,
        numberofports, twoportdataorder, numberoffrequencies,
        numberofnoisefrequencies, reference, information, matrixformat,
        mixedmodeorder, comments, noisedata)
    checkphysicaldata(ts)
    if matrixformat != "Full"
        for k in axes(N,3), j in axes(N,2), i in 1:j-1
            N[i,j,k] == N[j,i,k] ||
                error("Upper/Lower output requires transpose-symmetric matrices; use Full.")
        end
    end
    return ts
end
# Common physical-value checks used after parsing and before serialization.
# Encoding additionally checks actual file values and their representability.
function checkphysicaldata(ts::TouchstoneFile)
    if !(isfinite(ts.R) && ts.R > 0)
        error(lazy"R must be a positive number of ohms: $(ts.R)")
    end
    if !all(z -> isfinite(z) && z > 0, ts.reference)
        error(lazy"The reference impedances must be positive numbers of ohms: $(ts.reference)")
    end
    if ts.version == 1.0 && !all(==(ts.R), ts.reference)
        error(lazy"A version 1.0 file states one reference impedance, R = $(ts.R), which the reference impedances $(ts.reference) differ from; write a version 1.1 or version 2 file.")
    end
    if isempty(ts.f)
        error(lazy"No network data.")
    end
    checkfrequencies(ts.f, "network")
    checkfrequencies(@view(ts.noisedata[1:5:end]), "noise")
    i = findfirst(!isfinite, ts.noisedata)
    isnothing(i) || error(lazy"The noise data value $(ts.noisedata[i]) of the record at $(ts.noisedata[5*cld(i, 5)-4]) $(ts.frequencyunit) is not finite.")
    if !isempty(ts.noisedata)
        units = frequencyscale(ts.frequencyunit)
        for i in 1:5:length(ts.noisedata)
            isfinite(ts.noisedata[i] * units) ||
                error(lazy"The noise frequency $(ts.noisedata[i]) $(ts.frequencyunit) overflows in Hz.")
            if ts.version < 2.0
                raw = ts.noisedata[i+4] / ts.R
                isfinite(raw) && isfinite(raw * ts.R) ||
                    error(lazy"The noise resistance $(ts.noisedata[i+4]) ohms at $(ts.noisedata[i]) $(ts.frequencyunit) is not representable normalized by R = $(ts.R) ohms.")
                raw == 0 && ts.noisedata[i+4] != 0 &&
                    error(lazy"The noise resistance $(ts.noisedata[i+4]) ohms at $(ts.noisedata[i]) $(ts.frequencyunit) underflows normalized by R = $(ts.R) ohms.")
            end
        end
        # Noise starts at or below the highest network frequency
        # (Touchstone 2.0, "Noise Parameter Data").
        if ts.noisedata[1] * units > maximum(ts.f)
            error(lazy"The first noise frequency, $(ts.noisedata[1]) $(ts.frequencyunit), is above the highest network frequency, $(maximum(ts.f)) Hz.")
        end
    end
    return nothing
end

function checkfrequencies(f::AbstractVector, kind::String)
    for i in eachindex(f)
        if !(isfinite(f[i]) && f[i] >= 0)
            error(lazy"The $(kind) data frequency $(f[i]) is not a finite, nonnegative number.")
        elseif i > firstindex(f) && !(f[i] > f[i-1])
            error(lazy"The $(kind) data frequencies do not increase: $(f[i]) follows $(f[i-1]).")
        end
    end
    return nothing
end
function checkmixedmode(order, nports, parameter, reference, version)
    isempty(order) && return nothing
    version in (2.0, 2.1) || error("Mixed-mode data require Touchstone version 2.")
    length(order) == nports || error("Number of mixed mode order descriptors must match the number of ports.")
    lowercase(parameter) in ("s", "y", "z") || error("Mixed-mode data require S, Y or Z parameters.")
    owner = zeros(Int, nports)
    pairs = Dict{Tuple{Int,Int},UInt8}()
    for (mode, ports) in order
        mode in ('S', 'D', 'C') || error("Unknown mixed-mode descriptor: $(mode)")
        length(ports) == (mode == 'S' ? 1 : 2) || error("Invalid mixed-mode descriptor arity.")
        all(p -> 1 <= p <= nports, ports) || error("Mixed-mode port is out of range.")
        i = ports[1]
        if mode == 'S'
            owner[i] == 0 || error("Mixed-mode port is reused.")
            owner[i] = i
        else
            j = ports[2]
            i != j || error("A mixed-mode pair must contain distinct ports.")
            reference[i] == reference[j] || error("Mixed-mode pairs require equal reference impedances.")
            key = (i,j) # Orientation carries the differential sign.
            mask = mode == 'D' ? 0x01 : 0x02
            previous = get(pairs, key, 0x00)
            previous & mask == 0 || error("Duplicate mixed-mode descriptor.")
            if previous == 0
                owner[i] == owner[j] == 0 || error("Mixed-mode pairs overlap or disagree in orientation.")
                owner[i] = j
                owner[j] = i
            end
            pairs[key] = previous | mask
        end
    end
    all(!iszero, owner) && all(==(0x03), values(pairs)) ||
        error("Every port needs one S descriptor or one matched D/C pair.")
    return nothing
end
