@testset "Parsing" begin

    @testset "Decimal count keywords" begin
        for version in (2.0,2.1)
            text = v2text("1 1 0 2 0 3 0 4 0";version,n=2,
                extra="[Number of Noise Frequencies] 1\n",
                ending="[Noise Data]\n1 .5 .25 90 2\n[End]")
            for (keyword, count) in (("Number of Ports",2),
                    ("Number of Frequencies",1),("Number of Noise Frequencies",1))
                header = "[$keyword] $count"
                for value in ("+$count", "0$count")
                    @test parsedfields(replace(text,header=>"[$keyword] $value")) == parsedfields(text)
                end
                for prefix in ("0x","0o","0b")
                    digits = prefix == "0b" && count == 2 ? "10" : string(count)
                    @test_throws ArgumentError parsefile(replace(text,header=>"[$keyword] $prefix$digits"))
                end
                @test_throws OverflowError parsefile(replace(text,header=>"[$keyword] $(big(typemax(Int))+1)"))
            end
        end
    end

    @testset "Supported version markers" begin
        for version in (2.0,2.1)
            text = v2text("1 .5 .1"; version)
            @test parsefile(text).version == version
            @test parsefile(replace(text,"[Version] $version"=>"[vErSiOn]\t$version  ! marker")).version == version
            for bad in (replace(text,"# GHz S RI R 50\n"=>"[Number of Frequencies] 1\n# GHz S RI R 50\n"),
                        replace(text,"[Number of Ports] 1"=>"[Matrix Format] Full\n[Number of Ports] 1"),
                        replace(text,"[Version] $version"=>"[Version] $version\n[Version] $version"),
                        replace(text,"R 50"=>"R 50 75"))
                @test_throws ErrorException parsefile(bad)
            end
        end
        for marker in ("", "1.0", "1.1", "2", "2.00", "2.10", "2.2", "3.0",
                "NaN", "Inf", "0x1p1", "2.1 2.0", "2.100000000000000000001")
            @test_throws ErrorException parsefile(v2text("1 .5 .1"; version=marker))
        end
    end

    @testset "Port count precedes metadata" begin
        for version in (2.0,2.1), keyword in ("Two-Port Data Order",
                "Number of Frequencies", "Number of Noise Frequencies", "Reference",
                "Matrix Format", "Mixed-Mode Order", "Begin Information", "Network Data")
            text = "[Version] $version\n#\n[$keyword]\n"
            @test_throws ErrorException("[Number of Ports] must precede [$(lowercase(keyword))]") parsefile(text)
        end
    end

    @testset "Version 1.1 option lines" begin
        record = "1 1 0 2 0 3 0 4 0\n"
        for refs in ("4 9", "50 50")
            ts = parsefile("# Hz S RI R $refs !references\n" * record)
            @test ts.version == 1.1
            @test ts.reference == parse.(Float64, split(refs))
            @test ts.R == ts.reference[1]
            @test ts.comments == ["references"]
            @test ts.N[:,:,1] == [1 3; 2 4]
        end
        @test parsefile("# Hz S RI R 4\n" * record).version == 1.0
        @test parsefile("# Hz S RI R 4\n1 1 0\n").version == 1.0
        @test parsefile("# Hz S RI R 4 9\n# GHz Z DB R 75\n" * record).reference == [4,9]
        for option in ("R 4 9 16", "R 4 0", "R 4 -9", "R 4 Inf", "R 4 NaN",
                "R 4 0x20", "R 4 1e999", "R 4 1e-999", "R 4 9 GHz",
                "R 50 R 4 9", "R 4 9 R 50")
            @test_throws ErrorException parsefile("# Hz S RI $option\n" * record)
        end
        @test_throws ErrorException parsefile("# Hz S RI R 4 9\n1 1 0\n")
        @test_throws ErrorException parsefile(replace(v2text(record; n=2),
            "R 50" => "R 4 9"))
        @test_throws ErrorException parsefile("[Version] 1.1\n# Hz S RI R 4 9\n" * record)
        # The complete per-port list belongs on the option line.
        @test_throws ErrorException parsefile("# Hz S RI R 4\n9\n" * record)
        for n in (3,4,5,9)
            rows = [join(fill("1 0", n), ' ') for i in 1:n]
            input = "# Hz Z RI R " * join((i^2 for i in 1:n), ' ') * "\n1 " * join(rows, '\n') * "\n"
            ts = parsefile(input)
            @test ts.version == 1.1
            @test ts.numberofports == n
            @test ts.N[:,:,1] ≈ [i*j for i in 1:n, j in 1:n]
            @test_throws ErrorException parsefile(replace(input, "R " * join((i^2 for i in 1:n), ' ') => "R 4 9"))
        end
    end
    @testset "Inline comment boundaries" begin
        for (line, prefix, comment) in (("Ω!comment", "Ω", "comment"),
                ("25 °!", "25 °", ""), ("!Ω", "", "Ω"),
                (String(UInt8[0xb0,0x21,0x61]), "°", "a"))
            comments = String[]
            @test Touchstone.stripcomments!(comments, line) == prefix
            @test comments == [comment]
        end
        input = v2text("1 .5 0"; extra="[Begin Information]\nΩ!comment\n[End Information]\n")
        ts = parsefile(input)
        @test ts.information == ["Ω"]
        @test ts.comments == ["comment"]
    end

    @testset "Option lines in continued metadata" begin
        for (metadata, field, expected) in (
                ("[Reference] 50\n75\n", :reference, [50.0,75.0]),
                ("[Mixed-Mode Order] D1,2\nC1,2\n", :mixedmodeorder,
                    [('D',[1,2]),('C',[1,2])]))
            continued = replace(metadata, "\n"=>"\n# MHz Z DB R 75 ! skipped\n"; count=1)
            ts = parsefile(v2text("1 .1 0 .2 0 .3 0 .4 0"; n=2, extra=continued))
            @test getfield(ts, field) == expected
            @test ts.parameter == "s"
            @test ts.frequencyunit == "ghz"
            @test ts.comments == [" skipped"]
            incomplete = first(split(metadata, '\n')) * "\n# MHz Z DB R 75\n"
            @test_throws ErrorException parsefile(v2text("1 .1 0 .2 0 .3 0 .4 0";
                n=2, extra=incomplete))
        end
    end

    @testset "touchstone_parse" begin

        examples = [
            "!Example 1:\n!1-port S-parameter file, single frequency point\n# MHz S MA R 50\n!freq magS11 angS11\n2.000 0.894 -12.136",
            "!Example 1a:\n!1-port S-parameter file, single frequency point\n# MHz S DB R 50\n!freq magS11 angS11\n2.000 -0.97 -12.136",
            "!Example 2:\n!1-port Z-parameter file, multiple frequency points\n# MHz Z MA R 75\n!freq magZ11 angZ11\n100 0.99 -4\n200 0.80 -22\n300 0.707 -45\n400 0.40 -62\n500 0.01 -89",
            "!Example 3:\n!2-port H-parameter file, single frequency point\n# KHz H MA R 1\n! freq magH11 angH11 magH21 angH21 magH12 angH12 magH22 angH22\n2 .95 -26 3.57 157 .04 76 .66 -1",
            "!Example 4:\n!2-port S-parameter file, three frequency points\n# GHZ S RI R 50.0\n!freq RelS11 ImS11 ReS21 ImS21 ReS12 ImS12 ReS22 ImS22\n1.0000 0.3926 -0.1211 -0.0003 -0.0021 -0.0003 -0.0021 0.3926 -0.1211\n2.0000 0.3517 -0.3054 -0.0096 -0.0298 -0.0096 -0.0298 0.3517 -0.3054\n10.000 0.3419 0.3336 -0.0134 0.0379 -0.0134 0.0379 0.3419 0.3336",
            "!Example 5:\n! 4-port S-parameter data, taken at three frequency points\n# GHZ S MA R 50\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4\n6.00000 0.57 150.37 0.40 -44.34 0.41 -81.24 0.57 -95.77 !row 1\n0.40 -44.34 0.57 150.37 0.57 -95.77 0.41 -81.24 !row 2\n0.41 -81.24 0.57 -95.77 0.57 150.37 0.40 -44.34 !row 3\n0.57 -95.77 0.41 -81.24 0.40 -44.34 0.57 150.37 !row 4\n7.00000 0.50 136.69 0.45 -46.41 0.37 -99.09 0.62 -114.19 !row 1\n0.45 -46.41 0.50 136.69 0.62 -114.19 0.37 -99.09 !row 2\n0.37 -99.09 0.62 -114.19 0.50 136.69 0.45 -46.41 !row 3\n0.62 -114.19 0.37 -99.09 0.45 -46.41 0.50 136.69 !row 4",
            "!Example 8:\n!2-port network, S-parameter and noise data\n# GHZ S MA R 50\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n! NOISE PARAMETERS\n4 .7 .64 69 .38\n18 2.7 .46 -33 .40",
            "!Example 4 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by [Reference]\n! Data cannot be represented using 1.0 syntax\n! Note that the [Reference] keyword arguments appear on a separate line\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Reference]\n50 75 0.01 0.01\n[Number of Frequencies] 1\n[Network Data]\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4\n[End]",
            "!Example 5 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by the [Reference] keyword arguments\n! Data cannot be represented using 1.0 syntax\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Number of Frequencies] 1\n[Reference] 50 75 0.01 0.01\n[Matrix Format] Full\n[Network Data]\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4\n[End]",
            # Same as above but no matrix format
            "!Example 5 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by the [Reference] keyword arguments\n! Data cannot be represented using 1.0 syntax\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Number of Frequencies] 1\n[Reference] 50 75 0.01 0.01\n[Network Data]\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4\n[End]",
            "!Example 6 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by the [Reference] keyword arguments\n! Note that [Reference] arguments are split across two lines\n! Data cannot be represented using 1.0 syntax\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Number of Frequencies] 1\n[Reference] 50 75\n0.01 0.01\n[Matrix Format] Lower\n[Network Data]\n5.00000 0.60 161.24 !row 1\n0.40 -42.20 0.60 161.20 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4\n[End]",
            "!Example 7 (Version 2.0):\n!1-port Z-parameter file, multiple frequency points\n[Version] 2.0\n# MHz Z MA\n[Number of Ports] 1\n[Number of Frequencies] 5\n[Reference] 20.0\n[Network Data]\n!freq magZ11 angZ11\n100 74.25 -4\n200 60 -22\n300 53.025 -45\n400 30 -62\n500 0.75 -89\n[End]",
            "!Example 8 (Version 1.0):\n!1-port S-parameter file, single frequency point\n# MHz S MA R 50\n!freq magS11 angS11\n2.000 0.894 -12.136",
            "!Example 9 (Version 1.0):\n!1-port Z-parameter file, multiple frequency points\n# MHz Z MA R 75\n!freq magZ11 angZ11\n100 0.99 -4\n200 0.80 -22\n300 0.707 -45\n400 0.40 -62\n500 0.01 -89",
            "!Example 10 (Version 2.0):\n!1-port Z-parameter file, multiple frequency points\n[Version] 2.0\n# MHz Z MA\n[Number of Ports] 1\n[Number of Frequencies] 5\n[Reference] 20.0\n[Network Data]\n!freq magZ11 angZ11\n100 74.25 -4\n200 60 -22\n300 53.025 -45\n400 30 -62\n500 0.75 -89\n[End]",
            "!Example 11 (Version 1.0):\n!2-port H-parameter file, single frequency point\n# kHz H MA R 1\n! freq magH11 angH11 magH21 angH21 magH12 angH12 magH22 angH22\n2 .95 -26 3.57 157 .04 76 .66 -14",
            "!Example 12 (Version 2.0):\n!2-port H-parameter file, single frequency point\n[Version] 2.0\n# kHz H MA R 1\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 1\n[Matrix Format] Full\n[Network Data]\n! freq magH11 angH11 magH21 angH21 magH12 angH12 magH22 angH22\n2 .95 -26 3.57 157 .04 76 .66 -14\n[End]",
            "!Example 13 (Version 1.0):\n!2-port S-parameter file, three frequency points\n# GHz S RI R 50.0\n!freq ReS11 ImS11 ReS21 ImS21 ReS12 ImS12 ReS22 ImS22\n1.0000 0.3926 -0.1211 -0.0003 -0.0021 -0.0003 -0.0021 0.3926 -0.1211\n2.0000 0.3517 -0.3054 -0.0096 -0.0298 -0.0096 -0.0298 0.3517 -0.3054\n10.000 0.3419 0.3336 -0.0134 0.0379 -0.0134 0.0379 0.3419 0.3336",
            "!Example 14 (Version 1.0):\n! 4-port S-parameter data, taken at three frequency points\n! note that data points need not be aligned\n# GHz S MA R 50\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4\n6.00000 0.57 150.37 0.40 -44.34 0.41 -81.24 0.57 -95.77 !row 1\n0.40 -44.34 0.57 150.37 0.57 -95.77 0.41 -81.24 !row 2\n0.41 -81.24 0.57 -95.77 0.57 150.37 0.40 -44.34 !row 3\n0.57 -95.77 0.41 -81.24 0.40 -44.34 0.57 150.37 !row 4\n7.00000 0.50 136.69 0.45 -46.41 0.37 -99.09 0.62 -114.19 !row 1\n0.45 -46.41 0.50 136.69 0.62 -114.19 0.37 -99.09 !row 2\n0.37 -99.09 0.62 -114.19 0.50 136.69 0.45 -46.41 !row 3\n0.62 -114.19 0.37 -99.09 0.45 -46.41 0.50 136.69 !row 4",
            "!Example 16 (Version 2.0):\n!6-port component shown; note that all five ports are used in some\n!relationship\n[Version] 2.0\n# MHz Y RI R 50\n[Number of Ports] 6\n[Number of Frequencies] 1\n[Reference] 50 75 75 50 0.01 0.01\n[Mixed-Mode Order] D2,3 D6,5 C2,3 C6,5 S4 S1\n[Network Data]\n5.00 8.0 9.0 2.0 -1.0 3.0 -2.0 1.0 3.0 1.0 0.1 0.2 -0.2\n2.0 -1.0 7.0 7.0 1.8 -2.0 -1.0 -1.0 -0.5 0.5 0.2 -0.1\n3.0 -2.0 1.8 -2.0 5.8 6.0 1.2 0.8 0.9 0.7 0.3 -0.5\n1.0 3.0 -1.0 -1.0 1.2 0.8 6.3 8.0 2.0 -0.5 1.5 0.6\n1.0 0.1 -0.5 0.5 0.9 0.7 2.0 -0.5 4.7 -6.0 -1.0 2.0\n0.2 -0.2 0.2 -0.1 0.3 -0.5 1.5 0.6 -1.0 2.0 5.5 -7.0\n[End]",
            "!Example 17 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n[Version] 2.0\n#\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50 25.0\n[Network Data]\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n4 .7 .64 69 19\n18 2.7 .46 -33 20\n[End]",
            "!Example 18 (Version 1.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n#\n! NETWORK PARAMETERS\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n! NOISE PARAMETERS\n4 .7 .64 69 .38\n18 2.7 .46 -33 .40",
            "!Example 19 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n[Version] 2.0\n#\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50 25.0\n[Network Data]\n! NETWORK PARAMETERS\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n! NOISE PARAMETERS\n4 .7 .64 69 19\n18 2.7 .46 -33 20\n[End]"
        ]

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
        ]

        for i in eachindex(examples)
            versions = parsedexamples[i].version == 2.0 ? (2.0,2.1) : (1.0,)
            for version in versions
                text = replace(examples[i], "[Version] 2.0"=>"[Version] $version")
                parsedexample = Touchstone.touchstone_parse(IOBuffer(text))
                for field in fieldnames(Touchstone.TouchstoneFile)
                    if field == :version
                        @test parsedexample.version == version
                    elseif field == :N
                        @test getfield(parsedexample,field) ≈ getfield(parsedexamples[i],field) rtol=2e-15
                    else
                        @test getfield(parsedexample,field) == getfield(parsedexamples[i],field)
                    end
                end
            end
        end

    end

    @testset "option line" begin
        # Option-line tokens may use spaces or tabs and appear in any order,
        # except that R precedes its value. Missing tokens use their defaults.
        data = "1.0 0.5 10\n2.0 0.4 20\n"
        for (line, twin) in [
                # The parameter last, the format and R defaulted
                ("# GHz Y", "# GHz Y MA R 50"),
                # Tabs between the parameters
                ("#\tGHz\tZ\tRI\tR\t75", "# GHz Z RI R 75"),
                # R and its value first
                ("# R 75 GHz Z RI", "# GHz Z RI R 75")]
            @test parsedfields(line * "\n" * data) == parsedfields(twin * "\n" * data)
        end
        # Version 1 Y and Z parameters are normalized to R.
        y = Touchstone.touchstone_parse(IOBuffer("# GHz Y MA R 50\n" * data))
        @test y.f == [1.0e9, 2.0e9]
        @test y.N[1, 1, :] ≈ [0.5 * cispi(10 / 180), 0.4 * cispi(20 / 180)] ./ 50
        z = Touchstone.touchstone_parse(IOBuffer("# GHz Z RI R 75\n" * data))
        @test z.N[1, 1, :] ≈ 75 .* [0.5 + 10im, 0.4 + 20im]
        @test z.reference == [75.0]
        # R and its positive value must be separate tokens; unknown tokens fail.
        for line in ["# GHz Z RI R75", "# GHz Z RI R", "# GHz Z RI R 0", "# GHz X RI"]
            @test_throws ErrorException Touchstone.touchstone_parse(IOBuffer(line * "\n" * data))
        end
        # Ignore additional option lines in the header, network data, and noise data.
        second = "# MHz Z RI R 75\n"
        v2text(extra) = "[Version] 2.0\n# GHz S MA R 50\n$(extra)[Number of Ports] 1\n[Number of Frequencies] 2\n[Network Data]\n" * data * "[End]\n"
        network = "# GHz S MA R 50\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n"
        for (text, twin) in [
                (v2text(second), v2text("")),
                ("# GHz S MA R 50\n" * second * data, "# GHz S MA R 50\n" * data),
                ("# GHz S MA R 50\n1.0 0.5 10\n" * second * "2.0 0.4 20\n", "# GHz S MA R 50\n" * data),
                (network * "4 .7 .64 69 .38\n" * second * "18 2.7 .46 -33 .40\n", network * "4 .7 .64 69 .38\n18 2.7 .46 -33 .40\n")]
            @test parsedfields(text) == parsedfields(twin)
        end
    end

    @testset "[Reference]" begin
        # Reference values may use decimal syntax and span multiple lines.
        v2text(reference) = "[Version] 2.0\n# GHz S RI R 50\n[Number of Ports] 2\n[Two-Port Data Order] 12_21\n$(reference)\n[Number of Frequencies] 1\n[Network Data]\n1.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8\n[End]\n"
        for reference in ["[Reference] .5 75", "[Reference]\t.5\n7.5e1"]
            @test parsedfields(v2text(reference)) == parsedfields(v2text("[Reference] 0.5 75"))
        end
        @test Touchstone.touchstone_parse(IOBuffer(v2text("[Reference] 0.5 75"))).reference == [0.5, 75.0]
        # Reference impedances must be positive, with one value per port.
        for reference in ["[Reference] -50 75", "[Reference] 0 75", "[Reference] 50 75 25"]
            @test_throws ErrorException Touchstone.touchstone_parse(IOBuffer(v2text(reference)))
        end
    end

    @testset "version 1 noise data" begin
        # Version 1 noise data start at or below the highest network frequency.
        # Reading noise records must preserve the preceding network records.
        network = "# GHz S MA R 50\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n"
        twin = Touchstone.touchstone_parse(IOBuffer(network))
        for noise in ["22 .7 .64 69 .38\n26 2.7 .46 -33 .40\n", "4 .7 .64 69 .38\n18 2.7 .46 -33 .40\n"]
            ts = Touchstone.touchstone_parse(IOBuffer(network * noise))
            @test (ts.f, ts.N) == (twin.f, twin.N)
            @test ts.noisedata == parse.(Float64, split(noise)) .* repeat([1, 1, 1, 1, 50], 2)
            @test ts.numberofnoisefrequencies == 2
        end
        # A first frequency of zero is network data
        @test Touchstone.touchstone_parse(IOBuffer("# GHz S RI R 50\n0 1 0\n1 0.5 0.5\n")).f == [0.0, 1.0e9]
    end

    @testset "frequency order and counts" begin
        # Network frequencies must increase and declared counts must match the data.
        # Only a five-value version 1 noise record may start at a lower frequency.
        increase(f, previous, line) = "The network data frequencies do not increase: $(f) follows $(previous) on the line: $(line)"
        v2text(count, data) = "[Version] 2.0\n# GHz S RI R 50\n[Number of Ports] 1\n$(count)\n[Network Data]\n$(data)[End]\n"
        twoport = "# GHz S MA R 50\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n"
        noise2 = "[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Network Data]\n2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n4 .7 .64 69 19\n[End]\n"
        for (text, message) in [
                ("# GHz S RI R 50\n1.0 0.5 0.1\n1.0 0.5 0.1\n2.0 0.4 0.2\n", increase(1.0, 1.0, "1.0 0.5 0.1")),
                ("# GHz S RI R 50\n2.0 0.5 0.1\n1.0 0.4 0.2\n", increase(1.0, 2.0, "1.0 0.4 0.2")),
                (twoport * "22 .60 -144 1.30 40 .14 40 .56 -85\n", increase(22.0, 22.0, "22 .60 -144 1.30 40 .14 40 .56 -85")),
                (v2text("[Number of Frequencies] 3", "1.0 0.5 0.1\n1.0 0.5 0.1\n2.0 0.4 0.2\n"), increase(1.0, 1.0, "1.0 0.5 0.1")),
                (v2text("[Number of Frequencies] 3", "1.0 0.5 0.1\n2.0 0.4 0.2\n"), "[Number of Frequencies] is 3, the network data has 2."),
                (noise2, "[Number of Noise Frequencies] is 2, the noise data has 1.")]
            @test_throws ErrorException(message) Touchstone.touchstone_parse(IOBuffer(text))
        end
        # Frequencies must be finite and nonnegative; noise frequencies must increase.
        frequency(f, line) = "The network data frequency $(f) is not a finite, nonnegative number on the line: $(line)"
        noise(f, previous, line) = "The noise data frequencies do not increase: $(f) follows $(previous) on the line: $(line)"
        for (text, message) in [
                ("# GHz S RI R 50\n-1.0 0.5 0.1\n2.0 0.4 0.2\n", frequency(-1.0, "-1.0 0.5 0.1")),
                ("# GHz S RI R 50\nnan 0.5 0.1\n2.0 0.4 0.2\n", "\"nan\" is not a decimal number, on the line: nan 0.5 0.1"),
                ("# GHz S RI R 50\n1.0 0.5 0.1\nnan 0.4 0.2\n3.0 0.3 0.3\n", "\"nan\" is not a decimal number, on the line: nan 0.4 0.2"),
                ("# GHz S RI R 50\n1.0 0.5 0.1\ninf 0.4 0.2\n", "\"inf\" is not a decimal number, on the line: inf 0.4 0.2"),
                (twoport * "4 .7 .64 69 .38\n4 2.7 .46 -33 .40\n", noise(4.0, 4.0, "4 2.7 .46 -33 .40")),
                (twoport * "nan .7 .64 69 .38\n", "\"nan\" is not a decimal number, on the line: nan .7 .64 69 .38")]
            @test_throws ErrorException(message) Touchstone.touchstone_parse(IOBuffer(text))
        end
    end

    @testset "[Version] first" begin
        # [Version] must precede all other content in version 2 files.
        # Version 1 files cannot contain keywords.
        data = "# GHz S RI R 50\n1.0 0.5 0.1\n"
        for keyword in ["[Number of Ports] 1", "[Number of Frequencies] 1", "[Matrix Format] Full"]
            message = "The keyword $(lowercase(keyword)) is only allowed after [Version] 2.0 or 2.1, which precedes all other lines of a version 2 file."
            @test_throws ErrorException(message) Touchstone.touchstone_parse(IOBuffer(keyword * "\n" * data))
        end
        @test Touchstone.touchstone_parse(IOBuffer("[Version] 2.0\n# GHz S RI R 50\n[Number of Ports] 1\n[Number of Frequencies] 1\n[Network Data]\n1.0 0.5 0.1\n[End]\n")).N == Touchstone.touchstone_parse(IOBuffer(data)).N
    end

    @testset "[Network Data]" begin
        # Keywords start in column one and require whitespace before arguments.
        # [Network Data] accepts trailing whitespace and comments, but no arguments.
        v2text(keyword) = "[Version] 2.0\n# GHz S RI R 50\n[Number of Ports] 1\n[Number of Frequencies] 2\n$(keyword)\n1.0 0.5 10\n2.0 0.4 20\n[End]\n"
        for (keyword, twin) in [("[Network Data]   ", "[Network Data]"),
                ("[Network Data]\t", "[Network Data]"),
                ("[Network Data] ! data follow", "[Network Data]\n! data follow")]
            @test parsedfields(v2text(keyword)) == parsedfields(v2text(twin))
        end
        @test Touchstone.touchstone_parse(IOBuffer(v2text("[Network Data]"))).N[1, 1, :] == [0.5 + 10im, 0.4 + 20im]
        # An argument is refused
        @test_throws ErrorException Touchstone.touchstone_parse(IOBuffer(v2text("[Network Data] 1")))
    end

    @testset "ISO 8859-1" begin
        # Invalid UTF-8 is decoded as Latin-1 in comments and information text.
        data = "# GHz S MA R 50\n1.0 0.5 10\n2.0 0.4 20\n"
        latin = Touchstone.touchstone_parse(IOBuffer("! measured at 25 \xb0C\n" * data))
        @test latin.comments == [" measured at 25 °C"]
        @test latin.N == Touchstone.touchstone_parse(IOBuffer("! measured at 25 C\n" * data)).N
        information = "[Version] 2.0\n# GHz S RI R 50\n[Number of Ports] 1\n[Begin Information]\nmeasured at 25 \xb0C\n[End Information]\n[Number of Frequencies] 2\n[Network Data]\n1.0 0.5 10\n2.0 0.4 20\n[End]\n"
        @test Touchstone.touchstone_parse(IOBuffer(information)).information == ["measured at 25 °C"]
    end

    @testset "touchstone_parse errors" begin

        # Empty input
        message = "Input is empty and thus not a valid touchstone file."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer())
        )

        # Two version lines
        example = "!Example 4 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by [Reference]\n! Data cannot be represented using 1.0 syntax\n! Note that the [Reference] keyword arguments appear on a separate line\n[Version] 2.0\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Reference]\n50 75 0.01 0.01\n[Number of Frequencies] 1\n[Network Data]\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4"
        message = "Only one [Version] keyword allowed: [version] 2.0"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # Two [Number of Ports] keywords
        example = "!Example 4 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by [Reference]\n! Data cannot be represented using 1.0 syntax\n! Note that the [Reference] keyword arguments appear on a separate line\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Number of Ports] 4\n[Reference]\n50 75 0.01 0.01\n[Number of Frequencies] 1\n[Network Data]\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4"
        message = "Only one [Number of Ports] keyword allowed: [number of ports] 4"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # Two [Two-Port Data Order] keywords
        example = "!Example 17 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50.0 25.0\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n[Noise Data]\n4.0 0.7 0.64 69.0 19.0\n18.0 2.7 0.46 -33.0 20.0\n[End]"
        message = "Only one [Two-Port Data Order] line allowed: [two-port data order] 21_12"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # [Two-Port Data Order] line for 4-port file
        example = "!Example 4 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by [Reference]\n! Data cannot be represented using 1.0 syntax\n! Note that the [Reference] keyword arguments appear on a separate line\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Two-Port Data Order] 21_12\n[Reference]\n50 75 0.01 0.01\n[Number of Frequencies] 1\n[Network Data]\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4"
        message = "[Two-Port Data Order] is only allowed if [Number of Ports] is 2: [two-port data order] 21_12"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # [Begin Information] before [Number of Ports]
        example = "!Example 17 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n[Version] 2.0\n# ghz s ma R 50.0\n[Begin Information]\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50.0 25.0\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n[Noise Data]\n4.0 0.7 0.64 69.0 19.0\n18.0 2.7 0.46 -33.0 20.0\n[End]"
        message = "[Number of Ports] must precede [begin information]"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # Two [End Information] keywords
        example = "!Example 17 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Begin Information]\ninformation\n[End Information]\n[End Information]\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50.0 25.0\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n[Noise Data]\n4.0 0.7 0.64 69.0 19.0\n18.0 2.7 0.46 -33.0 20.0\n[End]"
        message = "Unexpected [End Information] outside an information section."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # Two [Reference] keywords
        example = "!Example 17 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50.0 25.0\n[Reference] 50.0 25.0\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n[Noise Data]\n4.0 0.7 0.64 69.0 19.0\n18.0 2.7 0.46 -33.0 20.0\n[End]"
        message = "Only one [Reference] keyword allowed: [reference] 50.0 25.0"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # [Number of Ports] must be before [Reference]
        example = "!Example 17 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n[Version] 2.0\n# ghz s ma R 50.0\n[Reference] 50.0 25.0\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n[Noise Data]\n4.0 0.7 0.64 69.0 19.0\n18.0 2.7 0.46 -33.0 20.0\n[End]"
        message = "[Number of Ports] must precede [reference]"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # Unknown keyword
        example = "!Example 17 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 2\n[Two-Port Data Order] 21_12\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50.0 25.0\n[Unknown keyword example] unknown line example\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n[Noise Data]\n4.0 0.7 0.64 69.0 19.0\n18.0 2.7 0.46 -33.0 20.0\n[End]"
        message = "Unknown line type: [unknown keyword example] unknown line example"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # Number of ports in data and header not consistent
        example = "!Example 4 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by [Reference]\n! Data cannot be represented using 1.0 syntax\n! Note that the [Reference] keyword arguments appear on a separate line\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 2\n[Two-Port Data Order] 12_21\n[Reference]\n50 75\n[Number of Frequencies] 1\n[Network Data]\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4"
        message = "More network records than [Number of Frequencies]."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # Too many reference impedances for the declared port count.
        example = "!Example 4 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by [Reference]\n! Data cannot be represented using 1.0 syntax\n! Note that the [Reference] keyword arguments appear on a separate line\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 2\n[Reference]\n50 75 0.01 0.01\n[Number of Frequencies] 1\n[Network Data]\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4"
        message = "Too many values on [Reference] line: 50 75 0.01 0.01"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # A new keyword cannot replace missing reference impedances.
        example = "!Example 4 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by [Reference]\n! Data cannot be represented using 1.0 syntax\n! Note that the [Reference] keyword arguments appear on a separate line\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Reference]\n50 75\n[Number of Frequencies] 1\n[Network Data]\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4"
        message = "\"[number\" is not a decimal number, on the line: [number of frequencies] 1"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )


        # No network data.
        example = "!Example 13 (Version 1.0):\n!2-port S-parameter file, three frequency points\n!freq ReS11 ImS11 ReS21 ImS21 ReS12 ImS12 ReS22 ImS22\n# ghz s ri R 50.0\n"
        message = "No network data."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # No [Two-Port Data Order] keyword in v2 file with 2 ports
        example = "!Example 17 (Version 2.0):\n!2-port network, S-parameter and noise data\n!Default MA format, GHz frequencies, 50 ohm reference, S-parameters\n[Version] 2.0\n# ghz s ma R 50.0\n[Number of Ports] 2\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 2\n[Reference] 50.0 25.0\n[Network Data]\n! freq mags11 angs11 mags21 angs21 mags12 angs12 mags22 angs22 \n2.0 0.95 -26.0 3.57 157.0 0.04 76.0 0.66 -14.0\n22.0 0.6 -144.0 1.3 40.0 0.14 40.0 0.56 -85.0\n[Noise Data]\n4.0 0.7 0.64 69.0 19.0\n18.0 2.7 0.46 -33.0 20.0\n[End]"
        message = "two-port data order must be defined for a v2 file with two ports."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # [Two-Port Data Order] keyword not allowed in v2 file with more than 2 ports
        example = "!Example 4 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by [Reference]\n! Data cannot be represented using 1.0 syntax\n! Note that the [Reference] keyword arguments appear on a separate line\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Two-Port Data Order] 21_12\n[Reference]\n50 75 0.1 0.1\n[Number of Frequencies] 1\n[Network Data]\n5.00000 0.60 161.24 0.40 -42.20 0.42 -66.58 0.53 -79.34 !row 1\n0.40 -42.20 0.60 161.20 0.53 -79.34 0.42 -66.58 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 0.40 -42.20 !row 3\n0.53 -79.34 0.42 -66.58 0.40 -42.20 0.60 161.24 !row 4"
        message = "[Two-Port Data Order] is only allowed if [Number of Ports] is 2: [two-port data order] 21_12"
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # Triangular network records must match the declared dimensions.
        example = "!Example 6 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by the [Reference] keyword arguments\n! Note that [Reference] arguments are split across two lines\n! Data cannot be represented using 1.0 syntax\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Number of Frequencies] 1\n[Reference] 50 75\n0.01 0.01\n[Matrix Format] Lower\n[Network Data]\n5.00000 0.60 161.24 !row 1\n0.40 -42.20 0.60 161.20 !row 2\n0.42 -66.58 0.53 -79.34 0.60 161.24 !row 3\n[End]"
        message = "Incomplete network data record before [end]."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

        # Network records must have consistent widths.
        example = "!Example 6 (Version 2.0):\n! 4-port S-parameter data\n! Default impedance is overridden by the [Reference] keyword arguments\n! Note that [Reference] arguments are split across two lines\n! Data cannot be represented using 1.0 syntax\n[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 4\n[Number of Frequencies] 1\n[Reference] 50 75\n0.01 0.01\n[Matrix Format] Lower\n[Network Data]\n5.00000 0.60 !row 1\n0.40 -42.20 0.60 !row 2\n0.42 -66.58 0.53 -79.34 0.60 !row 3\n[End]"
        message = "Incomplete network data record before [end]."
        @test_throws(
            ErrorException(message),
            Touchstone.touchstone_parse(IOBuffer(example))
        )

    end

    @testset "hybrid parameters of two ports" begin
        # H and G parameters require two ports when reading and writing.
        for (p, nports, text) in [("H", 1, "# GHz H RI R 50\n1.0 0.5 0.1\n"),
                ("G", 3, "# GHz G RI R 50\n" * "1.0" * " 0.1 0"^9 * "\n")]
            @test_throws ErrorException("$(p) parameters are defined for two-port networks only; the file has $(nports) ports.") Touchstone.touchstone_parse(IOBuffer(text))
        end
        @test_throws ErrorException Touchstone.touchstone_write(IOBuffer(), [1.0e9], fill(0.1 + 0im, 1, 1, 1); parameter = "H")
        @test size(Touchstone.touchstone_parse(IOBuffer("# GHz H RI R 50\n1.0 0.5 0 1 0 -1 0 0.1 0\n")).N) == (2, 2, 1)
    end

    @testset "noise data of two ports" begin
        # Noise data require two ports when reading and writing.
        message = "Noise parameters are only included in files of two-port networks; the file has 1 ports."
        for text in ["# GHz S MA R 50\n1.0 0.5 10\n2.0 0.4 20\n1.0 .7 .64 69 .38\n",
                "[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 1\n[Number of Frequencies] 2\n[Number of Noise Frequencies] 1\n[Network Data]\n1.0 0.5 10\n2.0 0.4 20\n[Noise Data]\n1.0 .7 .64 69 19\n[End]\n"]
            @test_throws ErrorException(message) Touchstone.touchstone_parse(IOBuffer(text))
        end
        @test_throws ErrorException Touchstone.touchstone_write(IOBuffer(), [1.0e9, 2.0e9], fill(0.1 + 0im, 1, 1, 2); noisedata = [1.0, 0.7, 0.64, 69.0, 19.0])
    end

    @testset "after [End]" begin
        # After [End], accept comments and reject other content.
        v2 = "[Version] 2.0\n# GHz S MA R 50\n[Number of Ports] 1\n[Number of Frequencies] 2\n[Network Data]\n1.0 0.5 10\n2.0 0.4 20\n[End]\n"
        ts = Touchstone.touchstone_parse(IOBuffer(v2 * "! the end\n"))
        @test ts.comments == [" the end"]
        @test ts.N == Touchstone.touchstone_parse(IOBuffer(v2)).N
        for (after, line) in [("[Number of Ports] 2\n", "[number of ports] 2"),
                ("4 .7 .64 69 19\n", "4 .7 .64 69 19"), ("garbage here\n", "garbage here")]
            @test_throws ErrorException("Only comments may follow [End]: $(line)") Touchstone.touchstone_parse(IOBuffer(v2 * after))
        end
    end

    @testset "byte order mark" begin
        # A leading UTF-8 byte order mark does not change the parsed data.
        for text in ["# GHz S MA R 50\n1.0 0.5 10\n2.0 0.4 20\n", "! comment\r\n# GHz S MA R 50\r\n1.0 0.5 10\r\n"]
            @test parsedfields("\ufeff" * text) == parsedfields(text)
        end
    end

    @testset "parsetwoportdataorder" begin
        @test_throws(
            ErrorException("Unknown [Two-Port Data Order] parameter: [two-port data order] 21_34"),
            Touchstone.parsetwoportdataorder("[two-port data order] 21_34")
        )
    end

    @testset "parsenumberoffrequencies" begin
        @test_throws(
            ErrorException("Number of frequencies must be an integer greater than zero: [number of frequencies] 0"),
            Touchstone.parsenumberoffrequencies("[number of frequencies] 0")
        )
    end

    @testset "parsenumberofnoisefrequencies" begin
        @test_throws(
            ErrorException("Number of noise frequencies must be an integer greater than zero: [number of noise frequencies] 0"),
            Touchstone.parsenumberofnoisefrequencies("[number of noise frequencies] 0")
        )
    end

    @testset "parsereference!" begin
        io = IOBuffer("[Reference] 50.0 \n60.0 75.0 1.0\n[Number of Frequencies] 1")
        numberofports = 3
        comments = String[]
        reference = Float64[]
        line = Touchstone.stripcommentslowercase!(comments,readline(io))
        @test_throws(
            ErrorException("Too many values on [Reference] line: 60.0 75.0 1.0"),
            Touchstone.parsereference!(reference, comments, line, numberofports, io)
        )
    end

    @testset "parsematrixformat" begin
        @test_throws(
            ErrorException("Unknown format: unknown"),
            Touchstone.parsematrixformat("[matrix format] unknown")
        )
    end

    @testset "parsenetworkdata!" begin
        networkdata = Float64[]
        comments = String[]
        io = IOBuffer("2 .95 -26 3.57 157 .04 76 .66 -14\n# GHz S MA R 50\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n4 .7 .64 69 19\n18 2.7 .46 -33 20\n[End]")
        # A second option line is ignored
        @test Touchstone.parsenetworkdata!(networkdata,comments,io,2.0) == (2, 9)
        @test networkdata == [2.0, 0.95, -26.0, 3.57, 157.0, 0.04, 76.0, 0.66, -14.0, 22.0, 0.6, -144.0, 1.3, 40.0, 0.14, 40.0, 0.56, -85.0]
        # The three-argument network reader uses version 1 record boundaries
        # and leaves the first noise record unread.
        example = "2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n4 .7 .64 69 .38\n18 2.7 .46 -33 .40\n"
        network(args...) = (data = Float64[]; io = IOBuffer(example); (Touchstone.parsenetworkdata!(data, String[], io, args...), data, read(io, String)))
        @test network() == network(1.0)
        @test network()[1] == (2, 9)
    end

    @testset "parsenoisedata!"  begin

    networkdata = Float64[]
    noisedata = Float64[]
    comments = String[]
    io = IOBuffer("2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n4 .7 .64 69 19 1.2\n18 2.7 .46 -33 20\n[End]")
    Touchstone.parsenetworkdata!(networkdata,comments,io,2.0)
    @test_throws(
        ErrorException("Noise data lines must have 5 entries."),
        Touchstone.parsenoisedata!(noisedata,comments,io)
    )

    networkdata = Float64[]
    noisedata = Float64[]
    comments = String[]
    io = IOBuffer("2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n4 .7 .64 69 19\n[Noise Data]\n18 2.7 .46 -33 20\n[End]")
    Touchstone.parsenetworkdata!(networkdata,comments,io,2.0)
    @test_throws(
        ErrorException("Only one [Noise Data] keyword allowed."),
        Touchstone.parsenoisedata!(noisedata,comments,io)
    )

    networkdata = Float64[]
    noisedata = Float64[]
    comments = String[]
    io = IOBuffer("2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n4 .7 .64 69 19\n# GHz S MA R 50\n18 2.7 .46 -33 20\n[End]")
    Touchstone.parsenetworkdata!(networkdata,comments,io,2.0)
    # A second option line is ignored
    @test Touchstone.parsenoisedata!(noisedata,comments,io) == 2
    @test noisedata == [4.0, 0.7, 0.64, 69.0, 19.0, 18.0, 2.7, 0.46, -33.0, 20.0]

    networkdata = Float64[]
    noisedata = Float64[]
    comments = String[]
    io = IOBuffer("2 .95 -26 3.57 157 .04 76 .66 -14\n22 .60 -144 1.30 40 .14 40 .56 -85\n[Noise Data]\n18 2.7 .46 -33 20\n4 .7 .64 69 19\n[End]")
    Touchstone.parsenetworkdata!(networkdata,comments,io,2.0)
    @test_throws(
        ErrorException("The noise data frequencies do not increase: 4.0 follows 18.0 on the line: 4 .7 .64 69 19"),
        Touchstone.parsenoisedata!(noisedata,comments,io)
    )

    end

    @testset "Record boundaries and section ownership ($version)" for version in (2.0,2.1)
        expected = [.5+.1im,.4+.2im]
        for data in ("1 .5\n.1\n2 .4\n.2", "1\n.5\n.1\n2\n.4\n.2", "1 .5 .1\n2 .4 .2")
            @test parsefile(v2text(data; version, nf=2)).N[1,1,:] ≈ expected
        end
        # Every split of a full/triangular two-port record, including odd lines.
        for (mf,values,N) in (("Full",[1.,2.,3.,4.,5.,6.,7.,8.,9.],ComplexF64[2+3im 4+5im;6+7im 8+9im]),
                              ("Upper",[1.,2.,3.,4.,5.,6.,7.],ComplexF64[2+3im 4+5im;4+5im 6+7im]),
                              ("Lower",[1.,2.,3.,4.,5.,6.,7.],ComplexF64[2+3im 4+5im;4+5im 6+7im]))
            for splitpoint in 1:length(values)-1
                data = join(values[1:splitpoint],' ')*"\n"*join(values[splitpoint+1:end],' ')
                @test parsefile(v2text(data; version, n=2,extra="[Matrix Format] $mf\n")).N[:,:,1] == N
            end
        end
        for data in ("1 .5", "1 .5 .1\n2 .4", "1 .5 .1 2 .4 .2", "1 .5 .1\n2 .4 .2\n3 .3 .2")
            @test_throws ErrorException parsefile(v2text(data; version, nf=2))
        end
        @test_throws ErrorException parsefile("# Hz S RI R 50\n1 .5 .1\n2 .4\n")
        @test_throws ErrorException parsefile("# Hz S RI R 50\n1 .5 .1 .3 .2\n")
        got = parsefile(v2text("1 .5 .1"; version, ending="[End] ! once\n! after"))
        @test count(==(" once"),got.comments) == 1
        @test count(==(" after"),got.comments) == 1
        got = parsefile("# GHz S RI R 50\n2 .1 0 .2 0 .3 0 .4 0\n1 .5 .2 0 10 ! noise once\n")
        @test count(==(" noise once"),got.comments) == 1
        text = v2text("2 .1 0 .2 0 .3 0 .4 0"; version, n=2,extra="[Number of Noise Frequencies] 1\n",
            ending="[Noise Data] ! section\n1 .5 .2 0 10 ! row\n[End] ! end")
        got = parsefile(text)
        @test got.comments == [" section"," row"," end"]
        @test_throws ErrorException parsefile(replace(text,"1 .5 .2 0 10"=>"3 .5 .2 0 10"))
    end

    @testset "Empty network sections" begin
        for version in (2.0,2.1), count in (1,3)
            text = v2text("! no records";version,nf=count)
            @test_throws ErrorException("[Number of Frequencies] is $count, the network data has 0.") parsefile(text)
        end
        for reference in ("50", "50 75")
            @test_throws ErrorException("No network data.") parsefile("# Hz S RI R $reference\n")
        end
    end

    @testset "Negative noise frequencies" begin
        network = "2 1 0 2 0 3 0 4 0"
        noise = "-1 .5 .25 90 2"
        for version in (1.0,1.1,2.0,2.1)
            reference = version == 1.1 ? "50 75" : "50"
            text = version < 2 ? "# GHz S RI R $reference\n$network\n$noise\n" :
                v2text(network;version,n=2,extra="[Number of Noise Frequencies] 1\n",
                    ending="[Noise Data]\n$noise\n[End]")
            @test_throws ErrorException("The noise data frequency -1.0 is not a finite, nonnegative number on the line: $noise") parsefile(text)
        end
    end

    @testset "Headers and line endings ($version)" for version in (2.0,2.1)
        base = v2text("1 .5 .1"; version)
        for bad in (replace(base,"[End]"=>""), replace(base,"[End]"=>"[End] garbage"),
                    replace(base,"# GHz S RI R 50\n"=>""), replace(base,"[Number of Ports] 1"=>"[Number of Ports] 0"),
                    replace(base,"[Version] $version"=>"[Version] 3.0"),replace(base,"[Version] $version"=>"[Version]$version"),
                    replace(base,"[Number of Frequencies] 1\n"=>""),replace(base,"[Network Data]\n"=>""),
                    replace(base,"[Number of Frequencies] 1"=>"[Number of Frequencies] 1\n[Number of Frequencies] 1"),
                    replace(base,"[Network Data]"=>"[Begin Information]\nno terminator\n[Network Data]"),
                    replace(base,"[End]"=>"[Noise Data]\n[End]"))
            @test_throws ErrorException parsefile(bad)
        end
        @test_throws ErrorException parsefile("# Hz S RI R 50\n1 .5 0\n[End]\n")
        @test_throws ErrorException parsefile("# Hz S RI R 50\n1 .5 0\n[Noise Data]\n")
        for newline in ("\n","\r\n","\r"), prefix in ("","\ufeff")
            text = prefix * replace(base,"\n"=>newline)
            @test parsefile(text).N[1] == .5+.1im
            mktemp() do path,io
                write(io,text);close(io)
                @test Touchstone.touchstone_load(path).N[1] == .5+.1im
            end
        end
    end

    @testset "Network line wrapping" begin
        # Accept arbitrary version 2 wrapping and version 1 rows split across lines.
        N = reshape(ComplexF64.(1:16),4,4,1)
        text = written([1.0],N; version=1.0,format="RI",frequencyunit="Hz")
        values = reduce(vcat,numericlines(text))
        chunks = (9,6,2,8,6,2)
        start = 1; lines = String[]
        for count in chunks
            push!(lines, join(values[start:start+count-1],' ')); start += count
        end
        @test Touchstone.touchstone_parse(IOBuffer("# Hz S RI R 50\n"*join(lines,'\n'))).N == N
        header = "[Version] 2.0\n# Hz S RI R 50\n[Number of Ports] 4\n[Number of Frequencies] 1\n[Network Data]\n"
        @test Touchstone.touchstone_parse(IOBuffer(header*join(values,'\n')*"\n[End]")).N == N
    end
    @testset "Incremental record storage" begin
        for version in (1.0,1.1,2.0,2.1), (ports,count) in
                ((1,1),(2,2),(2,3),(2,1023),(2,1025),(16,31),(16,33)),
                matrixformat in (version < 2 ? ("Full",) : ("Full","Upper","Lower"))
            f = collect(1.0:count)
            N = [ComplexF64(i+j+10k, i+j-k) for i in 1:ports,j in 1:ports,k in 1:count]
            text = written(f,N;version,matrixformat,format="RI",frequencyunit="Hz")
            parsed = parsefile(text)
            @test parsed.f == f
            @test parsed.N == N
            @test parsed.N isa Array{ComplexF64,3}
            @test parsed.numberoffrequencies == count
        end
    end

    @testset "Large-matrix record storage" begin
        # Build records independently of the writer at and above the block
        # target, including counts on either side of a consolidation boundary.
        for ports in (64,65), count in (1,2,3,5), version in (1.0,2.0,2.1),
                matrixformat in (version < 2 ? ("Full",) : ("Full","Upper","Lower"))
            N = [matrixformat == "Full" ? ComplexF64(i+10j+100k,i-j) :
                ComplexF64(i+j+100k,i+j-k) for i in 1:ports,j in 1:ports,k in 1:count]
            io = IOBuffer()
            version >= 2 && println(io,"[Version] ",version)
            println(io,"# Hz S RI R 50")
            if version >= 2
                println(io,"[Number of Ports] ",ports)
                println(io,"[Number of Frequencies] ",count)
                println(io,"[Matrix Format] ",matrixformat)
                println(io,"[Network Data]")
            end
            for k in 1:count
                print(io,k)
                for i in 1:ports, j in 1:ports
                    matrixformat == "Upper" && i > j && continue
                    matrixformat == "Lower" && i < j && continue
                    z = N[i,j,k]
                    print(io,' ',real(z),' ',imag(z))
                end
                println(io)
            end
            version >= 2 && println(io,"[End]")
            parsed = parsefile(String(take!(io)))
            @test parsed.f == collect(1.0:count)
            @test parsed.N == N
            @test parsed.N isa Array{ComplexF64,3}
            @test parsed.numberoffrequencies == count
        end
    end

    @testset "Legacy first and final records" begin
        for reference in ("50", "50 75")
            @test_throws ErrorException("A network record must start with a frequency.") parsefile(
                "# Hz S RI R $reference\n1 0\n")
        end
        for data in ("1", "1 \n", "1\n2\n")
            @test_throws ErrorException("Incomplete or non-square network data record.") parsefile(
                "# Hz S RI R 50\n" * data)
        end
        for version in (1.0,1.1), ports in (1,2,3,4,5,9), count in (1,3)
            N = [ComplexF64(i+10j+100k,i-j) for i in 1:ports,j in 1:ports,k in 1:count]
            order = ports == 2 ? [(i,j) for j in 1:ports for i in 1:ports] :
                [(i,j) for i in 1:ports for j in 1:ports]
            lines = ["# Hz S RI R " * (version == 1.0 ? "50" : join(fill(50,ports),' '))]
            for k in 1:count
                push!(lines,"$k ! frequency $k")
                push!(lines,"# ignored option line")
                for (i,j) in order
                    z = N[i,j,k]
                    push!(lines,"$(real(z)) $(imag(z))")
                end
            end
            parsed = parsefile(join(lines,'\n'))
            @test parsed.N == N
            @test parsed.f == collect(1.0:count)
            @test parsed.comments == [" frequency $k" for k in 1:count]
        end
        for data in ("1 1 0\n2 2 0 3 0", "1 1 0\n2", "1 1 0\n2 2 0\n3 3 0 4 0",
                "1 1 0\n2 2 0\n3 3", "1 1 0\n2 2 0\n3 3 0\n4 4 0 5 0\n5 5 0")
            @test_throws ErrorException parsefile("# Hz S RI R 50\n" * data)
        end
        # The noise reader owns the lookahead line and its comment, even when
        # the only network record has been split across physical lines.
        text = "# Hz S RI R 4 9\n2 ! network\n1 0 2 0\n3 0 4 0\n" *
            "1 .5 .25 90 .5 ! noise\n"
        parsed = parsefile(text)
        @test parsed.N[:,:,1] == [1 3;2 4]
        @test parsed.noisedata == [1,.5,.25,90,2]
        @test parsed.comments == [" network"," noise"]
    end

    @testset "Incomplete declared data" begin
        for version in (2.0,2.1), count in (1,3,typemax(Int))
            text = v2text("1 .5 .1";version,nf=count)
            if count == 1
                @test parsefile(text).N[1] == .5+.1im
            else
                @test_throws ErrorException parsefile(text)
            end
            @test_throws ErrorException parsefile(v2text("1 .5";version,nf=count))
        end
        for ports in (1_000_000,typemax(Int))
            @test_throws Exception parsefile(v2text("1 .5 .1";n=ports))
        end
    end

end
