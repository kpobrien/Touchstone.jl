"""
    touchstone_load(filename)

Read a Touchstone 1.0, 1.1, 2.0, or 2.1 file and return a [`TouchstoneFile`](@ref).
Network frequencies `f` are in Hz and network parameters `N` use physical
units. Noise frequencies retain the file unit; noise resistance is in ohms.

The number of ports is determined from the file contents. No particular
filename extension is required. See [`touchstone_parse`](@ref) to read from IO.
"""
function touchstone_load(filename)
    open(filename, "r") do io
        return touchstone_parse(io)
    end
end

"""
    touchstone_parse(io::IO)

Read Touchstone data from a seekable stream `io` at its current position and
return a [`TouchstoneFile`](@ref). The stream remains open, and an existing
stream mark is preserved. Decode complete network records incrementally;
malformed input may be rejected before later records are read.
Network frequencies are in Hz and network parameters
use physical units, as for
[`touchstone_load`](@ref).

Accept LF, CRLF, or CR line endings and an optional leading UTF-8 byte order
mark. Text is decoded as UTF-8 when valid, or as Latin-1 otherwise.

# Examples
```jldoctest
julia> io = IOBuffer("# MHz S RI R 50\\n2.0 0.5 -0.25");

julia> ts = Touchstone.touchstone_parse(io);

julia> ts.f, ts.N[1, 1, 1]
([2.0e6], 0.5 - 0.25im)

julia> ts.frequencyunit
"mhz"
```
"""
function touchstone_parse(io::IO)
    readereof(io) && error(lazy"Input is empty and thus not a valid touchstone file.")
    # A UTF-8 byte order mark is not part of the first line.
    start = readerposition(io)
    read(io, 3) == UInt8[0xef, 0xbb, 0xbf] || seekreader!(io, start)
    reader = TouchstoneReader(io)
    try
        return parsetouchstone(reader)
    finally
        # Restore the caller's logical position after buffered lookahead,
        # including validation errors before the end of the input.
        seekreader!(io, readerposition(reader))
    end
end

