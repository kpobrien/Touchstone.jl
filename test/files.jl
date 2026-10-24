@testset "File operations" begin

    @testset "Saving Touchstone objects" begin
        mktempdir() do dir
            path = joinpath(dir,"network.ts")
            for version in (1.0,1.1,2.0,2.1), parameter in ("S","Z"), format in ("RI","MA","DB")
                f = [1.0e9,2.0e9]
                N = repeat(reshape(ComplexF64[1+2im 3-4im;3-4im 5+6im],2,2,1),1,1,2)
                reference = version == 1.1 ? [75.0,100.0] : [75.0,75.0]
                information = version >= 2 ? ["[Source] Example", "measured at 25 °C"] : String[]
                mixedmodeorder = version >= 2 ? [('D',[2,1]),('C',[2,1])] : Tuple{Char,Vector{Int}}[]
                matrixformat = version >= 2 ? "Lower" : "Full"
                ts = Touchstone.touchstone_file(f,N;version,parameter,format,
                    frequencyunit="GHz",R=version < 2 ? 75.0 : 40.0,reference,
                    information,mixedmodeorder,matrixformat,twoportdataorder="21_12",
                    comments=["measurement Ω"],noisedata=[1.0,.5,.25,90.0,17.0])
                ts.f[2] = 3.0e9
                ts.N[2,2,2] = 4+2im
                io = IOBuffer(); Touchstone.touchstone_write(io,ts)
                @test Touchstone.touchstone_save(path,ts) === nothing
                @test read(path,String) == String(take!(io))
                saved = Touchstone.touchstone_load(path)
                @test saved.f == ts.f
                @test saved.N ≈ ts.N rtol=2e-13
                @test (saved.version,saved.R,saved.reference) == (ts.version,ts.R,ts.reference)
                @test (saved.parameter,saved.format,saved.frequencyunit) == lowercase.((parameter,format,ts.frequencyunit))
                @test saved.twoportdataorder == ts.twoportdataorder
                @test saved.matrixformat == matrixformat
                @test saved.mixedmodeorder == mixedmodeorder
                @test saved.information == information
                @test saved.comments[1:length(ts.comments)] == ts.comments
                @test saved.noisedata ≈ ts.noisedata
                @test (saved.numberofports,saved.numberoffrequencies,saved.numberofnoisefrequencies) == (2,2,1)
                @test readdir(dir) == ["network.ts"]
            end
            # Counts are derived from the current arrays even for unchecked objects.
            ts = Touchstone.touchstone_file([1e9],ones(ComplexF64,1,1,1);format="RI")
            fields = fieldnames(typeof(ts))
            stale = Touchstone.TouchstoneFile(ntuple(length(fields)) do i
                fields[i] in (:numberofports,:numberoffrequencies,:numberofnoisefrequencies) ? 99 : getfield(ts,fields[i])
            end...)
            Touchstone.touchstone_save(path,stale)
            saved = Touchstone.touchstone_load(path)
            @test (saved.numberofports,saved.numberoffrequencies,saved.numberofnoisefrequencies) == (1,1,0)
            original = read(path,String)
            ts.N[1] = NaN
            @test_throws ErrorException Touchstone.touchstone_save(path,ts)
            @test read(path,String) == original
            @test readdir(dir) == ["network.ts"]
        end
    end

    @testset "Explicit filename extensions" begin
        mktempdir() do dir
            N = fill(0.5+0im,2,2,1)
            for version in (1.0,1.1,2.0,2.1), extension in (".ts",".TS",".s2p",".S2P",".s02p",".S0002P",".dat")
                path = joinpath(dir,"network-$version$extension")
                @test_logs Touchstone.touchstone_save(path,[1],N;version)
                @test isfile(path)
                @test !isfile(path*".s2p")
                @test !isfile(path*".ts")
                @test Touchstone.touchstone_load(path).version == version
            end
            # Replacing a custom-extension destination must not create a suffixed file.
            path = joinpath(dir,"network.dat"); write(path,"old data")
            @test_logs Touchstone.touchstone_save(path,[1],N;version=2.1)
            @test Touchstone.touchstone_load(path).N == N
            @test !isfile(path*".s2p")
            @test !isfile(path*".ts")
            @test_throws ErrorException Touchstone.touchstone_save(path,[1],N;version=2.2)
            @test Touchstone.touchstone_load(path).N == N
            for extension in (".s3p", ".s0003p", ".s0p", ".s000p", ".s"*repeat("9",100)*"p")
                mismatch = joinpath(dir,"network"*extension)
                @test_logs (:warn,"Extension $extension does not match the 2-port network.") Touchstone.touchstone_save(mismatch,[1],N;version=2.1)
                @test Touchstone.touchstone_load(mismatch).numberofports == 2
            end
        end
    end

    @testset "Default filename extensions" begin
        for (version, suffix) in ((1.0,".s"),(1.1,".s"),(2.0,".ts"),(2.1,".ts")),
            T in (Float16,Float32,Float64), numberofports in (2,3)
            mktempdir() do dir
                N = fill(0.5+0im,numberofports,numberofports,1)
                extension = suffix == ".s" ? ".s$(numberofports)p" : suffix
                arraypath = joinpath(dir,"array")
                objectpath = joinpath(dir,"object")
                @test_logs (:warn,"Adding extension of $extension") Touchstone.touchstone_save(arraypath,[1],N;version=T(version))
                ts = Touchstone.touchstone_file([1],N;version=T(version))
                @test_logs (:warn,"Adding extension of $extension") Touchstone.touchstone_save(objectpath,ts)
                @test readdir(dir) == ["array"*extension,"object"*extension]
                for path in (arraypath,objectpath)
                    saved = Touchstone.touchstone_load(path*extension)
                    @test saved.version == version
                    @test saved.numberofports == numberofports
                    @test saved.f == [1]
                    @test saved.N == N
                end
            end
        end
        mktempdir() do dir
            @test_logs @test_throws ErrorException Touchstone.touchstone_save(
                joinpath(dir,"network"),[1],fill(0.5+0im,2,2,1);version=2.2)
            @test isempty(readdir(dir))
        end
    end

    @testset "Numeric metadata on save" begin
        mktempdir() do dir
            path = joinpath(dir,"network.s2p")
            refs = [50,75]
            Touchstone.touchstone_save(path,[1],ones(ComplexF64,2,2,1);
                version=1.1,reference=@view(refs[:]),R=50,
                noisedata=Float32[1,0.5,0.25,90,2])
            ts = Touchstone.touchstone_load(path)
            @test ts.version == 1.1
            @test ts.reference == [50,75]
            @test ts.noisedata == [1,0.5,0.25,90,2]
        end
    end
    @testset "touchstone_save RI" begin

        path = tempdir()

        filename = joinpath(path,"Touchstone-"* string(UUIDs.uuid1()) * ".ts")

        frequencies = [1.0e9, 2.0e9, 10.0e9]
        N = [0.3926 - 0.1211im -0.0003 - 0.0021im; -0.0003 - 0.0021im 0.3926 - 0.1211im;;; 0.3517 - 0.3054im -0.0096 - 0.0298im; -0.0096 - 0.0298im 0.3517 - 0.3054im;;; 0.3419 + 0.3336im -0.0134 + 0.0379im; -0.0134 + 0.0379im 0.3419 + 0.3336im]
        version = 2.0
        R = 50.0
        format = "RI"
        frequencyunit = "Hz"
        comments = ["Example 4:","2-port S-parameter file, three frequency points"]

        Touchstone.touchstone_save(filename, frequencies, N;
            version = version, R = R,format = format, frequencyunit = frequencyunit,
            comments = comments)

        out=Touchstone.touchstone_load(filename)

        rm(filename)

        @test out.f == frequencies
        @test isapprox(out.N, N)
        @test out.version == version
        @test out.R == R
        @test out.format == lowercase(format)
        @test out.frequencyunit == lowercase(frequencyunit)

    end

    @testset "touchstone_save MA" begin

        path = tempdir()

        filename = joinpath(path,"Touchstone-"* string(UUIDs.uuid1()) * ".ts")

        frequencies = [1.0e9, 2.0e9, 10.0e9]
        N = [0.3926 - 0.1211im -0.0003 - 0.0021im; -0.0003 - 0.0021im 0.3926 - 0.1211im;;; 0.3517 - 0.3054im -0.0096 - 0.0298im; -0.0096 - 0.0298im 0.3517 - 0.3054im;;; 0.3419 + 0.3336im -0.0134 + 0.0379im; -0.0134 + 0.0379im 0.3419 + 0.3336im]
        version = 2.0
        R = 50.0
        format = "MA"
        frequencyunit = "Hz"
        comments = ["Example 4:","2-port S-parameter file, three frequency points"]

        Touchstone.touchstone_save(filename, frequencies, N;
            version = version, R = R,format = format, frequencyunit = frequencyunit,
            comments = comments)

        out=Touchstone.touchstone_load(filename)

        rm(filename)

        @test out.f == frequencies
        @test isapprox(out.N, N)
        @test out.version == version
        @test out.R == R
        @test out.format == lowercase(format)
        @test out.frequencyunit == lowercase(frequencyunit)

    end

    @testset "touchstone_save dB" begin

        path = tempdir()

        filename = joinpath(path,"Touchstone-"* string(UUIDs.uuid1()) * ".ts")

        frequencies = [1.0e9, 2.0e9, 10.0e9]
        N = [0.3926 - 0.1211im -0.0003 - 0.0021im; -0.0003 - 0.0021im 0.3926 - 0.1211im;;; 0.3517 - 0.3054im -0.0096 - 0.0298im; -0.0096 - 0.0298im 0.3517 - 0.3054im;;; 0.3419 + 0.3336im -0.0134 + 0.0379im; -0.0134 + 0.0379im 0.3419 + 0.3336im]
        version = 2.0
        R = 50.0
        format = "dB"
        frequencyunit = "Hz"
        comments = ["Example 4:","2-port S-parameter file, three frequency points"]

        Touchstone.touchstone_save(filename, frequencies, N;
            version = version, R = R,format = format, frequencyunit = frequencyunit,
            comments = comments)

        out=Touchstone.touchstone_load(filename)

        rm(filename)

        @test out.f == frequencies
        @test isapprox(out.N, N)
        @test out.version == version
        @test out.R == R
        @test out.format == lowercase(format)
        @test out.frequencyunit == lowercase(frequencyunit)

    end

    @testset "touchstone_save errors" begin

        path = tempdir()

        filename = joinpath(path,"Touchstone-"* string(UUIDs.uuid1()) * ".ts")

        frequencies = [1.0e9, 2.0e9, 10.0e9]
        N = [0.3926 - 0.1211im -0.0003 - 0.0021im; -0.0003 - 0.0021im 0.3926 - 0.1211im;;; 0.3517 - 0.3054im -0.0096 - 0.0298im; -0.0096 - 0.0298im 0.3517 - 0.3054im;;; 0.3419 + 0.3336im -0.0134 + 0.0379im; -0.0134 + 0.0379im 0.3419 + 0.3336im]
        version = 2.0
        R = 50.0
        format = "RI"
        frequencyunit = "Hz"
        comments = ["Example 4:","2-port S-parameter file, three frequency points"]

        # Error if network data arrays not square
        message = "Network data arrays are not square."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_save(filename, frequencies,
                N[1:end-1,:,:]; version = version, R = R,format = format,
                frequencyunit = frequencyunit,comments = comments)
        )

        # Unknown parameter family
        message = "Unknown parameter"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_save(filename, frequencies, N;
                version = version, R = R,format = format, parameter = "K",
                frequencyunit = frequencyunit, comments = comments)
        )

        # Unknown format error
        message = "Unknown format"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_save(filename, frequencies, N;
                version = version, R = R,format = "Unknown",
                frequencyunit = frequencyunit, comments = comments)
        )
        if isfile(filename)
            rm(filename)
        end

        # File extensions
        filename = joinpath(path,"Touchstone-"* string(UUIDs.uuid1()) * ".s4p")
        message = "Extension .s4p does not match the 2-port network."
        @test_warn message Touchstone.touchstone_save(filename, frequencies, N;
            version = version, R = R,format = format, frequencyunit = frequencyunit,
            comments = comments)
        rm(filename)

        # Incorrect file extension v1 file
        filename = joinpath(path,"Touchstone-"* string(UUIDs.uuid1()) * ".s4p")
        message = "Extension .s4p does not match the 2-port network."
        @test_warn message Touchstone.touchstone_save(filename, frequencies, N;
            version = 1.0, R = R,format = format, frequencyunit = frequencyunit,
            comments = comments)
        rm(filename)

        # No file extension
        filename = joinpath(path,"Touchstone-"* string(UUIDs.uuid1()))
        message = "Adding extension of .ts"
        @test_warn message Touchstone.touchstone_save(filename, frequencies, N;
            version = version, R = R,format = format, frequencyunit = frequencyunit,
            comments = comments)
        rm(filename * ".ts")

    end

    @testset "Atomic replacement and file extensions" begin
        mktempdir() do dir
            path = joinpath(dir,"existing.s1p")
            original = "# Hz S RI R 50\n1 .5 0\n"
            write(path, original)
            @test_throws ErrorException Touchstone.touchstone_save(path,[2.,1.],ones(ComplexF64,1,1,2))
            @test read(path,String) == original
            @test readdir(dir) == ["existing.s1p"]
            @test_throws ErrorException Touchstone.touchstone_save(path,[1.],ones(ComplexF64,1,1))
            @test read(path,String) == original
            @test_throws ErrorException Touchstone.atomicwrite(path) do stream
                write(stream, "partly written")
                error("injected write failure")
            end
            @test read(path,String) == original
            @test readdir(dir) == ["existing.s1p"]
            Touchstone.touchstone_save(path,[1.],fill(ComplexF64(2),1,1,1))
            @test Touchstone.touchstone_load(path).N[1] == 2
            @test readdir(dir) == ["existing.s1p"]
            # A failed rename must preserve a destination directory and clean up.
            blocked = joinpath(dir,"blocked.s1p"); mkdir(blocked)
            write(joinpath(blocked,"keep"),"keep")
            @test_throws Union{ArgumentError,Base.IOError} Touchstone.touchstone_save(blocked,[1.],ones(ComplexF64,1,1,1))
            @test read(joinpath(blocked,"keep"),String) == "keep"
            @test sort(readdir(dir)) == ["blocked.s1p","existing.s1p"]
            for (name,n) in (("x.s1p",1),("x.S10P",10),("x.s120p",120),("x.ts",2))
                Touchstone.touchstone_save(joinpath(dir,name),[1.],ones(ComplexF64,n,n,1); version=2.0)
                @test isfile(joinpath(dir,name))
                @test !isfile(joinpath(dir,name)*".s$(n)p")
            end
            @test_logs (:warn,"Adding extension of .s1p") Touchstone.touchstone_save(joinpath(dir,"noextension"),[1.],ones(ComplexF64,1,1,1))
            @test isfile(joinpath(dir,"noextension.s1p"))
        end
    end

    # Unix permission bits and unprivileged symlinks are not portable to Windows.
    if Sys.isunix()
        @testset "File permissions and links" begin
            mktempdir() do dir
                path = joinpath(dir,"network.ts")
                write(path,"old")
                chmod(path,0o640)
                Touchstone.touchstone_save(path,[1.],ones(ComplexF64,1,1,1); version=2.1)
                @test filemode(path) & 0o777 == 0o640
                @test Touchstone.touchstone_load(path).N[1] == 1

                target = joinpath(dir,"target.ts")
                write(target,"target contents")
                link = joinpath(dir,"link.ts")
                symlink(target,link)
                Touchstone.touchstone_save(link,[1.],fill(ComplexF64(2),1,1,1); version=2.1)
                @test !islink(link)
                @test read(target,String) == "target contents"
                @test Touchstone.touchstone_load(link).N[1] == 2

                other = joinpath(dir,"hardlink.ts")
                hardlink(path,other)
                original = read(other)
                Touchstone.touchstone_save(path,[1.],fill(ComplexF64(3),1,1,1); version=2.1)
                @test read(other) == original
                @test Touchstone.touchstone_load(path).N[1] == 3
                @test sort(readdir(dir)) == ["hardlink.ts","link.ts","network.ts","target.ts"]
            end
        end
    end

    @testset "Encoded record failures preserve the destination" begin
        # These adjacent physical frequencies collapse when expressed in GHz.
        f = 1.0000000000000001e9
        @test f / 1e9 == nextfloat(f) / 1e9
        # The physical noise boundary passes, but its serialized value does not.
        lastfrequency = 1.0000000000000053
        noise = [nextfloat(lastfrequency / 1e9), 0.5, 0.1, 0.0, 1.0]
        @test noise[1] * 1e9 <= lastfrequency
        @test noise[1] > lastfrequency / 1e9
        failures = [
            ([1.,2.], reshape(ComplexF64[1,Inf],1,1,2), (;format="RI")),
            ([1.,2.], reshape(ComplexF64[1,0],1,1,2), (;format="DB")),
            ([1.,2.], reshape(ComplexF64[1,1e308],1,1,2),
                (;format="RI",parameter="Y",R=1e308,version=1.0)),
            ([f,nextfloat(f)], ones(ComplexF64,1,1,2), (;frequencyunit="GHz")),
            ([lastfrequency], ones(ComplexF64,2,2,1),
                (;frequencyunit="GHz",noisedata=noise,version=1.0)),
        ]
        mktempdir() do dir
            path = joinpath(dir,"network.ts")
            for (f,N,options) in failures
                @test_throws ErrorException Touchstone.touchstone_file(f,N;options...)
                write(path,"existing")
                @test_throws ErrorException Touchstone.touchstone_save(path,f,N;options...)
                @test read(path,String) == "existing"
                @test readdir(dir) == ["network.ts"]
                rm(path)
                @test_throws ErrorException Touchstone.touchstone_save(path,f,N;options...)
                @test isempty(readdir(dir))
                untouched(io -> Touchstone.touchstone_write(io,f,N;options...))
            end
        end
    end

    @testset "Invalid input preserves the destination" begin
        bad = String(UInt8[0xff])
        mktempdir() do dir
            path = joinpath(dir, "existing.s1p")
            write(path, "existing")
            for (f, N, kw) in (([big"1e-500"], ones(ComplexF64,1,1,1), (;)),
                              ([1.0], ones(ComplexF64,1,1,1), (;comments=["valid", bad])),
                              (Float64[], zeros(ComplexF64,1,1,0), (;)),
                              ([1.0], ones(ComplexF64,2,2,1), (;version=1.0,information=["source"])),
                              ([1.0], ones(ComplexF64,2,2,1), (;version=1.1,information=["source"])))
                @test_throws ErrorException Touchstone.touchstone_save(path, f, N; kw...)
                @test read(path, String) == "existing"
                @test readdir(dir) == ["existing.s1p"]
            end
        end
    end
end
