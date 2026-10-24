"""
    isoptionline(line::String)

Return `true` if the `line` starts with `#` in column one.
This recognizes the prefix only; it does not validate the rest of the line.

# Examples
```jldoctest
julia> Touchstone.isoptionline("# MHz Z MA R 75")
true

julia> Touchstone.isoptionline("[number of ports] 1")
false
```
"""
function isoptionline(line::String)
    return startswith(line, '#')
end

"""
    parseoptionline(line::String)

Parse an option line into a `TouchstoneOptionLine` containing `frequencyunit`,
`parameter`, `format`, reference resistance `R` in ohms, and per-port
`reference` values when present.

Tokens are separated by whitespace and may appear in any order, except that
`R` must be followed by its positive, finite value. Missing parameters default
to GHz, S, MA, and R 50. Keep the first occurrence of each parameter and reject
unknown tokens. A version 1.1 list after `R` must finish the option line;
its first value supplies `R`. The complete file parser checks its length
against the port count. Strip comments before calling this helper.

# Examples
```jldoctest
julia> Touchstone.parseoptionline("# MHz Z MA R 75")
Touchstone.TouchstoneOptionLine("MHz", "Z", "MA", 75.0, Float64[])

julia> Touchstone.parseoptionline("# MHz H RI R 75")
Touchstone.TouchstoneOptionLine("MHz", "H", "RI", 75.0, Float64[])

julia> Touchstone.parseoptionline("# R 75 kHz Y")
Touchstone.TouchstoneOptionLine("kHz", "Y", "ma", 75.0, Float64[])
```
"""
function parseoptionline(line::String)
    # An empty option line uses the defaults for every parameter.
    frequencyunit = parameter = format = nothing
    R = nothing
    reference = Float64[]

    tokens = split(chopprefix(line, "#"))
    i = 1
    while i <= length(tokens)
        token = String(tokens[i])
        t = lowercase(token)
        if t == "hz" || t == "khz" || t == "mhz" || t == "ghz"
            frequencyunit = something(frequencyunit, token)
        elseif t == "s" || t == "y" || t == "z" || t == "g" || t == "h"
            parameter = something(parameter, token)
        elseif t == "db" || t == "ma" || t == "ri"
            format = something(format, token)
        elseif t == "r"
            n = i < length(tokens) && isdecimal(tokens[i+1]) ? parse(Float64, tokens[i+1]) : nothing
            if isnothing(n) || !(isfinite(n) && n > 0)
                error(lazy"R in the option line must be followed by a positive number of ohms: $(line)")
            end
            values = Float64[n]
            i += 1
            while i < length(tokens) && isdecimal(tokens[i+1])
                value = parsedecimal(tokens[i+1], line)
                value > 0 || error("Option-line reference resistances must be positive.")
                push!(values, value)
                i += 1
            end
            if length(values) > 1
                R === nothing && i == length(tokens) ||
                    error("A per-port reference list must be the only R entry and finish the option line.")
                reference = values
            end
            R = something(R, n)
        else
            error(lazy"Unknown option line parameter \"$(token)\"; the option line takes a frequency unit (Hz, kHz, MHz, GHz), a parameter (S, Y, Z, G, H), a format (DB, MA, RI) and R followed by its value, separated by whitespace: $(line)")
        end
        i += 1
    end

    return TouchstoneOptionLine(something(frequencyunit, "ghz"),
        something(parameter, "s"), something(format, "ma"), something(R, 50.0), reference)
end

"""
    isversion(line::String)

Return `true` if `line` starts with `[version]` in column one.
The caller must lowercase `line`. This checks only the prefix, not its arguments.

# Examples
```jldoctest
julia> Touchstone.isversion("[version] 2.0")
true

julia> Touchstone.isversion("[number of ports] 1")
false
```
"""
function isversion(line::String)
    return startswith(line, "[version]")
end

"""
    parseversion(line::String)

Return the floating-point version value after `[version]` in `line`.
The complete file parser validates whether the declared version is supported.
Strip comments before calling this helper.

# Examples
```jldoctest
julia> Touchstone.parseversion("[version] 2.0")
2.0
```
"""
function parseversion(line::String)
    return parse(Float64,line[10:end])
end

"""
    isnumberofports(line::String)

Return `true` if `line` starts with `[number of ports]` in column one.
The caller must lowercase `line`. This checks only the prefix, not its arguments.

# Examples
```jldoctest
julia> Touchstone.isnumberofports("[number of ports] 1")
true

julia> Touchstone.isnumberofports("[version] 1.0")
false
```
"""
function isnumberofports(line::String)
    return startswith(line, "[number of ports]")