function parsetouchstone(io::TouchstoneReader)

    readoptionline = true
    optionline = TouchstoneOptionLine("Hz","S","MA",50.0)
    comments = String[]
    version = 0.0
    numberofports = 0
    twoportdataorder = ""
    numberoffrequencies = 0
    numberofnoisefrequencies = 0
    reference = Float64[]
    information = String[]
    matrixformat = "Full"
    mixedmodeorder = Tuple{Char, Vector{Int}}[]

    noisedata = Float64[]
    networkheader = false
    seenheaders = Set{String}()

    while !readereof(io)

        line = stripcommentslowercase!(comments,readtouchstoneline(io))

        if startswith(line, "[")
            closebracket = findfirst(']', line)
            closebracket === nothing && error("Unterminated Touchstone keyword.")
            after = nextind(line, closebracket)
            after <= lastindex(line) && !isspace(line[after]) &&
                error("Keyword arguments must be separated by whitespace.")
        end
        if startswith(line, "[") && version >= 2.0 && !isversion(line)
            keyword = first(split(line, ']')) * "]"
            readoptionline && error("The option line must precede version 2 metadata.")
            if numberofports == 0 && !isnumberofports(line)
                error("[Number of Ports] must precede $(keyword)")
            end
            if keyword in ("[number of frequencies]", "[number of noise frequencies]",
                    "[matrix format]", "[mixed-mode order]", "[begin information]")
                keyword in seenheaders && error("Only one $(keyword) keyword allowed.")
                push!(seenheaders, keyword)
            end
        end
        if isempty(strip(line))
            nothing

        elseif iszero(version) && startswith(line, "[") && !isversion(line)
            # [Version] must precede other content in version 2; version 1 has no keywords.
            error(lazy"The keyword $(line) is only allowed after [Version] 2.0 or 2.1, which precedes all other lines of a version 2 file.")

        elseif isversion(line)
            if !iszero(version)
                error(lazy"Only one [Version] keyword allowed: $(line)")
            else
                strip(line[10:end]) in ("2.0", "2.1") ||
                    error("[Version] must be 2.0 or 2.1; version 1 has no keywords.")
                version = parseversion(line)
            end

        elseif isoptionline(line) && readoptionline
            optionline = parseoptionline(line)
            version >= 2.0 && !isempty(optionline.reference) &&
                error("Version 2 option lines require one resistance; use [Reference] for per-port values.")

            # Only the first option line supplies metadata.
            readoptionline = false

            # Version 1 network data follow the option line.
            if iszero(version)
                version = isempty(optionline.reference) ? 1.0 : 1.1
                reference = optionline.reference
                break
            end

        elseif isoptionline(line) && !readoptionline
            # Ignore additional option lines (Touchstone 2.0, "Option Line").
            nothing

        elseif isnumberofports(line)
            if !iszero(numberofports)
                error(lazy"Only one [Number of Ports] keyword allowed: $(line)")
            else
                numberofports = parsenumberofports(line)
                numberofports > 0 || error("The number of ports must be positive.")
            end

        elseif istwoportdataorder(line)
            # [Two-Port Data Order] is required only for two-port version 2 files.
            if numberofports == 2
                if !isempty(twoportdataorder)
                    error(lazy"Only one [Two-Port Data Order] line allowed: $(line)")
                else
                    twoportdataorder = parsetwoportdataorder(line)
                end
            else
                error(lazy"[Two-Port Data Order] is only allowed if [Number of Ports] is 2: $(line)")
            end

        elseif isbegininformation(line)
            rstrip(line) == "[begin information]" || error("[Begin Information] takes no arguments.")
            parseinformation!(information, comments, io)

        elseif isendinformation(line)
            error(lazy"Unexpected [End Information] outside an information section.")

        elseif isnumberoffrequencies(line)
            numberoffrequencies = parsenumberoffrequencies(line)

        elseif isnumberofnoisefrequencies(line)
            numberofnoisefrequencies = parsenumberofnoisefrequencies(line)

        elseif isreference(line)
            if !isempty(reference)
                error(lazy"Only one [Reference] keyword allowed: $(line)")
            end
            parsereference!(reference, comments, line, numberofports, io)

        elseif ismatrixformat(line)
            matrixformat = parsematrixformat(line)
        elseif ismixedmodeorder(line)
            parsemixedmodeorder!(mixedmodeorder, comments, line, numberofports, io)
        elseif rstrip(line) == "[network data]"
            # [Network Data] takes no arguments.
            networkheader = true
            break
        else
            error(lazy"Unknown line type: $(line)")
        end
    end

    readoptionline && error("A Touchstone file requires an option line.")
    if version >= 2.0
        networkheader || error("Missing [Network Data].")
        numberoffrequencies > 0 || error("Missing [Number of Frequencies].")
    end
    # Version 2 has an explicit record width; only version 1 needs inference.
    width = version >= 2.0 ? recordwidth(numberofports, matrixformat) : 0
    records = NetworkRecords(io, comments, version, width,
        numberoffrequencies, numberofnoisefrequencies)
    if !readnetworkrecord!(records)
        width == 0 && error("No network data.")
        error(lazy"[Number of Frequencies] is $(numberoffrequencies), the network data has 0.")
    end
    if version < 2.0
        # Infer the port count from the first complete record, independently
        # of the filename. Following records must have the same width.
        entries = (records.width - 1) ÷ 2
        numberofports = isqrt(entries)
        numberofports > 0 && 2numberofports^2 + 1 == records.width ||
            error("Incomplete or non-square network data record.")
    end

    if version < 2
        if numberofports == 2
            # Version 1 two-port data use column-major order.
            twoportdataorder = "21_12"
        else
            twoportdataorder = "12_21"
        end
    else
        if numberofports == 2 && isempty(twoportdataorder)
            error(lazy"two-port data order must be defined for a v2 file with two ports.")
        elseif isempty(twoportdataorder)
            twoportdataorder = "12_21"
        end
    end

    if lowercase(optionline.parameter) in ("g", "h") && numberofports != 2
        error(lazy"$(uppercase(optionline.parameter)) parameters are defined for two-port networks only; the file has $(numberofports) ports.")
    end

    !isempty(reference) && length(reference) != numberofports &&
        error("The option-line reference count must match the number of ports.")

    encoding = networkencoding(numberofports, matrixformat, twoportdataorder,
        optionline.parameter, optionline.frequencyunit, optionline.format,
        optionline.R, version, reference)
    frequencies, N = decodenetworkrecords!(records, numberofports, encoding,
        matrixformat != "Full")
    nfreq = records.count
    if version < 2.0
        numberoffrequencies = nfreq
    end

    nnoisefreq = parsenoisedata!(noisedata, comments, io; requireend=version >= 2.0, allowend=version >= 2.0)

    # Only comments and blank lines may follow [End].
    while !readereof(io)
        line = stripcommentslowercase!(comments, readtouchstoneline(io))
        if !isempty(strip(line))
            error(lazy"Only comments may follow [End]: $(line)")
        end
    end

    if version < 2.0
        # Version 1 has no declared count; use the number of noise records.
        @assert numberofnoisefrequencies == 0
        numberofnoisefrequencies = nnoisefreq
    else
        if numberofnoisefrequencies != nnoisefreq
            error(lazy"[Number of Noise Frequencies] is $(numberofnoisefrequencies), the noise data has $(nnoisefreq).")
        end
    end

    if numberofnoisefrequencies > 0 && numberofports != 2
        error(lazy"Noise parameters are only included in files of two-port networks; the file has $(numberofports) ports.")
    end

    if isempty(reference)
        for i in 1:numberofports
            push!(reference, optionline.R)
        end
    end

    # Convert the fifth noise value from version 1 normalization to ohms.
    if version < 2.0
        for i in 5:5:length(noisedata)
            resistance = noisedata[i] * optionline.R
            resistance == 0 && noisedata[i] != 0 && error("Noise resistance underflows in ohms.")
            noisedata[i] = resistance
        end
    end

    checkmixedmode(mixedmodeorder, numberofports, optionline.parameter, reference, version)
    result = TouchstoneFile(frequencies, N, optionline.frequencyunit,
        optionline.parameter, optionline.format, optionline.R, version,
        numberofports, twoportdataorder, numberoffrequencies,
        numberofnoisefrequencies, reference, information, matrixformat,
        mixedmodeorder, comments, noisedata)
    checkphysicaldata(result)
    return result
