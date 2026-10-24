# Exponent of R in the conversion from file values to physical values.
# Keeping the direction avoids ever materializing 1/R for a tiny R.
function normalizationpower(p, i, j)
    p == "z" && return 1
    p == "y" && return -1
    p == "h" && return i == j == 1 ? 1 : i == j == 2 ? -1 : 0
    p == "g" && return i == j == 1 ? -1 : i == j == 2 ? 1 : 0
    return 0
end

# Apply a ratio without forming an overflowing ratio or intermediate product.
function scalevalue(x, power, resistance::Tuple{<:Real,<:Real})
    power == 0 && return x
    a, b = power == 1 ? resistance : reverse(resistance)
    b == 1 && return x * a
    a == 1 && return x / b
    mx, ex = frexp(x)
    ma, ea = frexp(a)
    mb, eb = frexp(b)
    return ldexp(mx * ma / mb, ex + ea - eb)
end

# File-to-physical scaling for legacy non-S data, retaining factors when a
# ratio or geometric mean would lose range or precision.
function entrynormalization(p, i, j, R, version, reference)
    if version == 1.1 && !isempty(reference)
        if p == "z" || p == "y"
            ri, rj = reference[i], reference[j]
            R = ri == rj ? ri : sqrt(ri) * sqrt(rj)
            if ri != rj && R < floatmin(Float64)
                # Avoid rounding a subnormal mean before scaling the data.
                a, b = sqrt(ri), sqrt(rj)
                return (p == "z" ? 1 : -1, (a, inv(b)), log10(a) + log10(b))
            end
        elseif i == j
            R = reference[i]
        elseif reference[1] != reference[2]
            a, b = sqrt(reference[1]), sqrt(reference[2])
            return (p == "h" ? 1 : -1, (a, b), log10(a) - log10(b))
        end
    end
    return (normalizationpower(p, i, j), (R, 1.0), log10(R))
end

# Compute log10(abs(z)) of a nonzero z without squaring or overflowing a
# representable component.
function logmagnitude(z)
    hi = max(abs(real(z)), abs(imag(z)))
    lo = min(abs(real(z)), abs(imag(z)))
    return log10(hi) + 0.5 * log10(1 + (lo/hi)^2)
end

# The entry a refused value belongs to, for error messages.
entryname(encoding, n, frequency) = string(encoding.parameter,
    " parameter (", encoding.indices[n][1], ", ", encoding.indices[n][2], ") at ",
    frequency, " Hz")

"""
    arraytonetworkdata(frequencies, N, numberofports, numberoffrequencies,
        matrixformat, twoportdataorder, parameter, frequencyunit, format, R,
        version; reference=Float64[])

Encode physical parameters `N` and frequencies in Hz as a flat `Float64`
vector. Each record contains a frequency in `frequencyunit`, then pairs of
numbers in `format`, ordered by [`matrixindices`](@ref).

Apply the inverse of the physical-unit normalization described in
[`networkdatatoarray`](@ref). DB values are 20 log10 of the normalized magnitude;
MA and DB angles are in degrees. For version 1.1, `reference` supplies one
resistance per port; an empty vector uses `R` for all ports. This low-level
helper expects consistent dimensions and metadata. Use [`touchstone_file`](@ref)
for complete input validation.

# Examples
```jldoctest
julia> N = fill(100.0 + 0.0im, 1, 1, 1);

julia> Touchstone.arraytonetworkdata([2.0e9], N, 1, 1, "Full", "12_21",
           "Z", "GHz", "RI", 50.0, 1.0)
3-element Vector{Float64}:
 2.0
 2.0
 0.0

julia> Touchstone.arraytonetworkdata([2.0e9], N, 1, 1, "Full", "12_21",
           "Z", "GHz", "RI", 50.0, 2.0)
3-element Vector{Float64}:
   2.0
 100.0
   0.0
```
"""
function arraytonetworkdata(frequencies, N, numberofports, numberoffrequencies,
    matrixformat, twoportdataorder, parameter, frequencyunit, format, R, version;
    reference=Float64[])
    encoding = networkencoding(numberofports, matrixformat, twoportdataorder,
        parameter, frequencyunit, format, R, version, reference)
    data = Vector{Float64}(undef, (2length(encoding.indices)+1) * numberoffrequencies)
    encodenetworkdata!(data, frequencies, N, encoding)
    return data
end

networkencoding(ts::TouchstoneFile) = networkencoding(ts.numberofports,
    ts.matrixformat, ts.twoportdataorder, ts.parameter, ts.frequencyunit,
    ts.format, ts.R, ts.version, ts.reference)

