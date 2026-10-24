# Run with --project pointing to the revision being measured.
# Only standard libraries are needed. Fixture construction is not timed.
using Touchstone, Statistics, Printf
const T = Touchstone
f = collect(1.0:1000.0)
N = [complex(sin(i+j+k),cos(i-j+k)) for i in 1:16,j in 1:16,k in 1:1000]
function measure(label, fn)
    fn(); fn()
    times = Float64[]; bytes = Int[]
    for _ in 1:5
        GC.gc()
        sample = @timed fn()
        push!(times,sample.time); push!(bytes,sample.bytes)
    end
    @printf("%s,%.3f,%.3f\n",label,median(times)*1000,median(bytes)/1e6)
    flush(stdout)
end
println("Julia ",VERSION,"; CPU ",Sys.CPU_NAME,"; threads ",Threads.nthreads())
println("operation,median_ms,allocated_MB")
mktempdir() do dir
    path = joinpath(dir,"input.s16p")
    T.touchstone_save(path,f,N;version=1.0,format="RI",frequencyunit="Hz")
    text = read(path,String)
    println("# LF fixture bytes: ",sizeof(text))
    for (name,newline) in (("LF","\n"),("CRLF","\r\n"),("CR","\r"))
        content = replace(text,"\n"=>newline)
        write(path,content)
        # Assert physical data independently of the line-reader timing.
        got = T.touchstone_load(path)
        @assert got.f == f && got.N == N
        measure("load-"*name,()->T.touchstone_load(path))
        measure("buffer-"*name,()->T.touchstone_parse(IOBuffer(content)))
    end
    measure("save-RI",()->T.touchstone_save(path,f,N;
        version=1.0,format="RI",frequencyunit="Hz"))

    # Many ports and few frequencies expose metadata and column-label costs.
    frequencies = [1.0]
    parameters = [complex((i+j)/1024,(i-j)/4096) for i in 1:256,j in 1:256,k in 1:1]
    path = joinpath(dir,"many-ports.ts")
    options = (;version=2.1,format="RI",frequencyunit="Hz",comments=String[])
    T.touchstone_save(path,frequencies,parameters;options...)
    got = T.touchstone_load(path)
    @assert got.f == frequencies && got.N == parameters
    measure("save-p256-f1",()->T.touchstone_save(path,frequencies,parameters;options...))
    measure("write-p256-f1",()->T.touchstone_write(IOBuffer(),frequencies,parameters;options...))

    # Separate noise emission from balanced network/noise sweeps, with
    # no-noise and single-record controls for buffer setup costs.
    path = joinpath(dir,"noise.ts")
    cases = [(version,nf,10000) for version in (1.0,1.1,2.0,2.1) for nf in (1,10000)]
    append!(cases,[(2.1,10000,0),(2.1,1,1)])
    for (version,nf,nn) in cases
        frequencies = collect(1.0:nf)
        parameters = [complex(sin(i+j+k),cos(i-j+k)) for i in 1:2,j in 1:2,k in 1:nf]
        noise = Float64[]
        for k in 1:nn
            append!(noise,(Float64(k),1+0.5sin(k),0.5+0.1cos(k),30sin(k),75*(1+0.2cos(k))))
        end
        reference = version == 1.1 ? [75.0,90.0] : [75.0,75.0]
        options = (;version,R=75.0,reference,format="RI",frequencyunit="Hz",
            noisedata=noise,comments=String[])
        T.touchstone_save(path,frequencies,parameters;options...)
        got = T.touchstone_load(path)
        @assert got.f == frequencies && got.N == parameters
        @assert got.reference == reference && isapprox(got.noisedata,noise;rtol=2e-14)
        io = IOBuffer()
        T.touchstone_write(io,frequencies,parameters;options...)
        @assert take!(io) == read(path)
        label = "v$(version)-network$(nf)-noise$(nn)"
        measure("save-"*label,()->T.touchstone_save(path,frequencies,parameters;options...))
        measure("write-"*label,()->T.touchstone_write(IOBuffer(),frequencies,parameters;options...))
    end
end
