"""
    touchstone_save(filename::String, frequencies::AbstractVector,
        N::AbstractArray; version=1.0, reference=Float64[], R=50.0,
        format="RI", parameter="S", comments=[""], twoportdataorder="12_21",
        matrixformat="Full", frequencyunit="Hz",
        mixedmodeorder=Tuple{Char, Vector{Int}}[], information=String[],
        noisedata=Float64[])

Write network frequencies `frequencies` in Hz and physical parameters `N` to
`filename`. See [`touchstone_file`](@ref) for array dimensions, keyword meanings,
and validation. The defaults here select version 1, RI format, and Hz.

Preserve an explicit filename extension. When no extension is supplied, append
`.sNp` for versions 1.0 and 1.1, and `.ts` for versions 2.0 and 2.1, where `N`
is the number of ports. These defaults follow common naming conventions; the
Touchstone 2.1 specification permits `.ts` for all versions and allows other
extensions.
Warn when an `.sNp` extension does not match the port count.

Validate metadata, then encode and validate records while writing a temporary
file in the same directory. Replace the destination after successful writing
and close using `Base.rename`. Failures before replacement leave the destination
unchanged. Julia versions before 1.12 may fall back to copying if renaming fails.
Remove the temporary file on failure. Do not mutate the inputs during a write.
An existing regular file retains its read/write/execute permission bits.
Replacement does not preserve hard-link identity or follow an existing destination symlink, and
it does not guarantee persistence across a system crash. Return `nothing`.
"""
function touchstone_save(filename::String, frequencies::AbstractVector,
    N::AbstractArray; version=1.0, reference::AbstractVector{<:Real}=Float64[], R = 50.0,
    format::String="RI", parameter::String = "S", comments::Vector{String}=[""],
    twoportdataorder::String="12_21", matrixformat::String="Full",
    frequencyunit="Hz",
    mixedmodeorder::Vector{Tuple{Char, Vector{Int}}} = Tuple{Char, Vector{Int}}[],
    information::Vector{String} = String[], noisedata::AbstractVector{<:Real} = Float64[])

    ndims(N) == 3 || error("Network data must have two port axes and a frequency axis.")
    if size(N,1) == size(N,2)
        numberofports = size(N,1)
    else
        error(lazy"Network data arrays are not square.")
    end

    prepared = preparetouchstone(frequencies, N; version, reference, R, format,
        parameter, comments, twoportdataorder, matrixformat, frequencyunit,
        mixedmodeorder, information, noisedata)

    # Keep explicit extensions; only an omitted extension needs a default.
    extension = lowercase(splitext(filename)[2])
    if isempty(extension)
        extension = prepared.version < 2 ? ".s$(numberofports)p" : ".ts"
        @warn "Adding extension of $(extension)"
        filename *= extension
    elseif occursin(r"^\.s[0-9]+p$", extension) &&
            lstrip(extension[3:end-1], '0') != string(numberofports)
        @warn "Extension $(extension) does not match the $(numberofports)-port network."
    end

    encoding = networkencoding(prepared)
    record = Vector{Float64}(undef, 2length(encoding.indices)+1)
    atomicwrite(filename) do io
        emit_touchstone(io, prepared, encoding, record)
    end
    return nothing
end

"""
    touchstone_save(filename::String, ts::TouchstoneFile)

Write the current frequencies `ts.f`, physical parameters `ts.N`, and metadata
of `ts` to `filename`. Preserve the selected version, units, representation,
references, mixed-mode order, information, comments, and noise data. Recompute
port and frequency counts from the arrays.

Validation, filename handling, and file replacement are the same as for the
array form of [`touchstone_save`](@ref). Return `nothing`.

# Examples
```jldoctest
julia> ts = Touchstone.touchstone_file([1.0e9], fill(0.5+0.0im, 1, 1, 1);
           version=2.1, format="RI");

julia> mktempdir() do directory
           filename = joinpath(directory, "network.ts")
           touchstone_save(filename, ts)
           saved = touchstone_load(filename)
           (saved.version, saved.f, saved.N == ts.N)
       end
(2.1, [1.0e9], true)
```
"""
function touchstone_save(filename::String, ts::TouchstoneFile)
    return touchstone_save(filename, ts.f, ts.N; touchstoneoptions(ts)...)