end

"""
    parsenetworkdata!(networkdata::Vector{Float64}, comments::Vector{String},
        io::Union{IO,TouchstoneReader}, version::Real=1.0; width::Int=0,
        expectedfrequencies::Int=0, expectednoise::Int=-1)

Append encoded network records from `io` to `networkdata`, collect comments,
and return `(numberoffrequencies, recordwidth)`. Values retain their file
units and representation. Frequencies must be finite, nonnegative, and
strictly increasing.

A positive `width` supplies the number of scalar values per record, allowing
arbitrary wrapping within a record. In this mode, a positive
`expectedfrequencies` limits the record count and `expectednoise=0` rejects
`[Noise Data]`. The complete file parser checks the declared counts. With
`width=0`, infer record boundaries from lines containing a frequency followed
by parameter pairs; `expectedfrequencies` and `expectednoise` are ignored.

Consume `[Noise Data]`, but leave `[End]` for [`parsenoisedata!`](@ref). In
version 1, a five-value line whose frequency does not exceed the preceding
network frequency starts the noise section; leave that line unread.

# Examples
```jldoctest
networkdata = Float64[]
comments = String[]
io = IOBuffer("1.0000 0.3926 -0.1211 -0.0003 -0.0021 -0.0003 -0.0021 0.3926 -0.1211\n2.0000 0.3517 -0.3054 -0.0096 -0.0298 -0.0096 -0.0298 0.3517 -0.3054\n10.000 0.3419 0.3336 -0.0134 0.0379 -0.0134 0.0379 0.3419 0.3336")
Touchstone.parsenetworkdata!(networkdata,comments,io,1.0)
println(networkdata)

# output
[1.0, 0.3926, -0.1211, -0.0003, -0.0021, -0.0003, -0.0021, 0.3926, -0.1211, 2.0, 0.3517, -0.3054, -0.0096, -0.0298, -0.0096, -0.0298, 0.3517, -0.3054, 10.0, 0.3419, 0.3336, -0.0134, 0.0379, -0.0134, 0.0379, 0.3419, 0.3336]
```
```jldoctest
networkdata = Float64[]
comments = String[]
io = IOBuffer("2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n! NOISE PARAMETERS\n4 .7 .64 69 .38\n18 2.7 .46 -33 .40")
Touchstone.parsenetworkdata!(networkdata,comments,io,1.0)
println(networkdata)

# output
[2.0, 0.95, -26.0, 3.57, 157.0, 0.04, 76.0, 0.66, -14.0, 22.0, 0.6, -144.0, 1.3, 40.0, 0.14, 40.0, 0.56, -85.0]
```
```jldoctest
networkdata = Float64[]
comments = String[]
io = IOBuffer("2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n4 .7 .64 69 19\n18 2.7 .46 -33 20\n[End]")
Touchstone.parsenetworkdata!(networkdata,comments,io,2.0)
println(networkdata)

# output
[2.0, 0.95, -26.0, 3.57, 157.0, 0.04, 76.0, 0.66, -14.0, 22.0, 0.6, -144.0, 1.3, 40.0, 0.14, 40.0, 0.56, -85.0]
```
"""
function parsenetworkdata!(networkdata::Vector{Float64},
        comments::Vector{String}, io::Union{IO,TouchstoneReader}, version::Real = 1.0; width::Int = 0,
        expectedfrequencies::Int = 0, expectednoise::Int = -1)
    records = NetworkRecords(io, comments, version, width, expectedfrequencies, expectednoise)
    while readnetworkrecord!(records)
        append!(networkdata, records.record)
    end
    return records.count, records.width
