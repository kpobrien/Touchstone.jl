# Run with --project pointing to the revision being measured.
# Report warm parsing time and total allocation; fixture construction is excluded.
using Touchstone, Statistics, Printf

function measure(input)
    parse() = Touchstone.touchstone_parse(IOBuffer(input))
    parse(); parse()
    times, bytes = Float64[], Int[]
    for _ in 1:5
        GC.gc()
        result = @timed parse()
        push!(times,result.time)
        push!(bytes,result.bytes)
    end
    return 1000median(times), median(bytes)/1e6
end

println("Julia ", VERSION, "; CPU ", Sys.CPU_NAME, "; threads ", Threads.nthreads())
println("ports,frequencies,version,format,median_ms,allocated_MB")
for (ports,count) in ((2,10000),(16,1000),(64,50),(256,1))
    f = collect(1.0:count)
    N = [complex(sin(i+j+k),cos(i-j+k)) for i in 1:ports,j in 1:ports,k in 1:count]
    for version in (1.0,1.1,2.0,2.1), format in ("RI","MA","DB")
        ports != 16 && format != "RI" && continue
        io = IOBuffer()
        reference = version == 1.1 ? collect(50.0:49.0+ports) : fill(50.0,ports)
        Touchstone.touchstone_write(io,f,N;version,format,reference,frequencyunit="Hz")
        input = String(take!(io))
        parsed = Touchstone.touchstone_parse(IOBuffer(input))
        @assert parsed.f == f && isapprox(parsed.N,N;rtol=2e-14)
        @assert parsed.reference == reference
        ms,mb = measure(input)
        @printf("%d,%d,%.1f,%s,%.3f,%.3f\n",ports,count,version,format,ms,mb)
        flush(stdout)
    end
end
