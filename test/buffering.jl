@testset "Buffered input" begin

    @testset "Caller stream marks" begin
        function checkmark(io, text, prefix, bad, marked)
            seekstart(io)
            marked && mark(io)
            seek(io, sizeof(prefix))
            if bad
                @test_throws ErrorException Touchstone.touchstone_parse(io)
            else
                @test Touchstone.touchstone_parse(io).N[1] == 1
            end
            @test position(io) == sizeof(text)
            @test ismarked(io) == marked
            if marked
                reset(io)
                @test position(io) == 0
                @test read(io, String) == text
            end
        end
        for prefix in ("", "prefix"), bom in ("", "\ufeff"), bad in (false,true), marked in (false,true)
            text = prefix * bom * "# Hz S RI R 50\n1 1 0\n" * (bad ? "[bad]\n" : "")
            checkmark(IOBuffer(text),text,prefix,bad,marked)
            mktemp() do path, io
                write(io,text)
                flush(io)
                checkmark(io,text,prefix,bad,marked)
            end
        end
    end
    @testset "Line storage" begin
        lines = ["first", "25 °C", String(UInt8[0xff]), repeat("x",31), "last"]
        for newline in ("\n", "\r\n", "\r"), blocksize in (7,16,64)
            reader = Touchstone.TouchstoneReader(IOBuffer(join(lines .* newline)),blocksize)
            saved = [Touchstone.readtouchstoneline(reader) for _ in lines]
            @test Touchstone.readereof(reader)
            # Returned strings remain valid after refills and buffer reuse.
            fill!(reader.bytes,0x00)
            @test saved == lines
        end
    end
    @testset "Lines, offsets and section rewinds" begin
        # Expected byte offsets are independent of the reader implementation.
        lines = ["", "a", "25 °C", String(UInt8[0xff]), repeat("z", 31), "last"]
        endings = ["\r\n", "\n", "\r", "\r\n", "\r", ""]
        text = join(lines .* endings)
        for blocksize in (1, 2, 3, 7, 16, 64)
            source = IOBuffer("prefix" * text); seek(source, 6)
            reader = Touchstone.TouchstoneReader(source, blocksize)
            pos = 6
            for (line, ending) in zip(lines, endings)
                @test Touchstone.readerposition(reader) == pos
                @test Touchstone.readtouchstoneline(reader) == line
                pos += sizeof(line) + sizeof(ending)
                @test Touchstone.readerposition(reader) == pos
            end
            @test Touchstone.readereof(reader)
            @test Touchstone.readtouchstoneline(reader) == ""
            Touchstone.seekreader!(reader, 6)
            @test Touchstone.readtouchstoneline(reader) == ""
        end
        # A two-port version 1 file rewinds at the transition to noise data.
        v1 = "# Hz S RI R 50\n2 1 0 2 0 3 0 4 0\n1 .5 .2 0 10 ! noise once\n"
        v2 = "[Version] 2.0\n# Hz S RI R 50\n[Number of Ports] 1\n" *
             "[Number of Frequencies] 1\n[Network Data]\n1 .5 .1\n[End] ! once\n"
        for text in (v1, v2, replace(v2,"[Version] 2.0"=>"[Version] 2.1")), newline in ("\n", "\r\n", "\r"), blocksize in (1, 7, 32)
            reader = Touchstone.TouchstoneReader(IOBuffer(replace(text, "\n"=>newline)), blocksize)
            parsed = Touchstone.parsetouchstone(reader)
            @test parsed.comments == (text == v1 ? [" noise once"] : [" once"])
            @test parsed.N[1] == (text == v1 ? 1 : .5+.1im)
            @test parsed.numberofnoisefrequencies == (text == v1 ? 1 : 0)
        end
        # Actual files: long lines and CRLF pairs on either side of the default
        # block boundary, with a BOM and an unterminated final physical line.
        for n in (65534, 65535, 65536, 131073), newline in ("\n", "\r\n", "\r")
            comment = repeat("x", n)
            text = "\ufeff!" * comment * newline * replace(chomp(v2), "\n"=>newline)
            mktemp() do path, io
                write(io, text); close(io)
                parsed = Touchstone.touchstone_load(path)
                @test parsed.comments == [comment, " once"]
                @test parsed.N[1] == .5+.1im
            end
        end
        source = IOBuffer("prefix" * v2); seek(source, 6)
        @test Touchstone.touchstone_parse(source).N[1] == .5+.1im
        @test position(source) == sizeof("prefix" * v2)
        source = IOBuffer("prefix# invalid\r\nrest"); seek(source, 6)
        @test_throws ErrorException Touchstone.touchstone_parse(source)
        @test position(source) == sizeof("prefix# invalid\r\n")
        @test read(source, String) == "rest"
    end
    @testset "Numeric decoding errors preserve stream ownership" begin
        prefix = "prefix"
        header = "[Version] 2.1\n# Hz Z RI R 50\n[Number of Ports] 1\n" *
            "[Number of Frequencies] 3\n[Network Data]\n"
        # Version 2 Z values are physical; reject a nonfinite parsed component
        # at this record without consuming subsequent records from the stream.
        badrecord = "1 1e999 0\n"
        rest = "2 1 0\n3 1 0\n[End]\n"
        text = prefix * header * badrecord * rest
        function check(io)
            mark(io)
            seek(io,sizeof(prefix))
            @test_throws ErrorException Touchstone.touchstone_parse(io)
            @test isopen(io)
            @test ismarked(io)
            @test position(io) == sizeof(prefix * header * badrecord)
            @test read(io,String) == rest
            reset(io)
            @test position(io) == 0
        end
        check(IOBuffer(text))
        mktemp() do path,io
            write(io,text); seekstart(io)
            check(io)
        end
        # A finite encoded value can also underflow during physical conversion.
        legacy = "# Hz Z RI R 1e-320\n1 1e-320 0\n2 1 0\n3 1 0\n"
        io = IOBuffer(legacy); mark(io)
        @test_throws ErrorException Touchstone.touchstone_parse(io)
        @test ismarked(io)
        @test read(io,String) == "3 1 0\n"
    end

end
