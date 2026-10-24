# Private parser cursor: scan line delimiters in memory instead of reading
# individual bytes from the source. Byte offsets retain section lookahead.
mutable struct TouchstoneReader{I<:IO}
    source::I
    bytes::Vector{UInt8}
    next::Int
    count::Int
    offset::Int64
end
TouchstoneReader(io::IO, blocksize::Int=65536) =
    TouchstoneReader(io, Vector{UInt8}(undef, blocksize), 1, 0, readerposition(io))

# Parser operations for buffered cursors and ordinary IO.
readerposition(io::IO) = position(io)
seekreader!(io::IO, pos::Integer) = seek(io, pos)
readereof(io::IO) = eof(io)

readerposition(io::TouchstoneReader) = io.offset + io.next - 1
function seekreader!(io::TouchstoneReader, pos::Integer)
    if io.offset <= pos <= io.offset + io.count
        io.next = pos - io.offset + 1
    else
        seek(io.source, pos)
        io.offset, io.next, io.count = pos, 1, 0
    end
    return io
end
function readereof(io::TouchstoneReader)
    io.next <= io.count && return false
    io.offset += io.count
    io.count = readbytes!(io.source, io.bytes, length(io.bytes))
    io.next = 1
    return io.count == 0
end

function readtouchstoneline(io::TouchstoneReader)
    # Only lines spanning blocks need an accumulation buffer.
    buffer = nothing
    while !readereof(io)
        first = io.next
        last = first
        @inbounds while last <= io.count && io.bytes[last] != 0x0a && io.bytes[last] != 0x0d
            last += 1
        end
        if last <= io.count
            line = if buffer === nothing
                String(@view io.bytes[first:last-1])
            else
                write(buffer, @view io.bytes[first:last-1])
                String(take!(buffer))
            end
            cr = io.bytes[last] == 0x0d
            io.next = last + 1
            # CRLF can cross a block boundary. A lone CR still ends the line.
            cr && !readereof(io) && io.bytes[io.next] == 0x0a && (io.next += 1)
            return line
        end
        buffer === nothing && (buffer = IOBuffer())
        write(buffer, @view io.bytes[first:io.count])
        io.next = io.count + 1
    end
    return buffer === nothing ? "" : String(take!(buffer))
end

# Retain direct IO support for the low-level section readers.
# Read LF, CRLF or CR without decoding the bytes until the complete line exists.
function readtouchstoneline(io::IO)
    buffer = IOBuffer()
    while !readereof(io)
        byte = read(io, UInt8)
        byte == 0x0a && break
        if byte == 0x0d
            !readereof(io) && peek(io, UInt8) == 0x0a && read(io, UInt8)
            break
        end
        write(buffer, byte)
    end
    return String(take!(buffer))
end

"""
    encodedline(line::AbstractString)

Encode a text line as bytes using the reader's Latin-1/UTF-8 convention.
Use Latin-1 when every character fits in one byte and those bytes are not
also valid UTF-8; use UTF-8 otherwise. Non-ASCII text is a compatibility
extension. The caller validates the text and adds any line ending.

# Examples
```jldoctest
julia> Touchstone.encodedline(" 25 °C"), Touchstone.encodedline(" 50 Ω")
(UInt8[0x20, 0x32, 0x35, 0x20, 0xb0, 0x43], UInt8[0x20, 0x35, 0x30, 0x20, 0xce, 0xa9])
```
"""
function encodedline(line::AbstractString)
    if !isascii(line) && all(c -> UInt32(c) < 0x100, line)
        bytes = UInt8[UInt32(c) for c in line]
        isvalid(String, bytes) || return bytes
    end
    return Vector{UInt8}(codeunits(String(line)))
end

