# Tests

Run functional tests without third-party test dependencies:

```sh
julia --project=. --check-bounds=yes test/core.jl
```

Run functional tests, Aqua and Documenter:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Run the same test harness with Aqua 0.8.0 in a temporary package environment:

```sh
julia --check-bounds=yes test/minimum-aqua.jl
```

CI runs this check on Julia 1.9 to exercise the Aqua compatibility lower bound.

| File | Coverage |
|---|---|
| `numbers.jl` | Decimal syntax, float formatting and numeric input conversion |
| `normalization.jl` | Physical units, parameter scaling and numerical range |
| `parsing.jl` | Headers, records, sections, counts and text encodings |
| `mixedmode.jl` | Port descriptors, pairing and reference impedances |
| `writing.jl` | Data ownership, layout, ordering and output validation |
| `files.jl` | File saving, extensions and atomic replacement |
| `buffering.jl` | Buffer boundaries, line endings and cursor positions |
| `helpers.jl` | Shared text fixtures and IO assertions |
| `fixtures.jl` | Independent expected values for file-format examples |

Run `julia --project=. benchmark/io.jl` to measure file and buffer IO, including
noise-heavy and balanced network/noise sweeps across all supported versions.
Use `julia --project=. benchmark/parsing.jl` for the port/frequency, version,
and representation grid. These benchmarks report timing and allocation
without imposing timing thresholds on the functional tests.
