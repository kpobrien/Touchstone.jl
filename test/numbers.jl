@testset "Numeric representation" begin
    @testset "decimal numbers" begin
        # Decimal numbers are accepted; hexadecimal, Inf, and NaN are rejected
        # in network data, noise data, reference impedances, and R.
        data = "1.0 0.5 0.1\n2.0 0.4 0.2\n"
        v2text(reference) = "[Version] 2.0\n# GHz S RI R 50\n[Number of Ports] 1\n[Number of Frequencies] 2\n[Reference] $(reference)\n[Network Data]\n" * data * "[End]\n"
        twoport = "# GHz S MA R 50\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n"
        for (text, token) in [("# GHz S RI R 50\n1.0 0x1p-1 0.1\n", "0x1p-1"), ("# GHz S RI R 50\n1.0 inf 0.1\n", "inf"),
                ("# GHz S RI R 50\n1.0 0.5 NaN\n", "NaN"), (twoport * "4 .7 .64 inf .38\n", "inf"), (v2text("0x32"), "0x32"), (v2text("Inf"), "Inf")]
            @test_throws ErrorException Touchstone.touchstone_parse(IOBuffer(text))
            @test occursin("\"$(lowercase(token))\" is not a decimal number", lowercase(sprint(showerror, try Touchstone.touchstone_parse(IOBuffer(text)) catch e; e end)))
        end
        @test_throws ErrorException Touchstone.touchstone_parse(IOBuffer("# GHz S RI R 0x32\n" * data))
        # Decimal forms use the same values.
        @test Touchstone.touchstone_parse(IOBuffer("# GHz S RI R 5e1\n1 +.5 -1E-1\n2. 4e-1 0.2\n")).N == Touchstone.touchstone_parse(IOBuffer("# GHz S RI R 50\n" * "1.0 0.5 -0.1\n2.0 0.4 0.2\n")).N
    end

    @testset "Decimal grammar" begin
        for good in ("0","-0.0","+.5","1.","123e-5",".123E+4")
            @test Touchstone.isdecimal(good)
        end
        for bad in ("","+",".","1e","1e+","NaN","Inf","0x1p-1","1\n","1 2","١")
            @test !Touchstone.isdecimal(bad)
        end
        # Exhaustive short-token agreement with the independent grammar.
        grammar = r"^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$"
        alphabet = ('0','1','.','e','+','-','x')
        mismatches = String[]
        for n in 1:5, chars in Iterators.product(ntuple(_->alphabet,n)...)
            token = join(chars)
            Touchstone.isdecimal(token) == occursin(grammar,token) || push!(mismatches,token)
        end
        @test isempty(mismatches)
    end

    @testset "IO display context cannot truncate numeric metadata" begin
        f = [1e9,2e9]; N = fill(0.123456789012345 + 0.234567890123456im,2,2,2)
        noise = [1.123456789012345, 0.234567890123456, 0.345678901234567,
            12.3456789012345, 23.4567890123456]
        for version in (1.0,2.0)
            options = (;version, R=51.23456789012345, noisedata=noise, format="RI")
            expected = written(f,N;options...)
            io = IOBuffer()
            Touchstone.touchstone_write(IOContext(io,:compact=>true,:limit=>true),f,N;options...)
            @test String(take!(io)) == expected
        end
    end

    @testset "Reusable decimal formatting matches Base" begin
        io = IOBuffer()
        digits = Vector{UInt8}(undef, Base.Ryu.neededdigits(Float64))
        values = [0.0, -0.0, nextfloat(0.0), -nextfloat(0.0), floatmin(Float64),
            floatmax(Float64), -floatmax(Float64), 1e-300, 1e300, 1.0, -1.0]
        # A deterministic sample across exponent and mantissa bit patterns,
        # including subnormal numbers, without an additional test dependency.
        bits = UInt64(1)
        for _ in 1:4096
            bits = bits * 0x5851f42d4c957f2d + 0x14057b7ef767814f
            x = reinterpret(Float64,bits)
            isfinite(x) && push!(values,x)
        end
        for x in values
            Touchstone.writefloat(io,x,digits)
            text = String(take!(io))
            @test text == string(x)
            @test isequal(parse(Float64,text),x)
        end
    end

    @testset "Numeric input conversion" begin
        tiny = big"1e-500"
        for version in (1.0, 2.0)
            for f in ([tiny], [-tiny], [big"1e500"], [BigFloat(NaN)])
                untouched(io -> Touchstone.touchstone_write(io, f, ones(ComplexF64,1,1,1);
                    version, frequencyunit="Hz", format="RI"))
                @test_throws ErrorException Touchstone.touchstone_file(f, ones(ComplexF64,1,1,1);
                    version, frequencyunit="Hz", format="RI")
            end
            for z in (tiny, -tiny, complex(tiny, 1), complex(1, -tiny), big"1e500")
                untouched(io -> Touchstone.touchstone_write(io, [1.0], fill(z,1,1,1);
                    version, frequencyunit="Hz", format="RI"))
                @test_throws ErrorException Touchstone.touchstone_file([1.0], fill(z,1,1,1);
                    version, frequencyunit="Hz", format="RI")
            end
        end
        # Exact zero, representable subnormals, and ordinary rounding remain valid.
        for x in (BigFloat(0), BigFloat(-0.0), BigFloat(nextfloat(0.0)),
                  big"0.1", big(1)//big(3), Float32(0.25))
            z = complex(x, -x)
            ts = Touchstone.touchstone_file([abs(x)], fill(z,1,1,1); frequencyunit="Hz", format="RI")
            @test isequal(ts.f[1], Float64(abs(x)))
            @test isequal(ts.N[1], ComplexF64(z))
            io = IOBuffer(); Touchstone.touchstone_write(io, ts)
            parsed = Touchstone.touchstone_parse(IOBuffer(take!(io)))
            @test isequal(parsed.N, ts.N)
        end
    end
end
