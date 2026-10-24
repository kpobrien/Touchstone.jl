@testset "Mixed-mode data ($version)" for version in (2.0,2.1)
    @testset "touchstone_write mixed-mode order" begin
        # Mixed-mode descriptors survive writing and reading, including Example 16.
        for order in [[('D', [1, 2]), ('C', [1, 2])],
                [('D', [2, 3]), ('D', [6, 5]), ('C', [2, 3]), ('C', [6, 5]), ('S', [4]), ('S', [1])]]
            n = length(order)
            io = IOBuffer()
            Touchstone.touchstone_write(io, [1.0e9], reshape(ComplexF64.(1:n^2), n, n, 1); version, mixedmodeorder = order)
            ts = Touchstone.touchstone_parse(IOBuffer(take!(io)))
            @test ts.mixedmodeorder == order
            @test ts.N == reshape(ComplexF64.(1:n^2), n, n, 1)
        end
    end

    @testset "Mixed-mode semantics and continuations" begin
        valid = [('D',[2,1]),('S',[3]),('C',[2,1])]
        raw = "1 " * join(fill("1 0",9),' ')
        for extra in ("[Mixed-Mode Order] D2,1 S3 C2,1\n",
                      "[Mixed-Mode Order]\nD2,1\n! comment\n\nS3 C2,1\n")
            got = parsefile(v2text(raw; version, n=3,extra))
            @test got.mixedmodeorder == valid
        end
        badorders = [[('D',[1,2]),('D',[1,2])], [('X',[1]),('S',[2])],
            [('S',[0]),('S',[2])], [('S',[1]),('S',[3])], [('D',[1]),('C',[2])],
            [('D',[1,1]),('C',[1,1])], [('D',[1,2]),('C',[2,1])],
            [('S',[1]),('S',[1])], [('S',[1,2]),('S',[2])]]
        for order in badorders
            untouched(io -> Touchstone.touchstone_write(io,[1e9],ones(ComplexF64,2,2,1); version, mixedmodeorder=order))
            descriptors = join((string(m)*join(p,',') for (m,p) in order),' ')
            @test_throws ErrorException parsefile(v2text("1 1 0 1 0 1 0 1 0"; version, n=2,extra="[Mixed-Mode Order] $descriptors\n"))
        end
        for parameter in ("H","G")
            order = [('D',[1,2]),('C',[1,2])]
            untouched(io -> Touchstone.touchstone_write(io,[1e9],ones(ComplexF64,2,2,1); version, parameter,mixedmodeorder=order))
        end
        for extra in ("[Mixed-Mode Order] D1,2\n", "[Mixed-Mode Order] D1,2 C1,2 S1\n",
                      "[Reference] 50 75\n[Mixed-Mode Order] D1,2 C1,2\n")
            @test_throws ErrorException parsefile(v2text("1 1 0 1 0 1 0 1 0"; version, n=2,extra))
        end
        overlap = [('D',[1,2]),('C',[1,2]),('D',[2,3]),('C',[2,3])]
        untouched(io -> Touchstone.touchstone_write(io,[1e9],ones(ComplexF64,4,4,1); version, mixedmodeorder=overlap))
    end
end