function networkencoding(nports, matrixformat, order, parameter, frequencyunit, format, R, version,
    reference=Float64[])
    indices = matrixindices(nports, matrixformat, order)
    p, fmt = lowercase(parameter), Symbol(lowercase(format))
    version in (1.0, 1.1, 2.0, 2.1) || error("Unknown format or version")
    p in ("s", "z", "y", "g", "h") || error("Unknown format or version")
    fmt in (:ri, :ma, :db) || error("Unknown format")
    # Store uniform normalization once; retain per-entry scales when needed.
    scales = if version >= 2 || p == "s"
        (0, (1.0, 1.0), 0.0)
    elseif p in ("z", "y") && (version == 1.0 || isempty(reference) || allequal(reference))
        entrynormalization(p, 1, 1, R, version, reference)
    else
        [entrynormalization(p, I[1], I[2], R, version, reference) for I in indices]
    end
    return (; indices, scales, fmt, units=frequencyscale(frequencyunit),
        parameter=uppercase(p), unit=frequencyunit)
end

entryscale(scales::Tuple, n) = scales
entryscale(scales::AbstractVector, n) = scales[n]

function encoderecord!(record, frequencies, N, k, encoding)
    (; indices, scales, fmt, units) = encoding
    f = frequencies[k] / units
    isfinite(f) && isfinite(f * units) ||
        error(lazy"The network frequency $(frequencies[k]) Hz is out of range in $(encoding.unit).")
    f == 0 && frequencies[k] != 0 &&
        error(lazy"The network frequency $(frequencies[k]) Hz underflows in $(encoding.unit); use Hz.")
    record[1] = f
    for n in eachindex(indices)
        z = N[indices[n],k]
        isfinite(z) ||
            error(lazy"The $(entryname(encoding, n, frequencies[k])) is not finite: $(z).")
        power, R, logR = entryscale(scales, n)
        if fmt == :db
            iszero(z) &&
                error(lazy"The $(entryname(encoding, n, frequencies[k])) is zero, which has no value in dB; use RI or MA.")
            a, b = 20 * (logmagnitude(z) - power*logR), rad2deg(angle(z))
        elseif fmt == :ma
            # Scale components before taking a magnitude when necessary.
            normalized = complex(scalevalue(real(z), -power, R), scalevalue(imag(z), -power, R))
            a, b = abs(normalized), rad2deg(angle(z))
            a == 0 && z != 0 &&
                error(lazy"The magnitude of the $(entryname(encoding, n, frequencies[k])) underflows; use DB or another reference impedance.")
        else
            a, b = scalevalue(real(z), -power, R), scalevalue(imag(z), -power, R)
            ((a == 0 && real(z) != 0) || (b == 0 && imag(z) != 0)) &&
                error(lazy"A component of the $(entryname(encoding, n, frequencies[k])) underflows; use DB or another reference impedance.")
        end
        isfinite(a) && isfinite(b) ||
            error(lazy"The $(entryname(encoding, n, frequencies[k])), $(z), is not representable in $(uppercase(String(fmt))).")
        # Rounding/scaling must not create a file whose physical values
        # overflow or vanish on readback, including near Float64 limits.
        # 1e±300 is well inside the Float64 exponent limits. Outside
        # that safe interior, explicitly exercise the decoding path.
        largest = max(abs(real(z)), abs(imag(z)))
        if largest > 1e300 || (0 < largest < 1e-300) || fmt == :ri
            decodeentry(a, b, power, R, logR, fmt)
        end
        record[2n] = a
        record[2n+1] = b
    end
    return record
end

function checkencodedfrequency(f, previous, units)
    f > previous && f * units > previous * units ||
        error("Frequencies collapse after unit conversion; use Hz.")
    return f
end

function encodenetworkdata!(data, frequencies, N, encoding)
    width = 2length(encoding.indices) + 1
    previous = -1.0
    for k in 1:length(data)÷width
        record = @view data[(k-1)*width+1:k*width]
        encoderecord!(record, frequencies, N, k, encoding)
        previous = checkencodedfrequency(record[1], previous, encoding.units)
    end
    return data
end

function checknoisestart(ts, lastfrequency)
    !isempty(ts.noisedata) && ts.noisedata[1] > lastfrequency &&
        error("Noise starts above the highest serialized network frequency.")
    return nothing
end

function checkencoding(ts, encoding)
    record = Vector{Float64}(undef, 2length(encoding.indices)+1)
    previous = -1.0
    for k in eachindex(ts.f)
        encoderecord!(record, ts.f, ts.N, k, encoding)
        previous = checkencodedfrequency(record[1], previous, encoding.units)
    end
    checknoisestart(ts, record[1])
    return record
