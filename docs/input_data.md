# Input data

Everything the drivers read. All items live in the folder given by `caseRoot`,
except the streamline files, which live in `caseRoot/model.sim/<caseName>`
(rename `model.sim` to whatever your simulator case directory is called).

No field data are distributed with this repository. The formats below are the
ones produced by the workflow used in the manuscript (Petrel RE model + Intersect
simulation + MATLAB/MRST post-processing), but any simulator able to write
Eclipse-style grids and `SLN` streamlines can be used.

---

## 1. `PERM_iter.GRDECL` — current permeability field

Eclipse-format (GRDECL) file containing at least

| Keyword | Description |
| --- | --- |
| `PERMX` | horizontal permeability, mD (modified by the inversion) |
| `PERMY` | horizontal permeability, mD (kept equal to `PERMX` in the reported applications) |
| `NTG` | net-to-gross ratio |

plus the grid geometry (`SPECGRID`, `COORD`, `ZCORN`, `ACTNUM`; `--` comments and
`INCLUDE`-style constructs are handled by MRST's reader). The geometry must be
present because the grid is built with `processGRDECL` + `computeGeometry`.

Local grid refinement (`CARFIN` blocks, as written by Petrel) is detected
automatically: streamline cells recorded in refined cells are mapped back onto
their parent cells of the global grid (`lgrcell2glocell`).

`PERMX`/`PERMY` are clamped to `[PERM_min, PERM_max]` (default 0.01–800 mD)
before use, and the updated field is written back to `PERM_outpath`; when that
equals `PERM_path` a `.bak_<timestamp>` copy is created first.

## 2. `SW_iter.GRDECL` — current initial water-saturation field

GRDECL file containing

| Keyword | Description |
| --- | --- |
| `SWAT` | initial water saturation, fraction (modified by the inversion) |
| `NTG` | net-to-gross ratio |
| `ACTNUM` | optional; when absent the active mask is taken as `NTG > 0` |

Grid geometry as in item 1. Values are clipped to `[SW_min, SW_max]`
(default 0.01–0.999883, the latter matching the simulator deck).

## 3. Streamline files — `caseRoot/model.sim/<caseName>`

The simulator case directory holds the Eclipse **unformatted** streamline output:

* `<caseName>.SLNSPEC` — metadata. Fields seen in practice: `RESTART`,
  `EXTENT`, `NAMES`, `MAPAXES`, `GRIDUNIT`, `MAPUNITS`, `RADIAL`.
* `<caseName>.SLN0001`, `.SLN0002`, … — one file per reporting step, with fields
  `INTEHEAD`, `GEOMETRY`, `GEOMINDX`, `ID_BEG`, `ID_END`, `ID_CELL`, `TIME_BEG`,
  `IFRACRES`, `PFRACRES`, `PFRACWAT`, `PFRACOIL`, `PFRACGAS`, `PRESSURE`,
  `SWAT`, `SGAS`, `RS`, `RV`, `FLORES`, `FLRWAT`, `FLROIL`, `FLRGAS`.

They are read with `readEclipseOutputFileUnFmt` and reshaped into a MATLAB
struct array by [`../src/file2Streamline.m`](../src/file2Streamline.m), whose
fields are `BEGIN, END, GEOMETRY, IFRACRES, PFRACRES, PFRACOIL, PFRACWAT, SO, SW,
FR, FW, FO, CELL, MEANX, MEANY, MEANZ, MEANSO, MEANSW, MEANSODSW, TOF, TotalTOF,
MINX, MINY, MINZ`. The snapshot date is taken from `INTEHEAD` (year/month/day).

`caseName` must match the run name appearing in the `wcut` file (item 4);
otherwise the driver stops with an explicit error listing the block titles it
found, instead of silently falling back to another run.

The number of `.SLN####` files defines the number of snapshots; only those
within `sl_years` years of the current time are used.

## 4. `wcut` — water-cut histories (permeability inversion)

A plain-text file (no extension) holding several concatenated blocks. Each block
starts with a line containing the string `SUMMARY OF RUN`. For a block whose
marker is on line `h`:

| Line | Content |
| --- | --- |
| `h` | block title — must contain `caseName` for the simulated block, and `observed` (case-insensitive) for the field-history block |
| `h+3` | number of reporting steps (first integer on the line) |
| `h+6` | well names; **data columns start from the 3rd token** (the first two are labels) |
| `h+11` | first date line, followed by one line per reporting step |

Each data line is read as: `date`, `step`, `cumulative days`, then one water-cut
value per well. `undef` is read as 0 and `-1` as 0. Dates may use the Chinese
locale format (`01-1月-1995`) — parsed explicitly — or ISO style.

If the file contains **no** `SUMMARY OF RUN` markers (a minimal export holding
one simulation plus the observed history), the driver falls back to the six line
indices in `wcut_fixed_cols = [w_c_l d_c_s d_c_e w_o_l d_o_s d_o_e]`
(default `[7 12 310 318 323 621]`), i.e. simulated names/data start/data end,
then observed names/data start/data end. The active mode is printed at start-up.

## 5. `swat_mismatch` — saturation-mismatch series (saturation inversion)

A plain-text file (no extension) with a fixed layout:

| Line | Content |
| --- | --- |
| 4 | number of reporting steps `mis_nsteps` (first integer on the line); if absent, falls back to `numel(file) - 11` |
| 7 | well names; **data columns start from the 3rd token** |
| 12 … 11+`mis_nsteps` | one line per time step: `date`, then one mismatch value per well |

`undef` and `-1` are read as 0. Rows whose number of values does not match the
well-name row are reported with a warning and skipped; if no valid row remains,
the driver stops with an explicit error. A trailing end-of-file artefact of
`readtxtfile` is skipped harmlessly.

## 6. Not required

Relative-permeability tables (`Krw.xlsx`) and fluid viscosities are **not** read.
The fractional-flow curve used by the back-projection is obtained from the
streamline records themselves (`FW`, `SO`, `SW` fields written by the
simulator), so no saturation-function table has to be supplied.

---

## What the drivers write

| File | Content |
| --- | --- |
| `PERM_iter.GRDECL` | `PERMX` updated by the streamline-multiplier projection (grid geometry is re-written too) |
| `SW_iter.GRDECL` | `SWAT` updated by the back-projection of the water-cut mismatch |
| `perm_inversion_summary_iter<NN>.txt` | per-well table: `well, t_sim, t_obs, E_bt, E_bt_soft, E_wc, drive, N_cand, M_star, df_line, df_obs, Lambda_f, wc_err, snapshot, osc_damped` |
| `well_update_state.mat` | per-producer state carried between iterations (previous correction sign, used by the oscillation damper) |
| diagnostic figures | written only when `make_plots = true` |

All output files are written next to `PERM_outpath` / `SW_writepath`.

> **Debug switch.** By default `write_slnmask_to_poro = false`, so the streamline
> visit count is *not* written to the output. Setting it to `true` stores that
> count in the `PORO` keyword of the output GRDECL, which would overwrite the
> porosity of the model if the deck includes the file wholesale — use it only
> for inspection, never for a simulation run.