end

function atomicwrite(writefile, filename)
    # A same-directory temporary file keeps replacement on one filesystem.
    # Do not use mv(force=true), whose fallback can remove the destination.
    temporary, io = mktemp(dirname(abspath(filename)))
    try
        writefile(io)
        close(io)
        isfile(filename) && chmod(temporary, filemode(filename) & 0o777)
        Base.rename(temporary, filename)
    finally
        try
            isopen(io) && close(io)
        finally
            ispath(temporary) && rm(temporary)
        end
    end

    return nothing
end

"""
    touchstone_write(io::IO, f::AbstractVector, N::AbstractArray; kwargs...)

Write network frequencies `f` in Hz and physical parameters `N` to `io`,
leaving the stream open. Accept the same keywords and defaults as
[`touchstone_file`](@ref): version 2, MA format, and GHz file frequencies.

Validate all metadata and encoded records before writing any bytes. Invalid
inputs leave `io` untouched; an IO failure during writing can leave partial
output. Do not mutate the inputs during a write. Use [`touchstone_save`](@ref)
for file replacement. Return `nothing`.

# Examples
```jldoctest
julia> io = IOBuffer();

julia> Touchstone.touchstone_write(io, [2.0e6], fill(0.5 - 0.25im, 1, 1, 1);
           version=1.0, format="RI", frequencyunit="MHz");

julia> print(String(take!(io)))
# MHz S RI R 50.0
! freq ReS11 ImS11
2.0 0.5 -0.25
```
"""
function touchstone_write(io::IO, f::AbstractVector, N::AbstractArray; kwargs...)
    prepared = preparetouchstone(f, N; kwargs...)
    encoding = networkencoding(prepared)
    record = checkencoding(prepared, encoding)
    return emit_touchstone(io, prepared, encoding, record)
end

"""
    touchstone_write(io::IO, ts::TouchstoneFile)

Write the current frequencies `ts.f`, physical parameters `ts.N`, and metadata
to `io`. Recompute port and frequency counts from the arrays. Validation and
IO behavior are the same as for the array form of [`touchstone_write`](@ref).
Return `nothing`.
"""
function touchstone_write(io::IO, ts::TouchstoneFile)
    return touchstone_write(io, ts.f, ts.N; touchstoneoptions(ts)...)
end

# Forward object metadata through the same validation as array inputs.
function touchstoneoptions(ts::TouchstoneFile)
    return (; frequencyunit=ts.frequencyunit, parameter=ts.parameter,
        format=ts.format, R=ts.R, version=ts.version,
        twoportdataorder=ts.twoportdataorder, reference=ts.reference,
        information=ts.information, matrixformat=ts.matrixformat,
        mixedmodeorder=ts.mixedmodeorder, comments=ts.comments, noisedata=ts.noisedata)
end