end

"""
    parsenumberofports(line::String)

Return the decimal integer after `[number of ports]` in `line`. The complete file
parser checks that the port count is positive.
Strip comments before calling this helper.

# Examples
```jldoctest
julia> Touchstone.parsenumberofports("[number of ports] 1")
1
```
"""
function parsenumberofports(line::String)
    return parse(Int,line[18:end]; base=10)
end

"""
    istwoportdataorder(line::String)

Return `true` if `line` starts with `[two-port data order]` in column one.
The caller must lowercase `line`. This checks only the prefix, not its arguments.

# Examples
```jldoctest
julia> Touchstone.istwoportdataorder("[two-port data order] 12_21")
true

julia> Touchstone.istwoportdataorder("[version] 1.0")
false
```
"""
function istwoportdataorder(line::String)
    return startswith(line, "[two-port data order]")
end

"""
    parsetwoportdataorder(line::String)

Return `"12_21"` or `"21_12"` from a `[two-port data order]` line.
Reject other order strings.
Strip comments before calling this helper.

# Examples
```jldoctest
julia> Touchstone.parsetwoportdataorder("[two-port data order] 12_21")
"12_21"

julia> Touchstone.parsetwoportdataorder("[two-port data order] 21_12")
"21_12"
```
"""
function parsetwoportdataorder(line::String)
    twoportdataorder = strip(line[22:end])
    if !(twoportdataorder == "12_21" || twoportdataorder == "21_12")
        error(lazy"Unknown [Two-Port Data Order] parameter: $(line)")
    end
    return String(twoportdataorder)
end

"""
    isbegininformation(line::String)

Return `true` if `line` starts with `[begin information]` in column one.
The caller must lowercase `line`. This checks only the prefix, not its arguments.

# Examples
```jldoctest
julia> Touchstone.isbegininformation("[begin information]")
true

julia> Touchstone.isbegininformation("[version] 1.0")
false
```
"""
function isbegininformation(line::String)
    return startswith(line, "[begin information]")
end

"""
    isendinformation(line::String)

Return `true` if `line` is `[end information]`, allowing trailing whitespace.
The caller must lowercase `line` and strip comments.

# Examples
```jldoctest
julia> Touchstone.isendinformation("[end information]")
true

julia> Touchstone.isendinformation("[version] 1.0")
false
```
"""
function isendinformation(line::String)
    return rstrip(line) == "[end information]"
end

"""
    parseinformation!(information::Vector{String}, comments::Vector{String},
        io::Union{IO,TouchstoneReader})

Append information-section lines from `io` to `information`, preserving case.
Append comments separately to `comments`. Start after `[Begin Information]`
and consume the required `[End Information]` terminator. Return `nothing`.

# Examples
```jldoctest
information = String[]
comments = String[]
io = IOBuffer("This is an information section.\n[End Information]")
Touchstone.parseinformation!(information,comments,io)
println(information)

# output
["This is an information section."]
```
"""
function parseinformation!(information::Vector{String},
        comments::Vector{String}, io::Union{IO,TouchstoneReader})
    while !readereof(io)
        line = stripcomments!(comments, readtouchstoneline(io))
        isendinformation(lowercase(line)) && return nothing
        push!(information, line)
    end
    error("Missing [End Information].")
end

"""
    isnumberoffrequencies(line::String)

Return `true` if `line` starts with `[number of frequencies]` in column one.
The caller must lowercase `line`. This checks only the prefix, not its arguments.

# Examples
```jldoctest
julia> Touchstone.isnumberoffrequencies("[number of frequencies]")
true

julia> Touchstone.isnumberoffrequencies("[version] 1.0")
false
```
"""
function isnumberoffrequencies(line::String)
    return startswith(line, "[number of frequencies]")
end

"""
    parsenumberoffrequencies(line::String)

Return the positive decimal integer after `[number of frequencies]` in `line`.
Reject zero or negative counts.
Strip comments before calling this helper.

# Examples
```jldoctest
julia> Touchstone.parsenumberoffrequencies("[number of frequencies] 10")
10
```
"""
function parsenumberoffrequencies(line::String)
    numberoffrequencies = parse(Int,line[24:end]; base=10)
    if numberoffrequencies < 1
        error(lazy"Number of frequencies must be an integer greater than zero: $(line)")
    end
    return numberoffrequencies
end