end

# The current record and one parsed lookahead line are reusable. Version 1
# identifies records by line shape; version 2 uses its declared record width.
mutable struct NetworkRecords{I}
    io::I
    comments::Vector{String}
    version::Float64
    counted::Bool
    width::Int
    expectedfrequencies::Int
    expectednoise::Int
    count::Int
    frequency::Float64
    record::Vector{Float64}
    values::Vector{Float64}
    pending::Bool
    finished::Bool
end
NetworkRecords(io, comments, version, width, expectedfrequencies, expectednoise) =
    NetworkRecords(io, comments, Float64(version), width > 0, width,
        expectedfrequencies, expectednoise, 0, -1.0, Float64[], Float64[], false, false)

function finishnetworkrecord!(records, line="")
    isempty(records.record) && return false
    width = length(records.record)
    if records.width == 0
        records.width = width
    elseif records.width != width
        isempty(line) && error("Incomplete final network data record.")
        error(lazy"Number of ports are not consistent between lines:$(line)")
    end
    records.count += 1
    return true
end

function readnetworkrecord!(records)
    records.finished && return false
    (; io, comments, record, values) = records
    empty!(record)
    if records.pending
        append!(record, values)
        records.pending = false
    end
    while !readereof(io)
        pos, commentcount = readerposition(io), length(comments)
        line = stripdataline!(comments, readtouchstoneline(io))
        isempty(strip(line)) && continue
        isoptionline(line) && continue
        if isend(line) || isnoisedata(line)
            if isnoisedata(line)
                records.version < 2 && error("Version 1 files do not support [Noise Data].")
                records.counted && records.expectednoise == 0 &&
                    error("[Noise Data] requires [Number of Noise Frequencies].")
            else
                # The noise reader owns [End] and its inline comment.
                seekreader!(io, pos)
                resize!(comments, commentcount)
            end
            records.counted && !isempty(record) &&
                error(lazy"Incomplete network data record before $(strip(line)).")
            records.finished = true
            return finishnetworkrecord!(records)
        end
        parsedataline!(values, line)
        if records.counted
            length(values) <= records.width - length(record) ||
                error("Too many values in a network data record; each frequency must start a line.")
            if isempty(record)
                records.expectedfrequencies > 0 && records.count >= records.expectedfrequencies &&
                    error("More network records than [Number of Frequencies].")
            end
        elseif isodd(length(values)) && records.frequency >= 0 &&
                !(values[1] > records.frequency) && records.version < 2 && length(values) == 5
            # Re-read the first noise line in the noise section, including its comment.
            seekreader!(io, pos)
            resize!(comments, commentcount)
            records.finished = true
            return finishnetworkrecord!(records)
        end
        newfrequency = records.counted ? isempty(record) : isodd(length(values))
        if newfrequency
            f = values[1]
            isfinite(f) && f >= 0 ||
                error(lazy"The network data frequency $(f) is not a finite, nonnegative number on the line: $(line)")
            f > records.frequency ||
                error(lazy"The network data frequencies do not increase: $(f) follows $(records.frequency) on the line: $(line)")
            records.frequency = f
            if !records.counted && !isempty(record)
                records.pending = true
                return finishnetworkrecord!(records, line)
            end
        elseif !records.counted && isempty(record)
            error("A network record must start with a frequency.")
        end
        append!(record, values)
        if records.counted && length(record) == records.width
            return finishnetworkrecord!(records)
        end
    end
    records.finished = true
    return finishnetworkrecord!(records)
