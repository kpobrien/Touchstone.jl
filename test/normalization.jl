@testset "Normalization" begin

    @testset "Version 2 physical values" begin
        matrix = ComplexF64[1+2im 3-4im; -5+6im 7+8im]
        N = reshape(matrix,2,2,1)
        for version in (2.0,2.1), parameter in ("S","Z","Y","H","G"), format in ("RI","MA","DB")
            pair(z) = format == "RI" ? (real(z),imag(z)) :
                (format == "MA" ? abs(z) : 20log10(abs(z)), rad2deg(angle(z)))
            values = collect(Iterators.flatten(pair(matrix[i,j]) for i in 1:2 for j in 1:2))
            noise = [1.0,0.5,0.25,90.0,2.0]
            text = v2text("1 " * join(values,' ');version,n=2,parameter,format,
                extra="[Reference] 4 9\n[Number of Noise Frequencies] 1\n",
                ending="[Noise Data]\n1 .5 .25 90 2\n[End]")
            ts = parsefile(text)
            @test ts.N ≈ N rtol=3e-14
            @test ts.reference == [4,9]
            @test ts.R == 50
            @test ts.noisedata == noise
            made = Touchstone.touchstone_file(ts.f,N;version,parameter,format,
                reference=[4,9],frequencyunit="GHz",noisedata=noise)
            @test made.version == version
            @test made.N === N
            io = IOBuffer(); Touchstone.touchstone_write(io,made)
            output = String(take!(io))
            @test startswith(output,"[Version] $version\n")
            @test first(numericlines(output)) ≈ [1; values] rtol=3e-14
            @test last(numericlines(output)) == noise
            @test parsefile(output).version == version
        end
    end
    @testset "Numeric references in conversion helpers" begin
        for version in (1,1.1), refs in ([4,9],[4.0,9.0])
            raw = [1.0,1,0,2,0,3,0,4,0]
            f,N = Touchstone.networkdatatoarray(raw,2,1,"Full","21_12",
                "Z","Hz","RI",4,version;reference=refs)
            expected = version == 1 ? [4 12;8 16] : [4 18;12 36]
            @test N[:,:,1] ≈ expected
            @test Touchstone.arraytonetworkdata(f,N,2,1,"Full","21_12",
                "Z","Hz","RI",4,version;reference=refs) ≈ raw
        end
    end


    @testset "Version 1.1 normalization" begin
        # Independent factors for port references 4 and 9 ohms, in matrix order.
        factors = (S=ones(2,2), Z=[4 6;6 9], Y=[1/4 1/6;1/6 1/9],
            H=[4 2/3;2/3 1/9], G=[1/4 3/2;3/2 9])
        normalized = ComplexF64[1+2im 3-4im; -5+6im 7+8im]
        for (parameter, factor) in pairs(factors), format in ("RI","MA","DB")
            pair(z) = format == "RI" ? (real(z),imag(z)) :
                (format == "MA" ? abs(z) : 20log10(abs(z)), rad2deg(angle(z)))
            raw = collect(Iterators.flatten(pair(z) for z in normalized))
            input = "# Hz $parameter $format R 4 9\n1 " * join(raw, ' ') * "\n"
            expected = reshape(normalized .* factor,2,2,1)
            @test parsefile(input).N ≈ expected rtol=3e-14
            output = written([1.0],expected; version=1.1, reference=[4.0,9.0],
                parameter=String(parameter), format, frequencyunit="Hz")
            # Check file tokens independently of the package decoder.
            @test only(numericlines(output))[2:end] ≈ raw rtol=3e-14
            @test parsefile(output).N ≈ expected rtol=3e-14
            @test occursin(" R 4.0 9.0\n",output)
            @test !occursin("[Version]",output) && !occursin("[Reference]",output)
            v1 = written([1.0],expected; version=1.0, R=9.0,
                parameter=String(parameter), format, frequencyunit="Hz")
            v11 = written([1.0],expected; version=1.1, reference=[9.0,9.0],
                parameter=String(parameter), format, frequencyunit="Hz")
            @test numericlines(v1) == numericlines(v11)
        end
        # Unequal references can have a ratio outside Float64 even when the result fits.
        for (parameter, refs) in (("H",[1e308,1e-320]), ("G",[1e-320,1e308]))
            input = "# Hz $parameter RI R $(join(refs,' '))\n1 0 0 1e-300 0 1e-300 0 0 0\n"
            expected = setprecision(256) do
                a,b = BigFloat.(refs)
                Float64(BigFloat(1e-300) * sqrt(parameter == "H" ? a/b : b/a))
            end
            ts = parsefile(input)
            @test ts.N[1,2,1] ≈ expected rtol=3e-15
            @test ts.N[2,1,1] ≈ expected rtol=3e-15
            for format in ("RI","MA")
                output = written(ts.f,ts.N; version=1.1, reference=refs,
                    parameter,format,frequencyunit="Hz")
                @test parsefile(output).N ≈ ts.N rtol=3e-15
            end
            dbinput = "# Hz $parameter DB R $(join(refs,' '))\n1 -6000 0 -6000 0 -6000 0 -6000 0\n"
            @test parsefile(dbinput).N[1,2,1] ≈ expected rtol=3e-13
        end
        for parameter in ("Z","Y"), refs in ([1e300,1e200],[1e-300,1e-200])
            rawvalue = parameter == "Z" ? 1e-50 : 1e50
            input = "# Hz $parameter RI R $(join(refs,' '))\n1 0 0 $rawvalue 0 $rawvalue 0 0 0\n"
            expected = setprecision(256) do
                scale = sqrt(prod(BigFloat.(refs)))
                Float64(parameter == "Z" ? BigFloat(rawvalue)*scale : BigFloat(rawvalue)/scale)
            end
            @test parsefile(input).N[1,2,1] ≈ expected rtol=3e-15
        end
    end

    @testset "Subnormal reference normalization" begin
        r = nextfloat(0.0)
        for refs in ([r,2r], [3r,7r], [r,floatmin(Float64)],
                     [prevfloat(floatmin(Float64)),floatmin(Float64)], [r,r]),
            parameter in ("Z","Y"), format in ("RI","MA","DB")
            x = parameter == "Z" ? 1e300 : 1e-300
            a = format == "DB" ? 20log10(x) : x
            b = format == "RI" ? x/3 : 27.0
            raw = repeat([a,b],4)
            input = "# Hz $parameter $format R $(join(refs,' '))\n1 " *
                join(raw,' ') * "\n"
            # Compute physical values without rounding the reference product.
            expected = setprecision(512) do
                value = format == "RI" ? complex(BigFloat(a),BigFloat(b)) :
                    (format == "DB" ? BigFloat(10)^(BigFloat(a)/20) : BigFloat(a)) *
                    complex(cospi(BigFloat(b)/180),sinpi(BigFloat(b)/180))
                [ComplexF64(parameter == "Z" ?
                    value * sqrt(BigFloat(ri)*BigFloat(rj)) :
                    value / sqrt(BigFloat(ri)*BigFloat(rj))) for ri in refs, rj in refs]
            end
            parsed = parsefile(input)
            for i in 1:2, j in 1:2
                @test parsed.N[i,j,1] ≈ expected[i,j] rtol=5e-13
            end
            output = written([1.0],reshape(expected,2,2,1); version=1.1,
                reference=refs, parameter, format, frequencyunit="Hz")
            # Check file values without using the package decoder.
            @test only(numericlines(output))[2:end] ≈ raw rtol=5e-13
        end
    end

    @testset "Version 1.1 noise normalization" begin
        input = "# Hz S RI R 4 9\n1 1 0 2 0 3 0 4 0\n1 0.5 0.25 90 0.5\n"
        ts = parsefile(input)
        @test ts.noisedata == [1.0,0.5,0.25,90.0,2.0]
        rebuilt = Touchstone.touchstone_file(ts.f,ts.N; version=1.1,
            reference=[4.0,9.0], R=50.0, frequencyunit="Hz",noisedata=ts.noisedata)
        @test rebuilt.R == 4.0
        output = written(ts.f,ts.N; version=1.1, reference=[4.0,9.0],
            frequencyunit="Hz",format="RI",noisedata=ts.noisedata)
        @test last(numericlines(output)) == [1.0,0.5,0.25,90.0,0.5]
        @test parsefile(output).noisedata == ts.noisedata
    end
    @testset "Polar angles in degrees" begin
        for format in ("MA", "DB"), phase in (0.0,90.0,180.0,-90.0,1e12,-1e16,1e20,1e308)
            magnitude = format == "MA" ? 1 : 0
            input = "# Hz S $format R 50\n1 $magnitude $phase\n"
            expected = setprecision(2048) do
                reduced = mod(BigFloat(phase), BigFloat(360))
                ComplexF64(cospi(reduced/180), sinpi(reduced/180))
            end
            @test abs(parsefile(input).N[1]-expected) <= 2eps(Float64)
        end
        @test parsefile("# Hz S MA R 50\n1 1 90\n").N[1] == im
        @test parsefile("# Hz S DB R 50\n1 0 180\n").N[1] == -1
    end

    @testset "version 1 normalization" begin
        # Version 1 Z data normalized to 75 ohms (Example 9) must match the
        # physical values in version 2 (Example 10).
        example9 = "# MHz Z MA R 75\n100 0.99 -4\n200 0.80 -22\n300 0.707 -45\n400 0.40 -62\n500 0.01 -89\n"
        example10 = "[Version] 2.0\n# MHz Z MA\n[Number of Ports] 1\n[Number of Frequencies] 5\n[Reference] 20.0\n[Network Data]\n100 74.25 -4\n200 60 -22\n300 53.025 -45\n400 30 -62\n500 0.75 -89\n[End]\n"
        parse(text) = Touchstone.touchstone_parse(IOBuffer(text)).N
        @test parse(example9) ≈ parse(example10)
        # Y = y / R, H11 = h11 R, H22 = h22 / R, G11 = g11 / R, and G22 = g22 R.
        # RI and DB decoding must agree with the corresponding physical values.
        v2text(p, values) = "[Version] 2.0\n# GHz $(p) RI R 50\n[Number of Ports] $(length(values) == 2 ? 1 : 2)\n" *
            (length(values) == 2 ? "" : "[Two-Port Data Order] 21_12\n") *
            "[Number of Frequencies] 1\n[Network Data]\n1.0 $(join(values, ' '))\n[End]\n"
        db(x, y) = "$(20 * log10(abs(complex(x, y)))) $(rad2deg(angle(complex(x, y))))"
        for (p, normalized, twin) in [
                ("Z", [2.0, 0.4], [100.0, 20.0]),
                ("Y", [0.5, 0.1], [0.01, 0.002]),
                ("H", [2.0, 0.4, -1.0, 0.0, 1.0, 0.0, 0.5, 0.1], [100.0, 20.0, -1.0, 0.0, 1.0, 0.0, 0.01, 0.002]),
                ("G", [0.5, 0.1, 1.0, 0.0, -1.0, 0.0, 2.0, 0.4], [0.01, 0.002, 1.0, 0.0, -1.0, 0.0, 100.0, 20.0])]
            @test parse("# GHz $(p) RI R 50\n1.0 $(join(normalized, ' '))\n") ≈ parse(v2text(p, twin))
            indb = join((db(normalized[k], normalized[k+1]) for k in 1:2:length(normalized)), ' ')
            @test parse("# GHz $(p) DB R 50\n1.0 $(indb)\n") ≈ parse(v2text(p, twin))
        end
        # Each version 1 parameter family and format must round-trip in physical units.
        N = [0.3 + 0.1im 0.02 - 0.5im; 1.5 + 0.2im 0.04 + 0.01im;;; 0.2 - 0.3im 0.1 + 0.6im; -1.2 + 0.4im 0.03 - 0.02im]
        for p in ["S", "Z", "Y", "G", "H"], format in ["RI", "MA", "DB"]
            io = IOBuffer()
            Touchstone.touchstone_write(io, [1.0e9, 2.0e9], N; version = 1.0, R = 50.0, parameter = p, format = format)
            @test Touchstone.touchstone_parse(IOBuffer(take!(io))).N ≈ N
        end
    end

    @testset "version 1 noise resistance" begin
        # Version 1 noise resistance is normalized to R. At R = 50 ohms,
        # 0.38 and 0.40 in Example 18 match 19 and 20 ohms in Example 19.
        example18 = "#\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n4 .7 .64 69 .38\n18 2.7 .46 -33 .40\n"
        example19 = "[Version] 2.0\n#\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50 25.0\n[Network Data]\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n4 .7 .64 69 19\n18 2.7 .46 -33 20\n[End]\n"
        v1, v2 = (Touchstone.touchstone_parse(IOBuffer(t)) for t in (example18, example19))
        @test v1.noisedata ≈ v2.noisedata == [4.0, 0.7, 0.64, 69.0, 19.0, 18.0, 2.7, 0.46, -33.0, 20.0]
        # Check another reference resistance and writing in both versions.
        @test Touchstone.touchstone_parse(IOBuffer(replace(example18, "#\n" => "# GHz S MA R 75\n"))).noisedata[5:5:end] ≈ [0.38, 0.40] .* 75
        for version in (1.0, 2.0)
            io = IOBuffer()
            Touchstone.touchstone_write(io, v2.f, v2.N; version = version, R = 75.0, frequencyunit = "GHz", noisedata = v2.noisedata)
            @test Touchstone.touchstone_parse(IOBuffer(take!(io))).noisedata ≈ v2.noisedata
        end
    end

    @testset "arraytonetworkdata errors" begin

        begin
            frequencies = 4.0e9:5.0e8:6.0e9
            N = [0.9546262517670427 - 0.296397700700921im;;; 0.8915960960938982 - 0.44358732281729774im;;; 0.9857309246425359 + 0.046691189499470154im;;; 0.9759591344506418 - 0.21128542054786678im;;; 0.9604441706426364 - 0.2762239892126382im]
            numberofports = 1
            numberoffrequencies = 5
            matrixformat = "Other"
            twoportdataorder = "12_21"
            parameter = "S"
            frequencyunit = "GHz"
            format = "MA"
            R = 50.0
            version = 2.0
            @test_throws(
                ErrorException("Unknown matrix format."),
                Touchstone.arraytonetworkdata(frequencies,N, numberofports, numberoffrequencies,
                    matrixformat, twoportdataorder, parameter, frequencyunit, format, R, version)
            )
        end

        begin
            frequencies = 4.0e9:5.0e8:6.0e9
            N = [0.9546262517670427 - 0.296397700700921im;;; 0.8915960960938982 - 0.44358732281729774im;;; 0.9857309246425359 + 0.046691189499470154im;;; 0.9759591344506418 - 0.21128542054786678im;;; 0.9604441706426364 - 0.2762239892126382im]
            numberofports = 1
            numberoffrequencies = 5
            matrixformat = "Full"
            twoportdataorder = "12_21"
            parameter = "K"
            frequencyunit = "GHz"
            format = "MA"
            R = 50.0
            version = 2.0
            @test_throws(
                ErrorException("Unknown format or version"),
                Touchstone.arraytonetworkdata(frequencies,N, numberofports, numberoffrequencies,
                    matrixformat, twoportdataorder, parameter, frequencyunit, format, R, version)
            )
        end
    end

    @testset "networkdatatoarray errors" begin

        networkdata = [4.0, 0.9995813511383583, -17.248815971093425, 4.5, 0.9958480363660398, -26.451285931791276, 5.0, 0.9868361175866559, 2.711906450972103, 5.5, 0.9985678550072272, -12.21545548845392, 6.0, 0.9993761539770525, -16.045248853866596]
        numberofports = 1
        numberoffrequencies = 5
        matrixformat = "Full"
        twoportdataorder = "12_21"
        parameter = "K"
        frequencyunit = "ghz"
        format = "ma"
        R = 50.0
        version = 2.0
        @test_throws(
            ErrorException("Unknown format or version"),
            Touchstone.networkdatatoarray(networkdata, numberofports,
                numberoffrequencies, matrixformat, twoportdataorder, parameter,
                frequencyunit, format, R, version)
            )

    end

    @testset "frequencyscale" begin
        @test_throws(
            ErrorException("Unknown frequency unit THz"),
            Touchstone.frequencyscale("THz")
        )
    end

    @testset "Finite range and stable normalization" begin
        for version in (1.0,2.0), x in (1e-200,1e200), parameter in ("S","Z","Y")
            text = written(fill(ComplexF64(x),1,1,1); version, parameter, format="DB")
            @test !occursin(r"(?i)\b(inf|nan)\b",text)
            @test parsefile(text).N[1] ≈ x rtol=2e-13
        end
        @test parsefile("# Hz Z DB R 1e-200\n1 7000 0\n").N[1] ≈ 1e150 rtol=2e-13
        @test parsefile("# Hz Y RI R 1e-320\n1 1e-320 0\n").N[1] == 1
        @test parsefile("# Hz Y MA R 1e-320\n1 1e-320 0\n").N[1] == 1
        text = written(fill(ComplexF64(1e200),1,1,1); version=1.0,parameter="Z",format="DB",R=1e-200)
        @test occursin("8000.0 0.0",text)
        @test parsefile(text).N[1] ≈ 1e200 rtol=2e-13
        for text in ("# GHz S RI R 50\n1e300 .5 0\n",
                     "# Hz S DB R 50\n1 7000 0\n",
                     "# Hz Z RI R 50\n1 1e308 0\n",
                     "# Hz Z MA R 50\n1 1e308 0\n",
                     "# Hz S DB R 50\n1 -7000 0\n",
                     "# Hz S RI R 50\n1 1e-999 0\n",
                     "# Hz S RI R 50\n2 .1 0 .2 0 .3 0 .4 0\n1 .5 .2 0 1e308\n")
            @test_throws ErrorException parsefile(text)
        end
        # Components are representable although the magnitude is above floatmax.
        z = parsefile("# Hz S DB R 50\n1 6168 45\n").N[1]
        expected = Float64(big(10)^BigFloat("308.4")/sqrt(big(2)))
        @test real(z) ≈ expected rtol=2e-13
        @test imag(z) ≈ expected rtol=2e-13
        untouched(io -> Touchstone.touchstone_write(io,[1e9],ones(ComplexF64,2,2,1);
            version=1.0,R=1e-320,noisedata=[1.0,.5,.2,0.,10.]))
    end

    let
        f=[1e9,2e9]
        physical=cat(ComplexF64[2+.3im .4-.2im; -.6+.7im 3-.8im],ComplexF64[1+.1im .2-.4im; -.3+.8im 4-.2im];dims=3)
        # Independent factors converting file values to physical units.
        scale(p,R)=p=="S" ? ones(2,2) : p=="Z" ? fill(R,2,2) : p=="Y" ? fill(1/R,2,2) : p=="H" ? [R 1;1 1/R] : [1/R 1;1 R]
        entryorder(order)=order=="12_21" ? [(1,1),(1,2),(2,1),(2,2)] : [(1,1),(2,1),(1,2),(2,2)]
        encode(z,fmt)=fmt=="RI" ? (real(z),imag(z)) : fmt=="MA" ? (abs(z),rad2deg(angle(z))) : (20log10(abs(z)),rad2deg(angle(z)))
        function rows(N,p,R,version,fmt,order)
            v=Float64[];sc=version<2 ? scale(p,R) : ones(2,2)
            for k in axes(N,3)
                push!(v,f[k]/1e9)
                for (i,j) in entryorder(order);append!(v,encode(N[i,j,k]/sc[i,j],fmt));end
            end
            v
        end
        function independent_input(v,p,R,version,fmt,order)
            header=version<2 ? "# GHz $p $fmt R $R\n" : "[Version] 2.0\n# GHz $p $fmt R $R\n[Number of Ports] 2\n[Two-Port Data Order] $order\n[Number of Frequencies] 2\n[Network Data]\n"
            header*join([join(v[k:k+8]," ") for k in 1:9:length(v)],"\n")*"\n"*(version<2 ? "" : "[End]\n")
        end
        @testset "Parameter scaling and ordering" begin
            for p in ("S","Z","Y","H","G"),R in (25.,50.,75.),version in (1.,2.),fmt in ("RI","MA","DB"), order in (version<2 ? ("21_12",) : ("12_21","21_12"))
                raw=rows(physical,p,R,version,fmt,order)
                got=Touchstone.touchstone_parse(IOBuffer(independent_input(raw,p,R,version,fmt,order)))
                @test got.f==f
                @test got.N≈physical rtol=2e-14 atol=2e-14
                io=IOBuffer();Touchstone.touchstone_write(io,f,physical;parameter=p,R,version,format=fmt,twoportdataorder=order)
                @test reduce(vcat,numericlines(String(take!(io))))≈raw rtol=2e-14 atol=2e-14
            end
            for version in (1.,2.),fmt in ("RI","MA")
                N=zeros(ComplexF64,2,2,2);order=version<2 ? "21_12" : "12_21"
                raw=rows(N,"S",50.,version,fmt,order)
                @test Touchstone.touchstone_parse(IOBuffer(independent_input(raw,"S",50.,version,fmt,order))).N==N
            end
            for R in (25.,50.,75.),version in (1.,2.)
                raw=rows(physical,"S",R,version,"RI","21_12")
                s=independent_input(raw,"S",R,version,"RI","21_12")
                noise=[1.,.7,.3,30.,15.];stored=copy(noise);stored[5]/=version<2 ? R : 1.
                if version==2
                    s=replace(s,"[Network Data]"=>"[Number of Noise Frequencies] 1\n[Network Data]","[End]"=>"[Noise Data]\n"*join(stored," ")*"\n[End]")
                else;s*=join(stored," ")*"\n" end
                @test Touchstone.touchstone_parse(IOBuffer(s)).noisedata≈noise
            end
        end
    end
end
