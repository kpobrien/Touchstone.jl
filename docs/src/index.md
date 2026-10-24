# Touchstone.jl

Read and write Touchstone 1.0, 1.1, 2.0, and 2.1 network-parameter files.

## Quick start

```julia
using Touchstone

ts = touchstone_load("network.s2p")
frequencies = ts.f                 # Hz
parameters = ts.N                 # port × port × frequency

touchstone_save("network.ts", ts)
```

`N` contains physical network parameters: S is dimensionless, Z is in ohms,
and Y is in siemens. H/G mix impedance, admittance, and dimensionless entries.
The reader converts normalized version 1 values to these units. The
`frequencyunit` field describes file frequencies; it does not change the Hz
units of `f`. Noise frequencies retain the file unit, and noise resistance is
in ohms.

Saving a `TouchstoneFile` retains its version, representation, and metadata,
including mixed-mode order and noise data. Use the array form when selecting
a new file representation explicitly.

Use `Touchstone.touchstone_parse(io)` and `Touchstone.touchstone_write(io, ts)`
for streams. The writer uses the current `f`, `N`, and metadata. RI and MA
can represent exact zeros; finite DB text cannot.

## Versions and references

Version 1.0 uses one reference resistance `R` for all ports. Version 1.1
supports a resistance per port on the option line. To write the single-ended
two-port data above as version 1.1 while retaining its references:

```julia
touchstone_save("network-v1.1.s2p", ts.f, ts.N;
    version=1.1, parameter=ts.parameter, reference=ts.reference, format="RI")
```

The supplied references describe `N`. Changing `R` or `reference` does not
renormalize S parameters. For example, use `reference=[50,75]` only when the
supplied S data already uses those references. Likewise, `mixedmodeorder`
describes the supplied data; it does not perform a mixed-mode transformation.

For 1.1, `reference[1]` supplies `R` and the normalization of noise resistance.
Multiple option-line resistances identify version 1.1 on reading. A single
resistance, including a one-port file, is reported as version 1.0. Versions 2.0 and 2.1
use `[Reference]` for port references and store non-S parameters directly in
physical units. Select `version=2.1` to emit `[Version] 2.1`; both version 2
markers use the same data rules. Reading preserves the declared version.

Explicit filename extensions are preserved. When no extension is supplied,
`.sNp` is appended for versions 1.0 and 1.1, and `.ts` for versions 2.0 and 2.1,
where `N` is the number of ports. These defaults follow common naming
conventions; the Touchstone 2.1 specification permits `.ts` for all versions
and allows other extensions.

## API

The supported interface consists of `TouchstoneFile`, `touchstone_file`,
`touchstone_load`, `touchstone_parse`, `touchstone_save`, and `touchstone_write`.
Only load/save are exported; use the `Touchstone.` prefix for other names.
See the [API reference](reference.md) for arguments, defaults, units, and
validation. The implementation helpers in the internal reference may change.

The [README](https://github.com/kpobrien/Touchstone.jl/blob/main/README.md)
includes normalization formulas and file-writing guarantees. See the
[changelog](https://github.com/kpobrien/Touchstone.jl/blob/main/CHANGELOG.md)
for migration requirements.
