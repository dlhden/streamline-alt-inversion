# Dependencies

## 1. Summary

| Component | Role | Where it comes from |
|---|---|---|
| **MATLAB** R2020b or later | runtime | MathWorks (commercial) |
| **MRST 2024b** (trimmed) | Eclipse grid I/O and grid geometry | bundled in `libs/mrst`, GPL-3.0 |
| **Intersect** (or any Eclipse-compatible simulator) | generates the streamline (`.SLN*`) and grid (`GRDECL`) files | Schlumberger (commercial) — *not* required to read the code, only to produce the input files |

No other toolbox or third-party dependency is used. Microsoft Excel **is**
required on Windows for one input file: the relative-permeability table
`Krw.xlsx` is read with `xlsread` (the current algorithm does not consume the
curve derived from it, but the read is executed at start-up — see
[`input_data.md`](input_data.md) §6 for the two one-line workarounds).

MATLAB language features used by the drivers: `string`/`""` string literals,
`datetime` (with an explicit `zh_CN` locale in the C2 driver), `contains`,
`regexp`, `strsplit`/`split`, `smoothdata`, `accumarray`, `arrayfun`, `waitbar`,
`tanh`, `filesep`. All are base-MATLAB and available since R2020b
(`smoothdata` since R2017a).

## 2. MRST

### 2.1 Functions called

The drivers call exactly five MRST functions:

```
readGRDECL                (utils/inout/eclipse/deckinput_simple)
writeGRDECL               (utils/inout)
processGRDECL             (gridprocessing)
computeGeometry           (gridprocessing)
readEclipseOutputFileUnFmt(modules/deckformat/resultinput)
```

plus `file2Streamline.m`, which is **this repository's own** helper
(`src/file2Streamline.m`) and only uses base MATLAB.

### 2.2 The bundled trimmed copy

`libs/mrst` is MRST 2024b with everything under `modules/` removed except
`deckformat`, and the example datasets dropped — 5.5 MB / 627 files instead of
91 MB / 4 283 files. Files that remain are byte-for-byte identical to the
upstream release; see [`../libs/README.md`](../libs/README.md).

**Dependency-closure verification.** Starting from the five entry points, every
identifier appearing in each function body (comments and string literals
stripped) was matched against an index of all `.m` files in the *full* MRST tree
and followed recursively:

```
MRST functions in the transitive closure : 35
of which missing from libs/mrst          :  0
```

So the subtree is self-contained for the drivers' usage — no MRST function is
reached that is not present.

**Runtime verification** (MATLAB R2024b, real field data):

| Call | Input | Result |
|---|---|---|
| `readGRDECL` | `flow.GRDECL`, 7.9 MB | `cartDims = [100 100 120]`, 1 200 000 `PERMX`/`ACTNUM` values, 3.2 s |
| `processGRDECL` + `computeGeometry` | the above | **1 200 000 cells**, 23.6 s |
| `writeGRDECL` → `readGRDECL` | 1.2 M-cell field | round-trip OK, 13.0 s |
| `readEclipseOutputFileUnFmt` | `CASE.SLNSPEC` | 7 fields (`RESTART, EXTENT, NAMES, MAPAXES, GRIDUNIT, MAPUNITS, RADIAL`) |
| `readEclipseOutputFileUnFmt` | `CASE.SLN0002` | 20 fields (`INTEHEAD, GEOMETRY, GEOMINDX, ID_*, TIME_BEG, PFRACRES, PFRACWAT, SWAT, …`) |
| `file2Streamline` | the above | **3 000 streamlines** with `CELL/TOF/SW/FR/FW/BEGIN/END` populated |

`examples/test_toolbox.m` re-runs a reduced version of these checks on the
bundled miniature example files.

### 2.3 Path setup

Run `startup.m` at the repository root:

```matlab
>> cd streamline-alt-inversion
>> startup
>> main_SL_inversion_C2
```

It adds `src/`, `examples/` and the bundled MRST subtree to the MATLAB path,
excluding `octave_only` and `3rdparty` exactly as MRST's own `startup.m` does.

If you prefer your own MRST installation, delete `libs/mrst` and add MRST to the
path yourself; the drivers do not care which copy provides the functions.

## 3. Simulator side (input data only)

The workflow assumes the current model is simulated with a streamline-capable
Eclipse-compatible simulator (Intersect in the published applications) that can
export:

* `GRDECL` property files — the drivers read `PERMX`, `PERMY`, `PERMZ`, `NTG`,
  `ACTNUM` from the permeability file and `SWAT`, `NTG`, `ACTNUM` from the
  saturation file, plus the grid geometry (`SPECGRID`, `COORD`, `ZCORN`);
* Eclipse **unformatted** streamline files `<case>.SLNSPEC` and
  `<case>.SLN0001…`, read by MRST's `readEclipseOutputFileUnFmt` and reshaped by
  [`../src/file2Streamline.m`](../src/file2Streamline.m);
* producer water-cut history as plain text (`wcut`, with the simulated and the
  observed block in one file — the mismatch is their difference, computed by the
  driver);
* the relative-permeability table as `Krw.xlsx`.

The export recipes (including the Petrel side) and the exact layouts are in
[`input_data.md`](input_data.md).

The `GRDECL` readers are simulator-agnostic; only the `.SLN*` reader assumes the
Eclipse unformatted layout that Intersect writes.