end

function decodeentry(a, b, power, R, logR, fmt)
    if fmt == :ri
        x, y = scalevalue(a, power, R), scalevalue(b, power, R)
        ((a != 0 && x == 0) || (b != 0 && y == 0)) &&
            error("Network component underflows after conversion to physical units.")
        z = complex(x, y)
    else
        s, c = sincosd(b)
        phase = complex(c, s)
        if fmt == :db
            exponent = a/20 + power*logR
            magnitude = 10.0^exponent
            if isfinite(magnitude) && magnitude != 0
                z = magnitude * phase
            else
                # The magnitude can overflow even when both components fit.
                component(v) = iszero(v) ? v : copysign(10.0^(exponent + log10(abs(v))), v)
                z = complex(component(real(phase)), component(imag(phase)))
            end
            iszero(z) && error("DB magnitude underflows after conversion to physical units.")
        else
            magnitude = scalevalue(a, power, R)
            if isfinite(magnitude)
                z = magnitude * phase
            else
                z = complex(scalevalue(a*real(phase), power, R), scalevalue(a*imag(phase), power, R))
            end
            a != 0 && iszero(z) && error("Magnitude underflows after conversion to physical units.")
        end
    end
    isfinite(z) || error("Network parameter overflows after conversion to physical units.")
    return z
end

"""
    networkdatatoarray(networkdata, numberofports, numberoffrequencies,
        matrixformat, twoportdataorder, parameter, frequencyunit, format, R,
        version; reference=Float64[])

Decode flat file records into `(frequencies, N)`, with frequencies in Hz and
physical network parameters in a `ComplexF64` array of size
`(numberofports, numberofports, numberoffrequencies)`.

For version 1.0, convert file values with `Z = z R`, `Y = y / R`,
`H11 = h11 R`, `H22 = h22 / R`, `G11 = g11 / R`, and `G22 = g22 R`.
Off-diagonal H/G entries and S parameters are unscaled. For version 1.1,
`reference` supplies per-port normalization; an empty vector uses `R` for all
ports. Version 2 non-S parameters already use physical units.

DB values describe the normalized magnitude in dB; MA and DB angles are in
degrees. Reconstruct triangular matrices by transpose symmetry, without complex
conjugation. Use [`touchstone_parse`](@ref) for complete file validation.

# Examples
```jldoctest
julia> f, N = Touchstone.networkdatatoarray([2.0, 2.0, 0.0], 1, 1,
           "Full", "12_21", "Z", "GHz", "RI", 50.0, 1.0);

julia> f, N[1, 1, 1]
([2.0e9], 100.0 + 0.0im)
```
"""
function networkdatatoarray(networkdata, numberofports, numberoffrequencies,
    matrixformat, twoportdataorder, parameter, frequencyunit, format, R, version;
    reference=Float64[])
    encoding = networkencoding(numberofports, matrixformat, twoportdataorder,
        parameter, frequencyunit, format, R, version, reference)
    width = 2length(encoding.indices) + 1
    length(networkdata) == width*numberoffrequencies || error("Incomplete network data record.")
    N = Array{ComplexF64}(undef, numberofports, numberofports, numberoffrequencies)
    frequencies = Vector{Float64}(undef, numberoffrequencies)
    symmetric = lowercase(matrixformat) != "full"
    for k in 1:numberoffrequencies
        record = @view networkdata[(k-1)*width+1:k*width]
        frequencies[k] = decoderecord!(N, (k-1)*numberofports^2,
            numberofports, record, encoding, symmetric)
    end
    checkfrequencies(frequencies, "network in Hz")
    return frequencies, N
end

# Decode into column-major physical storage. Triangular records use transpose
# symmetry, including for complex entries; they are not Hermitian matrices.
function decoderecord!(data, offset, nports, record, encoding, symmetric)
    (; indices, scales, fmt, units) = encoding
    f = record[1] * units
    isfinite(f) ||
        error(lazy"The network frequency $(record[1]) $(encoding.unit) overflows in Hz.")
    for n in eachindex(indices)
        power, resistance, logR = entryscale(scales, n)
        z = decodeentry(record[2n], record[2n+1], power, resistance, logR, fmt)
        i, j = Tuple(indices[n])
        data[offset + i + (j-1)*nports] = z
        symmetric && (data[offset + j + (i-1)*nports] = z)
    end
    return f
end

