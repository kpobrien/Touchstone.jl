@testset "Writing" begin

    @testset "Unsupported output versions" begin
        N = fill(0.5+0im,1,1,1)
        for version in (0.0,1.2,2.2,3.0,Inf,NaN,nextfloat(2.1))
            @test_throws ErrorException Touchstone.touchstone_file([1],N;version)
            untouched(io -> Touchstone.touchstone_write(io,[1],N;version))
            @test_throws ErrorException Touchstone.arraytonetworkdata([1],N,1,1,
                "Full","12_21","S","Hz","RI",50.0,version)
            @test_throws ErrorException Touchstone.networkdatatoarray([1.,.5,0.],1,1,
                "Full","12_21","S","Hz","RI",50.0,version)
        end
    end

    @testset "Version selector precision" begin
        N = fill(0.5+0im,2,2,1)
        for version in (1.0,1.1,2.0,2.1), T in (Float16,Float32,Float64)
            selector = T(version)
            ts = Touchstone.touchstone_file([1],N;version=selector,format="RI")
            @test ts.version === version
            @test parsefile(written([1],N;version=selector,format="RI")).version === version
            for adjacent in (prevfloat(selector),nextfloat(selector))
                @test_throws ErrorException Touchstone.touchstone_file([1],N;version=adjacent)
                untouched(io -> Touchstone.touchstone_write(io,[1],N;version=adjacent))
            end
        end
        for version in (11//10,21//10,big"1.1",big"2.1")
            @test Touchstone.touchstone_file([1],N;version).version === Float64(version)
        end
    end

    @testset "Numeric keyword conversion" begin
        N = fill(0.5+0im,2,2,1)
        for version in (1,2), R in (50,Float32(50),big"50"),
                refs in ([50,50],Float32[50,50],@view([50.0,50.0][1:2]))
            ts = Touchstone.touchstone_file([1],N; version,R,reference=refs,
                frequencyunit="Hz",noisedata=Float32[1,0.5,0.25,90,2])
            @test ts.R === 50.0
            @test ts.version === Float64(version)
            @test ts.reference isa Vector{Float64}
            @test ts.noisedata == [1,0.5,0.25,90,2]
            @test parsefile(written(ts.f,ts.N;version,R,reference=refs,
                frequencyunit="Hz",noisedata=ts.noisedata)).noisedata == ts.noisedata
        end
        refs,noise = [50.0,75.0],Float64[]
        ts = Touchstone.touchstone_file([1],N;version=1.1,reference=refs,noisedata=noise)
        @test ts.reference === refs
        @test ts.noisedata === noise
        for kwargs in ((R=big"1e-999",), (R=big"1e999",), (R=NaN,),
                (reference=[big"1e-999",big"50"],), (reference=[big"1e999",big"50"],),
                (reference=[0,50],), (reference=[NaN,50],),
                (noisedata=[big"1",big"0.5",big"0.25",big"90",big"1e-999"],),
                (noisedata=[1,0.5,0.25,90,Inf],))
            untouched(io -> Touchstone.touchstone_write(io,[1],N;
                frequencyunit="Hz",kwargs...))
        end
        @test_throws TypeError Touchstone.touchstone_file([1],N;reference=[50+im,50+im])
    end
    @testset "touchstone_file errors" begin

        message = "The size of the last axis of network data N must equal the number of frequencies"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6,3.0e6], [0.874020294860635 - 0.18794819544685323im;;;])
        )

        message = "Network data matrix must be square"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},1,2,1))
        )

        message = "Version must be 1.0, 1.1, 2.0, or 2.1"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},1,1,1),version=1.5)
        )

        message = "Unknown frequency unit"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},1,1,1),frequencyunit="THz")
        )

        message = "Unknown format"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},1,1,1),format="DA")
        )

        message = "Unknown parameter"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},1,1,1),parameter="K")
        )

        message = "Number of per port impedances must equal number of ports"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},1,1,1),reference=[50.0,50.0])
        )

        message = "Version 1.0 requires equal port impedances; use version 1.1 or version 2."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},2,2,1),reference=[50.0,40.0],version=1.0)
        )

        message = "For Touchstone files with version less than 2.0 only the Full matrix format is required."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},2,2,1),version=1.0,matrixformat="Lower")
        )

        message = "For Touchstone version 2 the valid formats are Full, Lower, or Upper."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},2,2,1),version=2.0,matrixformat="Triangular")
        )

        message = "Unknown two-port data order."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},2,2,1),version=2.0,twoportdataorder="23_32")
        )

        message = "Invalid number of elements in noise data."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_file([2.0e6], zeros(Complex{Float64},2,2,1),version=2.0,noisedata=[1.0,2.0,3.0,4.0,5.0,6.0])
        )

    end

    @testset "Empty network data" begin
        f = Float64[]
        N = zeros(ComplexF64,1,1,0)
        for version in (1.0,1.1,2.0,2.1)
            @test_throws ErrorException("No network data.") Touchstone.touchstone_file(f,N;version)
            untouched(io -> Touchstone.touchstone_write(io,f,N;version))
        end
    end

    @testset "touchstone_write" begin

        fixtures = networkexamples()
        parsedexamples = Any[
            fixtures.legacy_oneport_s_ma,
            fixtures.legacy_oneport_s_db,
            fixtures.legacy_oneport_z,
            fixtures.legacy_twoport_h,
            fixtures.legacy_twoport_s,
            fixtures.legacy_fourport_s,
            fixtures.legacy_noise,
            fixtures.v2_reference,
            fixtures.v2_full,
            fixtures.v2_lower,
            fixtures.v2_oneport_z,
            fixtures.v1_oneport_s,
            fixtures.v1_oneport_z,
            fixtures.v2_oneport_z_reference,
            fixtures.v1_twoport_h,
            fixtures.v2_twoport_h,
            fixtures.v1_twoport_s,
            fixtures.v1_fourport_s,
            fixtures.v2_mixedmode,
            fixtures.v2_noise,
            fixtures.v1_noise,
            fixtures.v2_noise_comments,
            fixtures.v2_information,
        ]

        writtenexamples = String[
            "!Example 1:\n!1-port S-parameter file, single frequency point\n!freq magS11 angS11\n# mhz s ma R 50.0\n2.0 0.894 -12.136\n",
            "!Example 1a:\n!1-port S-parameter file, single frequency point\n!freq magS11 angS11\n# mhz s db R 50.0\n! freq logmags11 angs11 \n2.0 -0.97 -12.136\n",
            "!Example 2:\n!1-port Z-parameter file, multiple frequency points\n!freq magZ11 angZ11\n# mhz z ma R 75.0\n100.0 0.99 -4.0\n200.0 0.8 -22.0\n300.0 0.707 -45.0\n400.0 0.4 -62.0\n500.0 0.01 -89.0\n",
            "!Example 3:\n!2-port H-parameter file, single frequency point\n! freq magH11 angH11 magH21 angH21 magH12 angH12 magH22 angH22\n# khz h ma R 1.0\n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -1.0\n",
            "!Example 4:\n!2-port S-parameter file, three frequency points\n!freq RelS11 ImS11 ReS21 ImS21 ReS12 ImS12 ReS22 ImS22\n# ghz s ri R 50.0\n! freq Res11 Ims11 Res21 Ims21 Res12 Ims12 Res22 Ims22 \n1.0 0.3926 -0.1211 -0.0003 -0.0021 -0.0003 -0.0021 0.3926 -0.1211\n2.0 0.3517 -0.3054 -0.0096 -0.0298 -0.0096 -0.0298 0.3517 -0.3054\n10.0 0.3419 0.3336 -0.0134 0.0379 -0.0134 0.0379 0.3419 0.3336\n",
            "!Example 5:\n! 4-port S-parameter data, taken at three frequency points\n!row 1\n!row 2\n!row 3\n!row 4\n!row 1\n!row 2\n!row 3\n!row 4\n!row 1\n!row 2\n!row 3\n!row 4\n# ghz s ma R 50.0\n! freq mags11 angs11 mags12 angs12 mags13 angs13 mags14 angs14 mags21 angs21 mags22 angs22 mags23 angs23 mags24 angs24 mags31 angs31 mags32 angs32 mags33 angs33 mags34 angs34 mags41 angs41 mags42 angs42 mags43 angs43 mags44 angs44 \n5.0 0.6 161.24 0.4 -42.2 0.42 -66.58 0.53 -79.34\n 0.4 -42.2 0.6 161.2 0.53 -79.34 0.42 -66.58\n 0.42 -66.58 0.53 -79.34 0.6 161.24 0.4 -42.2\n 0.53 -79.34 0.42 -66.58 0.4 -42.2 0.6 161.24\n6.0 0.57 150.37 0.4 -44.34 0.41 -81.24 0.57 -95.77\n 0.4 -44.34 0.57 150.37 0.57 -95.77 0.41 -81.24\n 0.41 -81.24 0.57 -95.77 0.57 150.37 0.4 -44.34\n 0.57 -95.77 0.41 -81.24 0.4 -44.34 0.57 150.37\n7.0 0.5 136.69 0.45 -46.41 0.37 -99.09 0.62 -114.19\n 0.45 -46.41 0.5 136.69 0.62 -114.19 0.37 -99.09\n 0.37 -99.09 0.62 -114.19 0.5 136.69 0.45 -46.41\n 0.62 -114.19 0.37 -99.09 0.45 -46.41 0.5 136.69\n",
            "!Example 8:\n!2-port network, S-parameter and noise data\n! NOISE PARAMETERS\n# ghz s ma R 50.0\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n4.0 0.7 0.64 69.0 0.38\n18.0 2.7 0.46 -33.0 0.4\n",
            "!Example 4 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by [Reference]\n! Data cannot be represented using 1.0 syntax\n! Note that the [Reference] keyword arguments appear on a separate line\n!row 1\n!row 2\n!row 3\n!row 4\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 4\n[Number of Frequencies] 1\n[Reference] 50.0 75.0 0.01 0.01\n[Network Data]\n! freq mags11 angs11 mags12 angs12 mags13 angs13 mags14 angs14 mags21 angs21 mags22 angs22 mags23 angs23 mags24 angs24 mags31 angs31 mags32 angs32 mags33 angs33 mags34 angs34 mags41 angs41 mags42 angs42 mags43 angs43 mags44 angs44 \n5.0 0.6 161.24 0.4 -42.2 0.42 -66.58 0.53 -79.34\n 0.4 -42.2 0.6 161.2 0.53 -79.34 0.42 -66.58\n 0.42 -66.58 0.53 -79.34 0.6 161.24 0.4 -42.2\n 0.53 -79.34 0.42 -66.58 0.4 -42.2 0.6 161.24\n[End]",
            "!Example 5 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by the [Reference] keyword arguments\n! Data cannot be represented using 1.0 syntax\n!row 1\n!row 2\n!row 3\n!row 4\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 4\n[Number of Frequencies] 1\n[Reference] 50.0 75.0 0.01 0.01\n[Network Data]\n! freq mags11 angs11 mags12 angs12 mags13 angs13 mags14 angs14 mags21 angs21 mags22 angs22 mags23 angs23 mags24 angs24 mags31 angs31 mags32 angs32 mags33 angs33 mags34 angs34 mags41 angs41 mags42 angs42 mags43 angs43 mags44 angs44 \n5.0 0.6 161.24 0.4 -42.2 0.42 -66.58 0.53 -79.34\n 0.4 -42.2 0.6 161.2 0.53 -79.34 0.42 -66.58\n 0.42 -66.58 0.53 -79.34 0.6 161.24 0.4 -42.2\n 0.53 -79.34 0.42 -66.58 0.4 -42.2 0.6 161.24\n[End]",
            "!Example 6 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by the [Reference] keyword arguments\n! Note that [Reference] arguments are split across two lines\n! Data cannot be represented using 1.0 syntax\n!row 1\n!row 2\n!row 3\n!row 4\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 4\n[Number of Frequencies] 1\n[Reference] 50.0 75.0 0.01 0.01\n[Matrix Format] Lower\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags22 angs22 mags31 angs31 mags32 angs32 mags33 angs33 mags41 angs41 mags42 angs42 mags43 angs43 mags44 angs44 \n5.0 0.6 161.24\n 0.4 -42.2 0.6 161.2\n 0.42 -66.58 0.53 -79.34 0.6 161.24\n 0.53 -79.34 0.42 -66.58 0.4 -42.2 0.6 161.24\n[End]",
            "!Example 7 (Version 2.0):\n!1-port Z-parameter file, multiple frequency points\n!freq magZ11 angZ11\n[Version] 2.0\n# mhz z ma R 50.0\n[Number of Ports] 1\n[Number of Frequencies] 5\n[Reference] 20.0\n[Network Data]\n100.0 74.25 -4.0\n200.0 60.0 -22.0\n300.0 53.025 -45.0\n400.0 30.0 -62.0\n500.0 0.75 -89.0\n[End]",
            "!Example 8 (Version 1.0):\n!1-port S-parameter file, single frequency point\n!freq magS11 angS11\n# mhz s ma R 50.0\n2.0 0.894 -12.136\n",
            "!Example 9 (Version 1.0):\n!1-port Z-parameter file, multiple frequency points\n!freq magZ11 angZ11\n# mhz z ma R 75.0\n100.0 0.99 -4.0\n200.0 0.8 -22.0\n300.0 0.707 -45.0\n400.0 0.4 -62.0\n500.0 0.01 -89.0\n",
            "!Example 10 (Version 2.0):\n!1-port Z-parameter file, multiple frequency points\n!freq magZ11 angZ11\n[Version] 2.0\n# mhz z ma R 50.0\n[Number of Ports] 1\n[Number of Frequencies] 5\n[Reference] 20.0\n[Network Data]\n100.0 74.25 -4.0\n200.0 60.0 -22.0\n300.0 53.025 -45.0\n400.0 30.0 -62.0\n500.0 0.75 -89.0\n[End]",
            "!Example 11 (Version 1.0):\n!2-port H-parameter file, single frequency point\n! freq magH11 angH11 magH21 angH21 magH12 angH12 magH22 angH22\n# khz h ma R 1.0\n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n",
            "!Example 12 (Version 2.0):\n!2-port H-parameter file, single frequency point\n! freq magH11 angH11 magH21 angH21 magH12 angH12 magH22 angH22\n[Version] 2.0\n# khz h ma R 1.0\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 1\n[Reference] 1.0 1.0\n[Network Data]\n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n[End]",
            "!Example 13 (Version 1.0):\n!2-port S-parameter file, three frequency points\n!freq ReS11 ImS11 ReS21 ImS21 ReS12 ImS12 ReS22 ImS22\n# ghz s ri R 50.0\n1.0 0.3926 -0.1211 -0.0003 -0.0021 -0.0003 -0.0021 0.3926 -0.1211\n2.0 0.3517 -0.3054 -0.0096 -0.0298 -0.0096 -0.0298 0.3517 -0.3054\n10.0 0.3419 0.3336 -0.0134 0.0379 -0.0134 0.0379 0.3419 0.3336\n",
            "!Example 14 (Version 1.0):\n! 4-port S-parameter data, taken at three frequency points\n! note that data points need not be aligned\n!row 1\n!row 2\n!row 3\n!row 4\n!row 1\n!row 2\n!row 3\n!row 4\n!row 1\n!row 2\n!row 3\n!row 4\n# ghz s ma R 50.0\n! freq mags11 angs11 mags12 angs12 mags13 angs13 mags14 angs14 mags21 angs21 mags22 angs22 mags23 angs23 mags24 angs24 mags31 angs31 mags32 angs32 mags33 angs33 mags34 angs34 mags41 angs41 mags42 angs42 mags43 angs43 mags44 angs44 \n5.0 0.6 161.24 0.4 -42.2 0.42 -66.58 0.53 -79.34\n 0.4 -42.2 0.6 161.2 0.53 -79.34 0.42 -66.58\n 0.42 -66.58 0.53 -79.34 0.6 161.24 0.4 -42.2\n 0.53 -79.34 0.42 -66.58 0.4 -42.2 0.6 161.24\n6.0 0.57 150.37 0.4 -44.34 0.41 -81.24 0.57 -95.77\n 0.4 -44.34 0.57 150.37 0.57 -95.77 0.41 -81.24\n 0.41 -81.24 0.57 -95.77 0.57 150.37 0.4 -44.34\n 0.57 -95.77 0.41 -81.24 0.4 -44.34 0.57 150.37\n7.0 0.5 136.69 0.45 -46.41 0.37 -99.09 0.62 -114.19\n 0.45 -46.41 0.5 136.69 0.62 -114.19 0.37 -99.09\n 0.37 -99.09 0.62 -114.19 0.5 136.69 0.45 -46.41\n 0.62 -114.19 0.37 -99.09 0.45 -46.41 0.5 136.69\n",
            "!Example 16 (Version 2.0):\n!6-port component shown; note that all five ports are used in some\n!relationship\n[Version] 2.0\n# mhz y ri R 50.0\n[Number of Ports] 6\n[Number of Frequencies] 1\n[Reference] 50.0 75.0 75.0 50.0 0.01 0.01\n[Mixed-Mode Order] D2,3 D6,5 C2,3 C6,5 S4 S1\n[Network Data]\n! freq Rey11 Imy11 Rey12 Imy12 Rey13 Imy13 Rey14 Imy14 Rey15 Imy15 Rey16 Imy16 Rey21 Imy21 Rey22 Imy22 Rey23 Imy23 Rey24 Imy24 Rey25 Imy25 Rey26 Imy26 Rey31 Imy31 Rey32 Imy32 Rey33 Imy33 Rey34 Imy34 Rey35 Imy35 Rey36 Imy36 Rey41 Imy41 Rey42 Imy42 Rey43 Imy43 Rey44 Imy44 Rey45 Imy45 Rey46 Imy46 Rey51 Imy51 Rey52 Imy52 Rey53 Imy53 Rey54 Imy54 Rey55 Imy55 Rey56 Imy56 Rey61 Imy61 Rey62 Imy62 Rey63 Imy63 Rey64 Imy64 Rey65 Imy65 Rey66 Imy66 \n5.0 8.0 9.0 2.0 -1.0 3.0 -2.0 1.0 3.0\n 1.0 0.1 0.2 -0.2\n 2.0 -1.0 7.0 7.0 1.8 -2.0 -1.0 -1.0\n -0.5 0.5 0.2 -0.1\n 3.0 -2.0 1.8 -2.0 5.8 6.0 1.2 0.8\n 0.9 0.7 0.3 -0.5\n 1.0 3.0 -1.0 -1.0 1.2 0.8 6.3 8.0\n 2.0 -0.5 1.5 0.6\n 1.0 0.1 -0.5 0.5 0.9 0.7 2.0 -0.5\n 4.7 -6.0 -1.0 2.0\n 0.2 -0.2 0.2 -0.1 0.3 -0.5 1.5 0.6\n -1.0 2.0 5.5 -7.0\n[End]",
            "!Example 17 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50.0 25.0\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n[Noise Data]\n4.0 0.7 0.64 69.0 19.0\n18.0 2.7 0.46 -33.0 20.0\n[End]",
            "!Example 18 (Version 1.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n! NETWORK PARAMETERS\n! NOISE PARAMETERS\n# ghz s ma R 50.0\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n4.0 0.7 0.64 69.0 0.38\n18.0 2.7 0.46 -33.0 0.4\n",
            "!Example 19 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n! NETWORK PARAMETERS\n! NOISE PARAMETERS\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50.0 25.0\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n[Noise Data]\n4.0 0.7 0.64 69.0 19.0\n18.0 2.7 0.46 -33.0 20.0\n[End]",
            "!Example 19 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n! NETWORK PARAMETERS\n! NOISE PARAMETERS\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 2\n[Begin Information]\nThis is information.\n[End Information]\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50.0 25.0\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n[Noise Data]\n4.0 0.7 0.64 69.0 19.0\n18.0 2.7 0.46 -33.0 20.0\n[End]",
        ]

        for i in 1:length(parsedexamples)
            io = IOBuffer();
            Touchstone.touchstone_write(io, parsedexamples[i]);
            # Polar conversion can change the final digits of numeric text.
            written = String(take!(io))
            actual, expected = split(written, '\n'), split(writtenexamples[i], '\n')
            @test length(actual) == length(expected)
            for (a, e) in zip(actual, expected)
                if !isempty(strip(e)) && first(lstrip(e)) in ['0':'9'; '+'; '-'; '.']
                    @test parse.(Float64, split(a)) ≈ parse.(Float64, split(e)) rtol=1e-13 atol=1e-14
                else
                    @test a == e
                end
            end
            @test Touchstone.touchstone_parse(IOBuffer(written)).N ≈ parsedexamples[i].N
        end
    end

    @testset "touchstone_write errors" begin

        # Readers and writers require positive reference impedances and finite,
        # nonnegative, strictly increasing frequencies.
        f = [1.0e9, 2.0e9]
        N = fill(0.1 + 0im, 1, 1, 2)
        noise = [1.0e9, 0.7, 0.64, 69.0, 0.38, 1.0e9, 2.7, 0.46, -33.0, 0.40]
        for (args, kwargs, message) in [
                ((f, N), (version = 1.0, R = 0.0), "R must be a positive number of ohms: 0.0"),
                ((f, N), (version = 1.0, R = -50.0), "R must be a positive number of ohms: -50.0"),
                ((f, N), (version = 2.0, reference = [0.0]), "The reference impedances must be positive numbers of ohms: [0.0]"),
                ((f, N), (version = 2.0, reference = [-50.0]), "The reference impedances must be positive numbers of ohms: [-50.0]"),
                ((f, N), (version = 1.0, reference = [75.0]), "A version 1.0 file states one reference impedance, R = 50.0, which the reference impedances [75.0] differ from; write a version 1.1 or version 2 file."),
                (([1.0e9, 1.0e9], N), (version = 1.0,), "The network data frequencies do not increase: 1.0e9 follows 1.0e9."),
                (([2.0e9, 1.0e9], N), (version = 2.0,), "The network data frequencies do not increase: 1.0e9 follows 2.0e9."),
                (([1.0e9, NaN], N), (version = 2.0,), "The network data frequency NaN is not a finite, nonnegative number."),
                (([-1.0e9, 1.0e9], N), (version = 2.0,), "The network data frequency -1.0e9 is not a finite, nonnegative number."),
                ((f, fill(0.1 + 0im, 2, 2, 2)), (version = 2.0, noisedata = noise), "The noise data frequencies do not increase: 1.0e9 follows 1.0e9.")]
            @test_throws ErrorException(message) Touchstone.touchstone_write(IOBuffer(), args...; kwargs...)
        end
        # A version 1 file of three ports with one impedance unlike the others
        @test_throws ErrorException Touchstone.touchstone_write(IOBuffer(), f, fill(0.1 + 0im, 3, 3, 2); version = 1.0, reference = [50.0, 50.0, 75.0])

        message = "Number of mixed mode order descriptors must match the number of ports."
        io = IOBuffer();
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_write(io,[2.0e6], zeros(Complex{Float64},1,1,1),mixedmodeorder = [('D',[1,2]),('C',[1,2])])
        )

        message = "Mixed-mode data require Touchstone version 2."
        io = IOBuffer();
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_write(io,[2.0e6], zeros(Complex{Float64},2,2,1),mixedmodeorder = [('D',[1,2]),('C',[1,2])],version=1.0)
        )


        message = "Unknown parameter"
        io = IOBuffer();
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_write(io,Touchstone.TouchstoneFile([2.0e6], [0.874020294860635 - 0.18794819544685323im;;;], "mhz", "k", "ma", 50.0, 1.0, 1, "12_21", 1, 0, [50.0], String[], "Full", Tuple{Char, Vector{Int64}}[], ["Example 1:", "1-port S-parameter file, single frequency point", "freq magS11 angS11"], Float64[]))
        )

        # Unknown format v1
        message = "Unknown format"
        io = IOBuffer();
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_write(io,Touchstone.TouchstoneFile([2.0e6], [0.874020294860635 - 0.18794819544685323im;;;], "mhz", "s", "da", 50.0, 1.0, 1, "12_21", 1, 0, [50.0], String[], "Full", Tuple{Char, Vector{Int64}}[], ["Example 1:", "1-port S-parameter file, single frequency point", "freq magS11 angS11"], Float64[]))
        )

        # Unknown format v2
        message = "Unknown format"
        io = IOBuffer();
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_write(io,Touchstone.TouchstoneFile([2.0e6], [0.874020294860635 - 0.18794819544685323im;;;], "mhz", "s", "da", 50.0, 2.0, 1, "12_21", 1, 0, [50.0], String[], "Full", Tuple{Char, Vector{Int64}}[], ["Example 1:", "1-port S-parameter file, single frequency point", "freq magS11 angS11"], Float64[]))
        )

    end

    @testset "version 1 noise data written" begin
        # Version 1 noise records follow network records without a keyword.
        # The first noise frequency cannot exceed the last network frequency.
        N = [0.1 + 0.2im 0.3 - 0.1im; 0.5 + 0.0im 0.2 + 0.1im;;; 0.2 - 0.1im 0.1 + 0.1im; 0.4 + 0.3im 0.1 - 0.2im]
        noise = [1.0, 0.7, 0.64, 69.0, 0.38, 2.0, 2.7, 0.46, -33.0, 0.40]
        io = IOBuffer()
        Touchstone.touchstone_write(io, [1.0e9, 2.0e9], N; version = 1.0, frequencyunit = "GHz", format = "RI", noisedata = noise)
        text = String(take!(io))
        @test !occursin("[Noise Data]", text)
        ts = Touchstone.touchstone_parse(IOBuffer(text))
        @test (ts.N ≈ N, ts.noisedata, ts.numberofnoisefrequencies) == (true, noise, 2)
        @test_throws ErrorException("The first noise frequency, 3.0 GHz, is above the highest network frequency, 2.0e9 Hz.") Touchstone.touchstone_write(IOBuffer(), [1.0e9, 2.0e9], N; version = 1.0, frequencyunit = "GHz", noisedata = [3.0, 0.7, 0.64, 69.0, 0.38])
    end

    @testset "Noise record layout and normalization" begin
        f, N = [1e9,2e9], ones(ComplexF64,2,2,2)
        noise = [0.0,0.75,0.25,-0.0,18.75,1.0,1.25,0.5,90.0,37.5]
        original = copy(noise)
        for version in (1.0,1.1,2.0,2.1), format in ("RI","MA","DB")
            reference = version == 1.1 ? [75.0,100.0] : [75.0,75.0]
            # Version 1.1 uses the first port reference even when R differs.
            R = version == 1.1 ? 50.0 : 75.0
            text = written(f,N;version,format,R,reference,frequencyunit="GHz",
                noisedata=noise)
            expected = version < 2 ?
                "0.0 0.75 0.25 -0.0 0.25\n1.0 1.25 0.5 90.0 0.5\n" :
                "[Noise Data]\n0.0 0.75 0.25 -0.0 18.75\n1.0 1.25 0.5 90.0 37.5\n[End]"
            @test endswith(text,expected)
            @test occursin("[Noise Data]",text) == (version >= 2)
            parsed = parsefile(text)
            @test parsed.numberofnoisefrequencies == 2
            @test isequal(parsed.noisedata,noise)
            @test isequal(noise,original)
        end
    end

    @testset "Noise records across the Float64 range" begin
        values = [0.0,-0.0,nextfloat(0.0),-nextfloat(0.0),
            prevfloat(floatmin(Float64)),floatmin(Float64),
            floatmax(Float64),-floatmax(Float64),1.0,-1.0]
        noise = Float64[]
        for (i,value) in enumerate(values)
            append!(noise,(Float64(i),value,value,value,value))
        end
        # Use Base formatting as an independent text oracle for all columns.
        expected = join((join(noise[i:i+4],' ') * "\n" for i in 1:5:length(noise)))
        for version in (1.0,1.1,2.0,2.1)
            text = written([Float64(length(values))],ones(ComplexF64,2,2,1);
                version,R=1.0,frequencyunit="Hz",format="RI",noisedata=noise)
            @test endswith(text,expected * (version < 2 ? "" : "[End]"))
            @test isequal(parsefile(text).noisedata,noise)
        end
    end

    @testset "comments written as read" begin
        # Latin-1 and UTF-8 output must preserve the decoded comment text.
        data = "# GHz S MA R 50\n1.0 0.5 10\n2.0 0.4 20\n"
        for (comment, bytes) in [("! measured at 25 \xb0C\n", b"! measured at 25 \xb0C\n"),
                ("! 50 \u03a9\n", b"! 50 \xce\xa9\n"), ("! \u00c3\u00a9\n", b"! \xc3\x83\xc2\xa9\n")]
            ts = Touchstone.touchstone_parse(IOBuffer(comment * data))
            io = IOBuffer()
            Touchstone.touchstone_write(io, ts)
            written = take!(io)
            @test occursin(String(copy(bytes)), String(copy(written)))
            @test Touchstone.touchstone_parse(IOBuffer(written)).comments[1] == ts.comments[1]
        end
    end

    @testset "Column labels and existing comments" begin
        f, N = [1.0], fill(0.5+0.25im,1,1,1)
        for version in (1.0,1.1,2.0,2.1), format in ("RI","MA","DB")
            labels = format == "RI" ? "ReS11 ImS11" :
                format == "MA" ? "magS11 angS11" : "logmagS11 angS11"
            comment = "\tFREQ $(uppercase(labels))  "
            comments = ["measurement Ω", "measurement Ω", comment, comment]
            text = written(f,N;version,format,frequencyunit="Hz",comments)
            @test parsefile(text).comments == comments
            @test comments == ["measurement Ω", "measurement Ω", comment, comment]
            # Without a label, add one once; later writes retain its parsed text.
            text = written(f,N;version,format,frequencyunit="Hz",comments=["measurement Ω"])
            expected = parsefile(text).comments
            @test length(expected) == 2
            for _ in 1:3
                ts = parsefile(text)
                io = IOBuffer(); Touchstone.touchstone_write(io,ts)
                text = String(take!(io))
                saved = parsefile(text)
                @test saved.comments == expected
                @test saved.N ≈ N
            end
        end
        # A label for another representation or matrix ordering is not equivalent.
        comments = ["freq magS11 angS11"]
        @test length(parsefile(written(f,N;format="RI",comments)).comments) == 2
        N = ones(ComplexF64,2,2,1)
        comments = ["freq ReS11 ImS11 ReS21 ImS21 ReS12 ImS12 ReS22 ImS22"]
        for (matrixformat,order,count) in (("Full","21_12",1),
                ("Full","12_21",2),("Lower","21_12",2))
            text = written(f,N;format="RI",matrixformat,twoportdataorder=order,comments)
            @test length(parsefile(text).comments) == count
        end
    end

    @testset "Multi-digit port labels" begin
        ports = 12
        N = fill(0.5+0.25im,ports,ports,1)
        for version in (1.1,2.1), parameter in ("S","Z"), format in ("RI","MA","DB"),
                matrixformat in (version < 2 ? ("Full",) : ("Full","Upper","Lower"))
            labels = format == "RI" ? ("Re","Im") :
                format == "MA" ? ("mag","ang") : ("logmag","ang")
            expected = " freq "
            for i in 1:ports, j in 1:ports
                matrixformat == "Upper" && i > j && continue
                matrixformat == "Lower" && i < j && continue
                for label in labels
                    expected *= "$label$parameter$i$j "
                end
            end
            options = (;version,parameter,format,matrixformat,frequencyunit="Hz")
            text = written([1.0],N;options...)
            @test parsefile(text).comments == [expected]
            @test parsefile(text).N ≈ N
            # A retained label suppresses another copy, including large labels.
            text = written([1.0],N;options...,comments=[expected])
            @test parsefile(text).comments == [expected]
        end
    end

    @testset "matrixindices" begin
        layouts = (
            (3,"Full","12_21",[(1,1),(1,2),(1,3),(2,1),(2,2),(2,3),(3,1),(3,2),(3,3)],
                "11 12 13 \n21 22 23 \n31 32 33 \n"),
            (3,"Upper","12_21",[(1,1),(1,2),(1,3),(2,2),(2,3),(3,3)],
                "11 12 13 \n   22 23 \n      33 \n         "),
            (3,"Lower","12_21",[(1,1),(2,1),(2,2),(3,1),(3,2),(3,3)],
                "11 \n21 22 \n31 32 33 \n"),
            (2,"Full","21_12",[(1,1),(2,1),(1,2),(2,2)],
                "11 12 \n21 22 \n"),
            (2,"Upper","21_12",[(1,1),(2,1),(2,2)],
                "11 12 \n   22 \n      "),
            (2,"Lower","21_12",[(1,1),(1,2),(2,2)],
                "11 \n21 22 \n"),
        )
        for (nports,format,order,entries,layout) in layouts
            expected = CartesianIndex.(entries)
            mktemp() do path, io
                indices = redirect_stdout(io) do
                    Touchstone.matrixindices(nports,format,order; printflag=true)
                end
                @test indices == expected
                seekstart(io)
                @test read(io,String) == layout
            end
            if order == "12_21"
                @test Touchstone.matrixindices(nports,lowercase(format)) == expected
            end
        end
        @test_throws(
            ErrorException("Unknown two port data order string."),
            Touchstone.matrixindices(2,"Full","21_31")
        )
        @test_throws(
            ErrorException("Unknown matrix format."),
            Touchstone.matrixindices(2,"Fake","21_12")
        )
        @test_throws(
            ErrorException("Two port data order = 21_12 is only allowed if the number of ports is two."),
            Touchstone.matrixindices(4,"Full","21_12")
        )
    end

    @testset "Output validation" begin
        for version in (1.0, 2.0), fmt in ("RI", "MA", "DB")
            untouched(io -> Touchstone.touchstone_write(io, [1e9], fill(ComplexF64(Inf),1,1,1); version, format=fmt))
        end
        for version in (1.0, 2.0)
            untouched(io -> Touchstone.touchstone_write(io, [1e9], zeros(ComplexF64,1,1,1); version, format="DB"))
        end
        for field in 2:5, bad in (Inf, NaN)
            noise = [1.0,0.5,0.2,0.0,10.0]; noise[field] = bad
            untouched(io -> Touchstone.touchstone_write(io, [1e9], ones(ComplexF64,2,2,1); noisedata=noise))
        end
        for (f,N,kw) in [
            ([2.0,1.0], ones(ComplexF64,1,1,2), (;)),
            ([1.0], ones(ComplexF64,2,2,1), (;mixedmodeorder=[('D',[1,2])])),
            ([1.0], ones(ComplexF64,2,2,1), (;version=1.0,mixedmodeorder=[('D',[1,2]),('C',[1,2])])),
            ([nextfloat(0.0),2nextfloat(0.0)], ones(ComplexF64,1,1,2), (;frequencyunit="GHz")),
            ([1.0], ones(ComplexF64,1,1,1), (;comments=["a\nb"])),
            ([1.0], ones(ComplexF64,1,1,1), (;information=["[End Information]"]))]
            untouched(io -> Touchstone.touchstone_write(io, f, N; kw...))
        end
    end

    @testset "Refused values are named" begin
        # The error names the entry and the frequency of the value refused.
        message(f) = try f(); "" catch e; sprint(showerror, e) end
        f = [1e9, 2e9]
        thru = repeat(ComplexF64[0 1; 1 0], 1, 1, 2)
        @test occursin("S parameter (1, 1) at 1.0e9 Hz is zero",
            message(() -> written(f, thru; format="DB")))
        N = copy(thru); N[1,2,2] = NaN
        @test occursin("S parameter (1, 2) at 2.0e9 Hz is not finite",
            message(() -> written(f, N; format="RI")))
        noise = [1.0, 0.7, 0.64, 69.0, 19.0, 2.0, 2.7, Inf, -33.0, 20.0]
        @test occursin("value Inf of the record at 2.0 GHz",
            message(() -> written(f, thru; noisedata=noise)))
        @test occursin("1.0e300 ghz overflows in hz",
            lowercase(message(() -> parsefile("# GHz S RI R 50\n1e300 1 0\n"))))
    end

    @testset "Physical values are authoritative" begin
        ts = Touchstone.touchstone_file([1e9],ones(ComplexF64,1,1,1); format="RI")
        @test !hasproperty(ts, :networkdata)
        ts.N[1] = 2+3im; ts.f[1] = 2e9
        io = IOBuffer(); Touchstone.touchstone_write(io,ts)
        result = parsefile(String(take!(io)))
        @test !hasproperty(result, :networkdata)
        @test result.N[1] == 2+3im
        @test result.f == [2e9]
        ts.N[1] = NaN
        untouched(io -> Touchstone.touchstone_write(io,ts))
        # Triangular formats hold transpose-symmetric matrices: a Hermitian
        # matrix that is not symmetric is refused like an asymmetric one.
        asymmetric = reshape(ComplexF64[1 2;3 4],2,2,1)
        hermitian = reshape(ComplexF64[1 2+3im;2-3im 4],2,2,1)
        for matrixformat in ("Upper","Lower")
            untouched(io -> Touchstone.touchstone_write(io,[1e9],asymmetric; matrixformat))
            untouched(io -> Touchstone.touchstone_write(io,[1e9],hermitian; matrixformat))
            symmetric = reshape(ComplexF64[1+2im 3+4im;3+4im 5-6im],2,2,1)
            @test parsefile(written(symmetric; matrixformat, format="RI")).N == symmetric
        end
    end

    @testset "Information sections" begin
        information = ["[Source] Example", "Mixed CASE at 25 °C", "", "[Date] Today"]
        for n in (1,2)
            text = written(ones(ComplexF64,n,n,1); information)
            @test occursin("[Begin Information]\n[Source] Example\n",text)
            @test occursin("[End Information]\n",text)
            @test parsefile(text).information == information
        end
        for version in (1.0,1.1)
            N = ones(ComplexF64,2,2,1)
            @test_throws ErrorException("Information sections require Touchstone version 2.") Touchstone.touchstone_file(
                [1.0],N;version,information)
            untouched(io -> Touchstone.touchstone_write(io,[1.0],N;version,information))
        end
    end

    @testset "Version 1 row layout and ordering" begin
        # Rev. 1.1, pp. 7–9: one line per row for 3/4 ports; larger rows
        # continue in groups of at most four pairs and start on new lines.
        # Construct expected rows directly from matrix coordinates, without
        # invoking the package parser, encoder, or matrixindices helper.
        for version in (1.0, 1.1), n in (1, 2, 3, 4, 5, 6, 8, 9)
            f = [1.0, 2.0]
            N = [complex(10000k+100i+j, -100i-j) for i in 1:n, j in 1:n, k in 1:2]
            actual = numericlines(written(f, N; version, format="RI", frequencyunit="Hz"))
            expected = Vector{Float64}[]
            for k in 1:2
                if n <= 2
                    # Version 1 two-port ordering is column-major.
                    push!(expected, vcat(f[k], collect(Iterators.flatten(
                        (real(N[i,j,k]), imag(N[i,j,k])) for j in 1:n for i in 1:n))))
                else
                    for i in 1:n, firstcol in 1:4:n
                        row = Float64[]
                        i == 1 && firstcol == 1 && push!(row, f[k])
                        for j in firstcol:min(firstcol+3,n)
                            append!(row, (real(N[i,j,k]), imag(N[i,j,k])))
                        end
                        push!(expected, row)
                    end
                end
            end
            @test actual == expected
        end
    end

    @testset "Version 2 full and triangular ordering" begin
        for version in (2.0,2.1), n in (1,2,3,4,5,9), matrixformat in ("Full","Upper","Lower"),
                order in (n == 2 ? ("12_21","21_12") : ("12_21",))
            # Complex transpose symmetry (not conjugate symmetry).
            N = [complex(100max(i,j)+min(i,j), i+j) for i in 1:n, j in 1:n, k in 1:2]
            if matrixformat == "Full"
                N[1,end,1] += 7im # Make full ordering observable for two ports.
            end
            text = written([1.0,2.0],N; version, matrixformat, twoportdataorder=order,
                format="RI", frequencyunit="Hz")
            expected = Float64[]
            for k in 1:2
                push!(expected, k)
                coordinates = [(i,j) for i in 1:n for j in 1:n if
                    matrixformat == "Full" || (matrixformat == "Upper" ? j>=i : j<=i)]
                if n == 2 && order == "21_12"
                    coordinates = [(j,i) for (i,j) in coordinates]
                end
                for (i,j) in coordinates
                    append!(expected, (real(N[i,j,k]),imag(N[i,j,k])))
                end
            end
            @test reduce(vcat,numericlines(text)) == expected
            @test Touchstone.touchstone_parse(IOBuffer(text)).N == N
        end
    end

    @testset "Views, ranges, and numeric conversion" begin
        parent = [ComplexF64(i+10j+100k, i-j) for i in 1:6, j in 1:6, k in 1:4]
        N = @view parent[1:2:5,1:2:5,2:3]
        fs = [0.0,1.0,2.0,3.0]; f = @view fs[2:3]
        ts = Touchstone.touchstone_file(f,N; format="RI",frequencyunit="Hz")
        @test ts.f === f
        @test ts.N === N
        @test isconcretetype(fieldtype(typeof(ts), :f))
        @test isconcretetype(fieldtype(typeof(ts), :N))
        @test written(f,N;format="RI",frequencyunit="Hz") ==
            written(collect(f),Array(N);format="RI",frequencyunit="Hz")
        for array in (N, PermutedDimsArray(N,(2,1,3)), Float32.(real.(N)), real.(N))
            text = written(1:2,array;format="RI",frequencyunit="Hz")
            @test Touchstone.touchstone_parse(IOBuffer(text)).N == ComplexF64.(array)
        end
        # Writes use the current values of retained views.
        parent[1,1,2] = 99+3im
        io = IOBuffer(); Touchstone.touchstone_write(io,ts)
        @test Touchstone.touchstone_parse(IOBuffer(String(take!(io)))).N == N
        mktempdir() do dir
            file = joinpath(dir,"views.s3p")
            Touchstone.touchstone_save(file,f,N;version=1.0,format="RI",frequencyunit="Hz")
            @test Touchstone.touchstone_load(file).N == N
        end
    end

    @testset "Validation of the final record" begin
        # A failure in the final record must not emit a header
        # or an earlier record into a caller-owned stream or destination file.
        for format in ("RI","MA","DB")
            N = ones(ComplexF64,4,4,3)
            N[end,end,end] = format == "DB" ? 0 : Inf
            @test_throws ErrorException Touchstone.touchstone_file([1.,2.,3.],N;format)
            io = IOBuffer(); write(io,"existing")
            @test_throws ErrorException Touchstone.touchstone_write(io,[1.,2.,3.],N;format)
            @test String(take!(io)) == "existing"
            mktempdir() do dir
                file = joinpath(dir,"existing.s4p");write(file,"existing")
                @test_throws ErrorException Touchstone.touchstone_save(file,[1.,2.,3.],N;format)
                @test read(file,String) == "existing"
                @test readdir(dir) == ["existing.s4p"]
            end
        end
    end

    @testset "Malformed metadata is rejected before emission" begin
        bad = String(UInt8[0xff])
        for version in (1.0, 2.0)
            untouched(io -> Touchstone.touchstone_write(io, [1.0], ones(ComplexF64,1,1,1);
                version, comments=["valid", bad]))
            @test_throws ErrorException Touchstone.touchstone_file([1.0], ones(ComplexF64,1,1,1);
                version, comments=[bad])
        end
        untouched(io -> Touchstone.touchstone_write(io, [1.0], ones(ComplexF64,1,1,1);
            comments=["valid"], information=["valid", bad]))
        ts = Touchstone.touchstone_file([1.0], ones(ComplexF64,1,1,1); comments=["valid"])
        push!(ts.comments, bad)
        untouched(io -> Touchstone.touchstone_write(io, ts))
        # Valid Unicode follows the Latin-1/UTF-8 output policy.
        io = IOBuffer()
        Touchstone.touchstone_write(io, [1.0], ones(ComplexF64,1,1,1);
            comments=["25 °C", "50 Ω"], information=["50 Ω"])
        parsed = Touchstone.touchstone_parse(IOBuffer(take!(io)))
        @test parsed.comments[1:2] == ["25 °C", "50 Ω"]
        @test parsed.information == ["50 Ω"]
    end
end