"""
    isnumberofnoisefrequencies(line::String)

Return `true` if `line` starts with `[number of noise frequencies]` in column one.
The caller must lowercase `line`. This checks only the prefix, not its arguments.

# Examples
```jldoctest
julia> Touchstone.isnumberofnoisefrequencies("[number of noise frequencies]")
true

julia> Touchstone.isnumberofnoisefrequencies("[version] 1.0")
false
```
"""
function isnumberofnoisefrequencies(line::String)
    return startswith(line, "[number of noise frequencies]")
end

"""
    parsenumberofnoisefrequencies(line::String)

Return the positive decimal integer after `[number of noise frequencies]` in `line`.
Reject zero or negative counts; omit the keyword when no noise data are present.
Strip comments before calling this helper.

# Examples
```jldoctest
julia> Touchstone.parsenumberofnoisefrequencies("[number of noise frequencies] 10")
10
```
"""
function parsenumberofnoisefrequencies(line::String)
    numberofnoisefrequencies = parse(Int,line[30:end]; base=10)
    if numberofnoisefrequencies < 1
        error(lazy"Number of noise frequencies must be an integer greater than zero: $(line)")
    end
    return numberofnoisefrequencies
end

"""
    isreference(line::String)

Return `true` if `line` starts with `[reference]` in column one.
The caller must lowercase `line`. This checks only the prefix, not its arguments.

# Examples
```jldoctest
julia> Touchstone.isreference("[reference]")
true

julia> Touchstone.isreference("[version] 1.0")
false
```
"""
function isreference(line::String)
    return startswith(line, "[reference]")
end

"""
    parsereference!(reference::Vector{Float64}, comments::Vector{String},
        line::String, numberofports::Int, io::Union{IO,TouchstoneReader})

Append positive, finite reference impedances in ohms to `reference`, starting
with the lowercased `[reference]` line `line` and reading continuation lines
from `io` until there is one value per port. Reject too few or too many values.
The caller strips comments from `line`; comments on continuation lines are
appended to `comments`. Return `nothing`.

# Examples
```jldoctest
io = IOBuffer("[Reference] 50.0 60.0 75.0")
numberofports = 3
comments = String[]
reference = Float64[]
line = Touchstone.stripcommentslowercase!(comments,readline(io))
Touchstone.parsereference!(reference, comments, line, numberofports, io)
println(reference)

# output
[50.0, 60.0, 75.0]
```
```jldoctest
io = IOBuffer("[Reference] 50.0 \n60.0 75.0")
numberofports = 3
comments = String[]
reference = Float64[]
line = Touchstone.stripcommentslowercase!(comments,readline(io))
Touchstone.parsereference!(reference, comments, line, numberofports, io)
println(reference)

# output
[50.0, 60.0, 75.0]
```
```jldoctest
io = IOBuffer("[Reference] 50.0 \n60.0 75.0\n[Number of Frequencies] 1")
numberofports = 3
comments = String[]
reference = Float64[]
line = Touchstone.stripcommentslowercase!(comments,readline(io))
Touchstone.parsereference!(reference, comments, line, numberofports, io)
println(reference)

# output
[50.0, 60.0, 75.0]
```
```jldoctest
io = IOBuffer("[Reference] .5 +75")
numberofports = 2
comments = String[]
reference = Float64[]
line = Touchstone.stripcommentslowercase!(comments,readline(io))
Touchstone.parsereference!(reference, comments, line, numberofports, io)
println(reference)

# output
[0.5, 75.0]
```
"""
function parsereference!(reference::Vector{Float64}, comments::Vector{String},
    line::String, numberofports::Int, io::Union{IO,TouchstoneReader})
    # Reference values may continue on subsequent lines.
    append!(reference, parsedecimal.(split(chopprefix(line, "[reference]")), line))
    while length(reference) < numberofports && !readereof(io)
        line = stripcommentslowercase!(comments, readtouchstoneline(io))
        isoptionline(line) && continue
        append!(reference, parsedecimal.(split(line), line))
    end

    length(reference) < numberofports && error("Incomplete [Reference].")
    if length(reference) > numberofports
        error(lazy"Too many values on [Reference] line: $(line)")
    end
    if !all(z -> isfinite(z) && z > 0, reference)
        error(lazy"The [Reference] impedances must be positive numbers of ohms: $(reference)")
    end

    return nothing
end

