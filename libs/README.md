# Bundled third-party library — MRST (trimmed)

This folder contains a **trimmed copy of MRST 2024b**, the MATLAB Reservoir
Simulation Toolbox by SINTEF Digital (Mathematics and Cybernetics).

* Upstream project: <https://www.mrst.no/> — <https://github.com/SINTEF-AppliedCompSci/MRST>
* License: **GNU General Public License v3.0** — see `mrst/COPYING`
* Version: release **2024b**
* Vendored on: 2026-10-10

## Why it is bundled

The drivers in `src/` call five MRST functions:

| Function | Origin inside MRST |
|---|---|
| `readGRDECL` | `utils/inout/eclipse/deckinput_simple/` |
| `writeGRDECL` | `utils/inout/` |
| `processGRDECL` | `gridprocessing/` |
| `computeGeometry` | `gridprocessing/` |
| `readEclipseOutputFileUnFmt` | `modules/deckformat/resultinput/` |

Rather than asking the user to download and install the whole toolbox (≈91 MB,
4 283 files, of which the vast majority are unrelated physics modules), this
repository ships the smallest self-contained subtree that provides those five
functions, so `git clone` gives a working installation with no extra downloads.

## What is included / removed

**Included** (unmodified, byte-for-byte as released):

```
mrst/utils/                 % core utilities, incl. inout and 3rdparty/matlab_bgl
mrst/gridprocessing/        % processGRDECL, computeGeometry, ...
mrst/params/                % physical/fluid parameter containers
mrst/plotting/              % figure helpers used by the above
mrst/solvers/               % linear solvers referenced by core
mrst/modules/deckformat/    % readEclipseOutputFileUnFmt + private helpers
mrst/COPYING                % GPL-3.0
mrst/README.txt, Contents.m
```

**Removed**: everything under `modules/` except `deckformat` (AD black-oil,
CO2 storage, geomechanics, multiscale, upscaling, … — none of which is touched
by the five entry points), plus the example datasets.

**Excluded from the MATLAB path** (though still present in the tree, exactly as
MRST itself does in its `startup.m`): `utils/octave_only` — Octave-only shims
that shadow MATLAB built-ins — and `utils/3rdparty`, which MRST registers
separately. `../startup.m` at the repository root reproduces this logic.

## Completeness check

The transitive dependency closure of the five entry points was computed over
the full MRST tree and contains **35 MRST functions, 0 of which are missing from
the subtree above**. The copy was additionally exercised against real field data
(`processGRDECL` + `computeGeometry` on a 100 × 100 × 120 = 1.2 M cell grid, and
`readEclipseOutputFileUnFmt` + `file2Streamline` on Intersect `.SLNSPEC` /
`.SLNxxxx` files yielding 3 000 streamlines); see `../docs/dependencies.md`.

## Using your own MRST instead

Delete `libs/mrst` and put a full MRST installation on the MATLAB path instead —
the drivers only ever call the five functions listed above, so any MRST release
that provides them (2021b or later) works.

## License note

MRST is GPL-3.0. This repository as a whole is therefore released under
GPL-3.0 as well (`../LICENSE`). The bundled subtree is redistributed
unmodified; all MRST copyright notices are preserved.
