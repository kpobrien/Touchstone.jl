# Changelog

## [0.2.0]

### Added

- Support Touchstone 1.1 per-port option-line resistances, including unequal-port
  G/H/Y/Z normalization and noise resistance normalized to port 1. Multiple
  option-line resistances identify version 1.1 on reading; a single resistance
  identifies version 1.0.
- Support Touchstone 2.1. Reading and writing preserve the selected version;
  `[Version]` accepts the literal argument `2.0` or `2.1`.
- Save a `TouchstoneFile` with `touchstone_save(filename, ts)`, retaining its
  representation, mixed-mode order, comments, information, and noise data.
- Accept one-based array views, frequency ranges, and real scalar/vector numeric
  keywords, with checked conversion to Float64/ComplexF64 storage.
- Support LF, CRLF, CR, a leading UTF-8 BOM, and Latin-1 input. Preserve comment
  and information text using compatible Latin-1/UTF-8 output encoding.
- Accept continued reference and mixed-mode declarations, and arbitrary record
  wrapping in version 2 input.

### Changed

- **Breaking:** `touchstone_save` preserves explicit filename extensions. When
  no extension is supplied, append `.sNp` for versions 1.0 and 1.1, and `.ts`
  for versions 2.0 and 2.1, where `N` is the number of ports. These are naming
  conventions; the Touchstone 2.1 specification permits `.ts` for all versions
  and allows other extensions. Request the full filename explicitly when a
  different extension is needed, including names such as `name.dat.s2p`.
- **Breaking:** Version 1.0 network parameters use physical units: `Z = z R`,
  `Y = y / R`, `H11 = h11 R`, `H22 = h22 / R`, `G11 = g11 / R`, and
  `G22 = g22 R`. Off-diagonal H/G entries and S parameters are unscaled.
  DB values describe the normalized magnitude. Remove application-side
  compensation for Touchstone.jl 0.1 normalization when upgrading.
- **Breaking:** Noise resistance (`noisedata[5:5:end]`) is in ohms, including for
  version 1. Noise frequencies remain in the file's frequency unit.
- **Breaking:** Reject invalid metadata, nonfinite values, negative or unordered
  frequencies, incomplete records, and inconsistent port/count data. Numbers
  require decimal syntax; counts require decimal integers. Version 2 requires
  an option line, port/frequency counts, `[Network Data]`, and `[End]`.
- **Breaking:** Remove the `TouchstoneFile.networkdata` field. Use `f` in Hz
  and `N` in physical units; writing uses their current values. Remove the
  `networkdata` argument from positional constructors, or use `touchstone_file`.
- **Breaking:** `TouchstoneFile` is parameterized by frequency and matrix storage
  types. Update code depending on its exact concrete type or Julia serialization
  layout.
- Validate metadata and every record before writing to caller-owned IO.
  `touchstone_save` replaces an existing file only after successful writing and
  close. See the README for filesystem semantics.
- Require Aqua 0.8 or later within the 0.8 series for package quality checks.

### Fixed

- Write `[Begin Information]` and `[End Information]` on lines of their own;
  0.1.3 wrote an information section that did not read back.
- Reject legacy network records containing a frequency without parameter pairs.
- Preserve existing comments without accumulating matching column labels on
  load/save cycles, and preserve caller-owned stream marks when reading,
  including on invalid input.
- Accept Float16 and Float32 version selectors in their original precision;
  reject adjacent unsupported values. Compare `.sNp` filename port counts
  independently of leading zeros.
- Preserve multibyte text at inline-comment boundaries and ignore additional
  option lines in continued reference and mixed-mode declarations.
- Validate mixed-mode port coverage, pairing, orientation, and reference
  impedances.
- Preserve precision for subnormal geometric means of unequal version 1.1 Z/Y
  references and for large finite polar angles. Use stable magnitude and DB
  calculations across the Float64 range.
- Reject unrepresentable values and frequency collapse during unit conversion.
  Use RI or MA for exact zero and Full for matrices without transpose symmetry.
- Emit one version 1 matrix row per line for three/four ports; larger rows wrap
  after four parameter pairs.
- Name the parameter entry and frequency, or the noise record, of a value the
  writer refuses, and the file value and unit of a frequency that overflows
  in Hz on reading.

### Performance

- Reserve matrix-index storage once, avoiding intermediate vector growth
  during construction, parsing, and writing.
- Cache port-number strings and write column-label text directly, reducing
  formatting overhead and allocation for files with many ports.
- Store uniform normalization once for S parameters, version 2 files, and
  equal-reference version 1 Z/Y data, avoiding a per-entry table during
  construction, parsing, and writing.
- Decode network records incrementally without retaining a complete encoded
  dataset. Consolidate decoded blocks once, and bound allocation from declared
  counts by the data received.
- Buffer file reads and construct lines without an intermediate byte vector.
  Reuse numeric-line storage and iterate over decimal tokens without
  regular-expression splitting or case conversion of numeric records.
- Reuse numeric and text buffers for network/noise output, including Float64
  formatting storage. Direct writes avoid a complete encoded network snapshot.
- Retain only physical network data in `TouchstoneFile`. Validate construction
  with one reusable record buffer instead of a complete encoded dataset.
- Encode file-save records once while writing the temporary file, preserving
  destination safety and preflight validation for caller-owned streams.
- Normalize and convert parameters without frequency-slice temporaries, and
  resolve noise frequency units once during validation.