# Emit validated metadata, checking encoded records before writing them.
function emit_touchstone(io::IO, ts::TouchstoneFile, encoding, record)
    # Caller display preferences must never reduce file precision.
    io = IOContext(io, :compact => false)
    versionone = ts.version < 2
    for comment in ts.comments
        write(io, "!", encodedline(comment), "\n")
    end
    !versionone && println(io, "[Version] ", ts.version)
    print(io, "# ", ts.frequencyunit, ' ', ts.parameter, ' ', ts.format, " R")
    if ts.version == 1.1
        for r in ts.reference
            print(io, ' ', r)
        end
    else
        print(io, ' ', ts.R)
    end
    println(io)
    if !versionone
        println(io, "[Number of Ports] ", ts.numberofports)
        if !isempty(ts.information)
            println(io, "[Begin Information]")
            for entry in ts.information
                write(io, encodedline(entry), "\n")
            end
            println(io, "[End Information]")
        end
        ts.numberofports == 2 && println(io, "[Two-Port Data Order] ", ts.twoportdataorder)
        println(io, "[Number of Frequencies] ", ts.numberoffrequencies)
        ts.numberofnoisefrequencies > 0 &&
            println(io, "[Number of Noise Frequencies] ", ts.numberofnoisefrequencies)
        print(io, "[Reference]")
        for r in ts.reference
            print(io, ' ', r)
        end
        println(io)
        ts.matrixformat != "Full" && println(io, "[Matrix Format] ", ts.matrixformat)
        if !isempty(ts.mixedmodeorder)
            print(io, "[Mixed-Mode Order]")
            for (mode, ports) in ts.mixedmodeorder
                print(io, ' ', mode, join(ports, ','))
            end
            println(io)
        end
        println(io, "[Network Data]")
    end
    # Build a comparison string only when an existing comment could match.
    if any(comment -> startswith(lowercase(lstrip(comment)), "freq "), ts.comments)
        columnline = sprint(emitcolumnlabels, ts.parameter, encoding, ts.numberofports)
        normalized = lowercase(strip(columnline))
        # Preserve supplied comments; only suppress an equivalent new label.
        any(comment -> lowercase(strip(comment)) == normalized, ts.comments) ||
            println(io, '!', columnline)
    else
        print(io, '!')
        emitcolumnlabels(io, ts.parameter, encoding, ts.numberofports)
        println(io)
    end
    lastfrequency = emitnetwork(io, ts.f, ts.N, encoding, record, ts.numberofports)
    checknoisestart(ts, lastfrequency)
    if !isempty(ts.noisedata)
        !versionone && println(io, "[Noise Data]")
        emitnoise(io, ts.noisedata, ts.R, versionone)
    end
    !versionone && print(io, "[End]")
    return nothing
end

function emitnoise(io, data, R, versionone)
    buffer = IOBuffer()
    digits = Vector{UInt8}(undef, Base.Ryu.neededdigits(Float64))
    for first in 1:5:length(data)
        for column in 0:4
            value = data[first+column]
            versionone && column == 4 && (value /= R)
            writefloat(buffer, value, digits)
            write(buffer, column == 4 ? UInt8('\n') : UInt8(' '))
        end
        seekstart(buffer)
        write(io, buffer)
        truncate(buffer, 0)
        seekstart(buffer)
    end
    return nothing
end

function emitcolumnlabels(io, parameter, encoding, nports)
    print(io, " freq ")
    labels = encoding.fmt == :ri ? ("Re", "Im") :
        encoding.fmt == :ma ? ("mag", "ang") : ("logmag", "ang")
    portlabels = string.(1:nports)
    for I in encoding.indices, label in labels
        write(io, label)
        write(io, parameter)
        write(io, portlabels[I[1]])
        write(io, portlabels[I[2]])
        write(io, UInt8(' '))
    end
    return nothing
end

function emitnetwork(io, f, N, encoding, record, nports)
    # Reuse the byte buffer as well as the numeric buffer. Printing floats to
    # an IOBuffer avoids generic-IO formatting allocations and tiny writes.
    buffer = IOBuffer()
    digits = Vector{UInt8}(undef, Base.Ryu.neededdigits(Float64))
    indices = encoding.indices
    previous = -1.0
    for k in eachindex(f)
        encoderecord!(record, f, N, k, encoding)
        previous = checkencodedfrequency(record[1], previous, encoding.units)
        writefloat(buffer, record[1], digits)
        pairs = 0
        for j in eachindex(indices)
            write(buffer, UInt8(' '))
            writefloat(buffer, record[2j], digits)
            write(buffer, UInt8(' '))
            writefloat(buffer, record[2j+1], digits)
            pairs += 1
            if j < length(indices) && (pairs == 4 ||
                    (nports > 2 && indices[j][1] != indices[j+1][1]))
                println(buffer)
                pairs = 0
            end
        end
        println(buffer)
        seekstart(buffer)
        write(io, buffer)
        truncate(buffer, 0)
        seekstart(buffer)
    end
    return previous
end

# Reuse the digit buffer for shortest-round-trip Float64 formatting.
# Keep the internal Base.Ryu API isolated in this function.
function writefloat(io, value::Float64, digits::Vector{UInt8})
    next = Base.Ryu.writeshortest(digits, 1, value)
    write(io, @view digits[1:next-1])
    return nothing
end