end

# Decode into small blocks until enough input has arrived to allocate the final
# arrays. Declared counts cannot force a large allocation from a small input:
# final storage is allocated only after at least half the records are present.
# Without a declared count, assemble the blocks once at the end.
function decodenetworkrecords!(records, nports, encoding, symmetric)
    block = Base.checked_mul(nports, nports)
    blockrecords = max(1, 4096 ÷ block) # At most 64 KiB of matrices, or one matrix.
    expected = records.counted ? records.expectedfrequencies : 0
    chunks = Tuple{Vector{Float64},Vector{ComplexF64}}[]
    frequencies, data = Float64[], ComplexF64[]
    offset = 0
    consolidated = false
    while true
        count = records.count
        if !consolidated && expected > 0 && count >= cld(expected, 2)
            frequencies = Vector{Float64}(undef, expected)
            data = Vector{ComplexF64}(undef, Base.checked_mul(block, expected))
            copydecodedrecords!(frequencies, data, chunks, count-1, block)
            empty!(chunks)
            offset = 0
            consolidated = true
        elseif count > offset + length(frequencies)
            offset = count-1
            capacity = min(blockrecords, max(1, 2length(frequencies)))
            expected > 0 && (capacity = min(capacity, expected-offset))
            frequencies = Vector{Float64}(undef, capacity)
            data = Vector{ComplexF64}(undef, Base.checked_mul(block, capacity))
            push!(chunks, (frequencies, data))
        end
        k = count-offset
        frequencies[k] = decoderecord!(data, (k-1)*block,
            nports, records.record, encoding, symmetric)
        readnetworkrecord!(records) || break
    end
    count = records.count
    expected > 0 && count != expected &&
        error(lazy"[Number of Frequencies] is $(expected), the network data has $(count).")
    if !consolidated
        frequencies = Vector{Float64}(undef, count)
        data = Vector{ComplexF64}(undef, Base.checked_mul(block, count))
        copydecodedrecords!(frequencies, data, chunks, count, block)
    end
    checkfrequencies(frequencies, "network in Hz")
    return frequencies, reshape(data, nports, nports, count)