"""
    matrixindices(nports, format; printflag=false)

Return network-matrix Cartesian indices in file order for `nports` and matrix
format `"Full"`, `"Upper"`, or `"Lower"` (case insensitive). Use `"12_21"`
ordering. With `printflag=true`, also print the index layout to standard output.

# Examples
```jldoctest
julia> Touchstone.matrixindices(2,"Full",printflag=true)
11 12
21 22
4-element Vector{CartesianIndex{2}}:
 CartesianIndex(1, 1)
 CartesianIndex(1, 2)
 CartesianIndex(2, 1)
 CartesianIndex(2, 2)

julia> Touchstone.matrixindices(2,"Upper",printflag=true)
11 12
   22
      3-element Vector{CartesianIndex{2}}:
 CartesianIndex(1, 1)
 CartesianIndex(1, 2)
 CartesianIndex(2, 2)

julia> Touchstone.matrixindices(2,"Lower",printflag=true)
11
21 22
3-element Vector{CartesianIndex{2}}:
 CartesianIndex(1, 1)
 CartesianIndex(2, 1)
 CartesianIndex(2, 2)
```
"""
function matrixindices(nports, format; printflag = false)
    return matrixindices(nports, format, "12_21", printflag = printflag)
end

"""
    matrixindices(nports, format, twoportdataorder; printflag=false)

Return network-matrix Cartesian indices for `nports`, matrix `format`, and
`twoportdataorder`. Matrix formats are `"Full"`, `"Upper"`, and `"Lower"`
(case insensitive). The order is `"12_21"` or `"21_12"` for two ports and
must be `"12_21"` for other port counts. With `printflag=true`, also print
the index layout to standard output.

# Examples
```jldoctest
julia> Touchstone.matrixindices(2,"Full","12_21")
4-element Vector{CartesianIndex{2}}:
 CartesianIndex(1, 1)
 CartesianIndex(1, 2)
 CartesianIndex(2, 1)
 CartesianIndex(2, 2)

julia> Touchstone.matrixindices(2,"Full","21_12")
4-element Vector{CartesianIndex{2}}:
 CartesianIndex(1, 1)
 CartesianIndex(2, 1)
 CartesianIndex(1, 2)
 CartesianIndex(2, 2)
```
"""
function matrixindices(nports, format, twoportdataorder; printflag = false)
    indices = CartesianIndex{2}[]

    fmt = lowercase(format)
    if fmt == "lower" || fmt == "upper"
        ntotal = nports*(1+nports) ÷ 2
    elseif fmt == "full"
        ntotal = nports^2
    else
        error(lazy"Unknown matrix format.")
    end

    sizehint!(indices, ntotal)

    for i = 1:nports
        firstcolumn = fmt == "upper" ? i : 1
        lastcolumn = fmt == "lower" ? i : nports
        for j = firstcolumn:lastcolumn
            if printflag
                print("$(i)$(j) ")
            end
            push!(indices,CartesianIndex(i,j))
        end
        if printflag
            print("\n")
            if fmt == "upper"
                for k = 1:i
                    print("   ")
                end
            end
        end
    end

    if twoportdataorder == "21_12" && nports == 2
        for n = 1:length(indices)
            if indices[n][1] != indices[n][2]
                indices[n] = CartesianIndex(indices[n][2],indices[n][1])
            end
        end
    elseif twoportdataorder == "21_12"
        error(lazy"Two port data order = 21_12 is only allowed if the number of ports is two.")
    elseif twoportdataorder == "12_21"
        nothing
    else
        error(lazy"Unknown two port data order string.")
    end
    return indices
end

"""
    frequencyscale(frequencyunit::String)

Return the multiplier that converts `frequencyunit` to Hz. Accept `"Hz"`,
`"kHz"`, `"MHz"`, and `"GHz"`, without regard to case.

# Examples
```jldoctest
julia> Touchstone.frequencyscale("MHz")
1.0e6
```
"""
function frequencyscale(frequencyunit::String)
    fu = lowercase(frequencyunit)
    if fu == "hz"
        return 1.0
    elseif fu == "khz"
        return 1.0e3
    elseif fu == "mhz"
        return 1.0e6
    elseif fu == "ghz"
        return 1.0e9
    else
        error(lazy"Unknown frequency unit $frequencyunit")
    end
end
function recordwidth(nports, matrixformat)
    try
        entries = Base.checked_mul(nports, nports)
        return lowercase(matrixformat) == "full" ? Base.checked_add(Base.checked_mul(2, entries), 1) :
            Base.checked_add(Base.checked_add(entries, nports), 1)
    catch e
        e isa OverflowError || rethrow()
        error("The number of ports is too large.")
    end
end
