# Source organization

All implementation files belong to the `Touchstone` module. `Touchstone.jl`
includes them in dependency order and defines the exports.

| File | Responsibility |
| --- | --- |
| `types.jl` | Network data and option-line types, field meanings, and units. |
| `reader.jl` | Buffered byte reading, line endings, decimal tokens, comments, and text encoding. |
| `conversion.jl` | Matrix ordering, frequency units, normalization, and numeric record encoding/decoding. |
| `construction.jl` | Array conversion, metadata validation, and `touchstone_file`. |
| `headers.jl` | Header keyword recognition and option, reference, information, and mixed-mode parsing. |
| `parsing.jl` | File loading, parser state, and network/noise section boundaries. |
| `writing.jl` | Stream output, record formatting, and atomic file replacement. |

The reader frames frequency records in reusable buffers. Both physical-data
parsing and the raw-record helper use the same framing logic. Numerical
conversion is shared by incremental parsing and whole-vector conversion.
Decoded blocks are consolidated once, using declared counts only after enough
records have arrived to bound allocation relative to the input.

Construction and parsing share physical-value and mixed-mode checks. Stream
writers validate every record before emitting bytes; file saves validate
records while writing a temporary file. Construction and writing reuse a
record buffer. Parsed objects retain only the physical network arrays.

The file boundaries do not introduce submodules or separate version-specific
implementations. Keep shared numerical rules in `conversion.jl`, metadata
rules in `construction.jl`, and text syntax in the reader, header, parser,
and writer files. Internal calls use the private reader operations rather
than extending `Base` for `TouchstoneReader`.