"""
    isdecimal(token::AbstractString)

Return `true` if `token` has decimal syntax: an optional sign, digits with an
optional decimal point, and an optional `e` or `E` exponent. Reject whitespace,
hexadecimal numbers, `Inf`, and `NaN`. This checks syntax only; use
[`parsedecimal`](@ref) to check the representable range.

# Examples
```jldoctest
julia> Touchstone.isdecimal.(["50", "-.5", "1.5e9", "0x1p-1", "inf", "nan"])
6-element BitVector:
 1
 1
 1
 0
 0
 0
```
"""
function isdecimal(token::AbstractString)
    bytes = codeunits(token)
    n, i = length(bytes), 1
    n == 0 && return false
    bytes[i] in (0x2b, 0x2d) && (i += 1)
    digits = 0
    while i <= n && 0x30 <= bytes[i] <= 0x39
        digits += 1
        i += 1
    end
    if i <= n && bytes[i] == 0x2e
        i += 1
        while i <= n && 0x30 <= bytes[i] <= 0x39
            digits += 1
            i += 1
        end
    end
    digits == 0 && return false
    if i <= n && bytes[i] in (0x65, 0x45)
        i += 1
        i <= n && bytes[i] in (0x2b, 0x2d) && (i += 1)
        firstdigit = i
        while i <= n && 0x30 <= bytes[i] <= 0x39
            i += 1
        end
        i == firstdigit && return false
    end
    return i == n + 1
end

"""
    parsedecimal(token::AbstractString, line::AbstractString)

Parse `token` as a finite `Float64` with the decimal syntax accepted by
[`isdecimal`](@ref). Reject overflow and nonzero values that round to zero.
Include the source `line` in syntax errors.
"""
function parsedecimal(token::AbstractString, line::AbstractString)
    isdecimal(token) ||
        error(lazy"\"$(token)\" is not a decimal number, on the line: $(line)")
    value = tryparse(Float64, token)
    value === nothing && error("Decimal number is outside the Float64 range: $(token)")
    isfinite(value) || error("Decimal number is outside the finite Float64 range: $(token)")
    if iszero(value)
        for c in token
            c in ('e', 'E') && break
            '1' <= c <= '9' && error("Decimal number underflows Float64: $(token)")
        end
    end
    return value
end

# Reuse numeric-line storage without allocating a token array for each line.
function parsedataline!(values::Vector{Float64}, line::String)
    empty!(values)
    for token in eachsplit(line)
        push!(values, parsedecimal(token, line))
    end
    return values
end

"""
    stripcommentslowercase!(comments::Vector{String}, line::String)

Append text after the first `!` to `comments`, preserving its case. Return
the remaining line in lowercase without stripping whitespace. Decode valid
UTF-8 as-is and invalid UTF-8 as Latin-1. See [`stripcomments!`](@ref) to
preserve the case of the returned line.

# Examples
```jldoctest
julia> comments=String[];println(Touchstone.stripcommentslowercase!(comments,"! This is a comment"));println(comments)

[" This is a comment"]

julia> comments=String[];println(Touchstone.stripcommentslowercase!(comments,"This is a !comment"));println(comments)
this is a
["comment"]

julia> comments=String[];println(Touchstone.stripcommentslowercase!(comments,"! 25 \\xb0C"));println(comments)

[" 25 °C"]
```
"""
stripcommentslowercase!(comments::Vector{String}, line::String) =
    lowercase(stripcomments!(comments, line))

"""
    stripcomments!(comments::Vector{String}, line::String)

Append text after the first `!` to `comments` and return the preceding text,
without changing case or stripping whitespace. Decode valid UTF-8 as-is and
invalid UTF-8 as Latin-1.

# Examples
```jldoctest
julia> comments = String[];

julia> Touchstone.stripcomments!(comments, "Model A ! measured at 25 °C")
"Model A "

julia> comments
1-element Vector{String}:
 " measured at 25 °C"
```
"""
function stripcomments!(comments::Vector{String}, line::String)
    if !isvalid(line)
        line = String(map(Char, codeunits(line)))
    end
    index = findfirst('!',line)
    if index != nothing
        push!(comments,line[nextind(line,index):end])
        return line[1:prevind(line,index)]
    else
        return line
    end
end

# Data records need case conversion only for option lines and section keywords.
# Decimal syntax accepts both e and E; comments retain their original case.
function stripdataline!(comments, line)
    text = stripcomments!(comments, line)
    return startswith(text, '#') || startswith(text, '[') ? lowercase(text) : text
end
