parsefile(text) = Touchstone.touchstone_parse(IOBuffer(text))
function parsedfields(text)
    ts = parsefile(text)
    return [getfield(ts, field) for field in fieldnames(Touchstone.TouchstoneFile)]
end

function v2text(data; version=2.0, n=1, nf=1, parameter="S", format="RI", extra="", ending="[End]")
    "[Version] $version\n# GHz $parameter $format R 50\n[Number of Ports] $n\n" *
    (n == 2 ? "[Two-Port Data Order] 12_21\n" : "") *
    "[Number of Frequencies] $nf\n$extra[Network Data]\n$data\n$ending\n"
end

function written(f, N; kwargs...)
    io = IOBuffer()
    Touchstone.touchstone_write(io, f, N; kwargs...)
    return String(take!(io))
end
written(N; f=collect(1.0:size(N,3)).*1e9, kwargs...) = written(f, N; kwargs...)

numericlines(text) = [parse.(Float64, split(line)) for line in split(text, '\n')
    if !isempty(strip(line)) && first(lstrip(line)) in ['0':'9'; '+'; '-'; '.']]

function untouched(f)
    io = IOBuffer()
    write(io, "existing")
    @test_throws ErrorException f(io)
    @test String(take!(io)) == "existing"
end