end

function copydecodedrecords!(frequencies, data, chunks, count, block)
    offset = 0
    for (f, N) in chunks
        n = min(length(f), count-offset)
        copyto!(frequencies, offset+1, f, 1, n)
        copyto!(data, offset*block+1, N, 1, n*block)
        offset += n
    end
    return nothing
end

"""
    parsenoisedata!(noisedata, comments, io; requireend=false, allowend=true)

Append five-value noise records from `io` to `noisedata`, collect comments,
and return the number of noise frequencies. Values retain their file units,
including normalized version 1 resistance; the complete file parser converts
that resistance to ohms. Frequencies must be finite, nonnegative, and
strictly increasing.

Consume `[End]` when present. Set `requireend=true` to reject a missing
terminator, or `allowend=false` to reject it in version 1 input. Start at the
first noise record, after any `[Noise Data]` keyword.

# Examples
```jldoctest
networkdata = Float64[]
noisedata = Float64[]
comments = String[]
io = IOBuffer("1.0000 0.3926 -0.1211 -0.0003 -0.0021 -0.0003 -0.0021 0.3926 -0.1211\n2.0000 0.3517 -0.3054 -0.0096 -0.0298 -0.0096 -0.0298 0.3517 -0.3054\n10.000 0.3419 0.3336 -0.0134 0.0379 -0.0134 0.0379 0.3419 0.3336")
Touchstone.parsenetworkdata!(networkdata,comments,io,1.0)
Touchstone.parsenoisedata!(noisedata,comments,io)
println(noisedata)

# output
Float64[]
```
```jldoctest
networkdata = Float64[]
noisedata = Float64[]
comments = String[]
io = IOBuffer("2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n! NOISE PARAMETERS\n4 .7 .64 69 .38\n18 2.7 .46 -33 .40")
Touchstone.parsenetworkdata!(networkdata,comments,io,1.0)
Touchstone.parsenoisedata!(noisedata,comments,io)
println(noisedata)

# output
[4.0, 0.7, 0.64, 69.0, 0.38, 18.0, 2.7, 0.46, -33.0, 0.4]
```
```jldoctest
networkdata = Float64[]
noisedata = Float64[]
comments = String[]
io = IOBuffer("2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n4 .7 .64 69 19\n18 2.7 .46 -33 20\n[End]")
Touchstone.parsenetworkdata!(networkdata,comments,io,2.0)
Touchstone.parsenoisedata!(noisedata,comments,io)
println(noisedata)

# output
[4.0, 0.7, 0.64, 69.0, 19.0, 18.0, 2.7, 0.46, -33.0, 20.0]
```
"""
function parsenoisedata!(noisedata, comments, io; requireend=false, allowend=true)

    freq = 0.0
    nnoisefreq = 0
    vals = Float64[]

    while !readereof(io)

        line = stripdataline!(comments,readtouchstoneline(io))

        if isempty(strip(line))
            nothing
        elseif isoptionline(line)
            # Ignore additional option lines (Touchstone 2.0, "Option Line").
            nothing
        elseif isend(line)
            allowend || error("Version 1 files do not support [End].")
            return nnoisefreq
        elseif isnoisedata(line)
            error(lazy"Only one [Noise Data] keyword allowed.")
        else
            parsedataline!(vals, line)

            if length(vals) != 5
                error(lazy"Noise data lines must have 5 entries.")
            end

            if !(isfinite(vals[1]) && vals[1] >= 0)
                error(lazy"The noise data frequency $(vals[1]) is not a finite, nonnegative number on the line: $(line)")
            elseif nnoisefreq > 0 && !(vals[1] > freq)
                error(lazy"The noise data frequencies do not increase: $(vals[1]) follows $(freq) on the line: $(line)")
            end
            freq = vals[1]
            nnoisefreq += 1

            for val in vals
                push!(noisedata,val)
            end
        end
    end
    requireend && error("Missing [End].")
    return nnoisefreq
end