"""
    ismatrixformat(line::String)

Return `true` if `line` starts with `[matrix format]` in column one.
The caller must lowercase `line`. This checks only the prefix, not its arguments.

# Examples
```jldoctest
julia> Touchstone.ismatrixformat("[matrix format] full")
true

julia> Touchstone.ismatrixformat("[version] 1.0")
false
```
"""
function ismatrixformat(line::String)
    return startswith(line, "[matrix format]")
end

"""
    parsematrixformat(line::String)

Return `"Full"`, `"Lower"`, or `"Upper"` from a lowercased `[matrix format]`
line with comments removed.

# Examples
```jldoctest
julia> Touchstone.parsematrixformat("[matrix format] lower")
"Lower"

julia> Touchstone.parsematrixformat("[matrix format] upper")
"Upper"
```
"""
function parsematrixformat(line::String)
    matrixformat = strip(line[16:end])
    if matrixformat == "full"
        return "Full"
    elseif matrixformat == "lower"
        return "Lower"
    elseif matrixformat == "upper"
        return "Upper"
    else
        error(lazy"Unknown format: $(matrixformat)")
    end
end

"""
    ismixedmodeorder(line::String)

Return `true` if `line` starts with `[mixed-mode order]` in column one.
The caller must lowercase `line`. This checks only the prefix, not its arguments.

# Examples
```jldoctest
julia> Touchstone.ismixedmodeorder("[mixed-mode order] d1,2 c1,2")
true

julia> Touchstone.ismixedmodeorder("[version] 1.0")
false
```
"""
function ismixedmodeorder(line::String)
    return startswith(line, "[mixed-mode order]")
end

"""
    parsemixedmodeorder!(mixedmodeorder::Vector{Tuple{Char, Vector{Int}}},
        line::String)
    parsemixedmodeorder!(mixedmodeorder, comments, line, numberofports, io)

Append descriptors from a `[Mixed-Mode Order]` line to `mixedmodeorder` as
`(mode, ports)` tuples. Convert mode letters to uppercase and port indices
to integers. The five-argument form also reads continuation lines from `io`,
collects their comments, and requires `numberofports` descriptors. Strip
comments from the initial `line` before calling either form.

These helpers parse descriptor syntax; port coverage, pairing, and reference
impedances are checked when constructing or parsing the complete file.
Return `nothing`.

# Examples
```jldoctest
julia> mixedmodeorder = Tuple{Char, Vector{Int}}[];Touchstone.parsemixedmodeorder!(mixedmodeorder,"[Mixed-Mode Order] D2,3 D6,5 C2,3 C6,5 S4 S1");mixedmodeorder
6-element Vector{Tuple{Char, Vector{Int64}}}:
 ('D', [2, 3])
 ('D', [6, 5])
 ('C', [2, 3])
 ('C', [6, 5])
 ('S', [4])
 ('S', [1])
```
"""
function parsemixedmodeorder!(mixedmodeorder::Vector{Tuple{Char, Vector{Int}}},
        line::String)
    for token in split(line[19:end])
        occursin(r"^[sSdDcC][0-9]+(,[0-9]+)?$", token) ||
            error("Invalid mixed-mode descriptor: $(token)")
        push!(mixedmodeorder, (uppercase(first(token)), parse.(Int, split(token[2:end], ','))))
    end
    return nothing
end

function parsemixedmodeorder!(order, comments, line, nports, io)
    parsemixedmodeorder!(order, line)
    while length(order) < nports && !readereof(io)
        line = stripcommentslowercase!(comments, readtouchstoneline(io))
        isoptionline(line) && continue
        startswith(line, "[") && error("Incomplete [Mixed-Mode Order].")
        parsemixedmodeorder!(order, "[Mixed-Mode Order] " * line)
    end
    length(order) == nports || error("Number of mixed mode order descriptors must match the number of ports.")
    return nothing
end

"""
    isend(line::String)

Return `true` if `line` is `[end]`, allowing trailing whitespace.
The caller must lowercase `line` and strip comments.

# Examples
```jldoctest
julia> Touchstone.isend("[end]")
true

julia> Touchstone.isend("[version] 1.0")
false
```
"""
function isend(line::String)
    return rstrip(line) == "[end]"
end

"""
    isnoisedata(line::String)

Return `true` if `line` is `[noise data]`, allowing trailing whitespace.
The caller must lowercase `line` and strip comments.

# Examples
```jldoctest
julia> Touchstone.isnoisedata("[noise data]")
true

julia> Touchstone.isnoisedata("[version] 1.0")
false
```
"""
function isnoisedata(line::String)
    return rstrip(line) == "[noise data]"
end
