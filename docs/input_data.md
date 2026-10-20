# Input data: what to prepare and where it comes from

This page is the practical counterpart of [`../README.md`](../README.md) §5: it
lists **every input item**, tells you **how to produce it** (Petrel export, case
model, production data) and documents the **exact file layout** the drivers
expect.

No field data are distributed with this repository. The formats below are the
ones produced by the workflow used in the manuscript (Petrel RE model →
Intersect simulation with streamline output → MATLAB/MRST post-processing); any
simulator that can write Eclipse-style GRDECL grids and Eclipse **unformatted**
`SLN` streamlines can be used instead.

---

## 0. Checklist

| # | Item | File name | Lives in | Produced by |
| --- | --- | --- | --- | --- |
| 1 | current permeability field | `PERM_iter.GRDECL` | `caseRoot` | Petrel property export (§1) |
| 2 | current initial water saturation | `SW_iter.GRDECL` | `caseRoot` | Petrel property export (§2) |
| 3 | streamlines of the current run | `<caseName>.SLNSPEC`, `<caseName>.SLN0001 …` | `caseRoot/model.sim/<caseName>/` | the **simulator** (§3) |
| 4 | water-cut histories (simulated + observed) | `wcut` | `caseRoot` | simulator well history + field production data (§4) |
| 5 | relative-permeability table | `Krw.xlsx` | `caseRoot` | core / SCAL data (§5) |

`caseRoot` and `caseName` are the two lines you set in the driver's
configuration block. Items 1, 2 and 3 must all describe the **same** run/state:
iteration `N` reads the fields used by run `N` and the streamlines written by
run `N`.

There is no sixth item: the water-cut mismatch that drives the saturation update
is not an input at all — the driver subtracts the observed block of `wcut` from
the simulated block (§4.4).

---

## 1. Permeability field — `PERM_iter.GRDECL` (from Petrel)

**Keywords read by the driver**

| Keyword | Description |
| --- | --- |
| `PERMX` | horizontal permeability, mD (**modified** by the inversion) |
| `PERMY` | horizontal permeability, mD (**modified** with the same multiplier) |
| `PERMZ` | vertical permeability, mD (optional; modified with the same multiplier when present) |
| `NTG` | net-to-gross ratio |
| `ACTNUM` | active-cell flag (used for the grid build and for reporting) |
| `SPECGRID`, `COORD`, `ZCORN` | grid geometry — **required**, the grid is built with `processGRDECL` + `computeGeometry` |

**How to export from Petrel**

1. Open the model and go to the *Models* pane (3D grid).
2. Right-click the **grid** (or the property folder) → **Export…**, and pick the
   Eclipse/GRDECL format. Depending on the Petrel version this entry is called
   *"Eclipse keywords (GRDECL)"*, *"Simulation grid / properties"*, or it appears
   under **File → Export → Simulation data** and, in the reservoir-engineering
   workflow, under **Simulation → Export**.
3. In the export dialog tick the keywords **`PERMX`, `PERMY`, `PERMZ`, `NTG`**
   and make sure the grid geometry (`SPECGRID`, `COORD`, `ZCORN`, `ACTNUM`) is
   included.
4. Save it as `PERM_iter.GRDECL` in `caseRoot`.

**Alternatives.** (a) If your Intersect/Eclipse deck already contains these
keywords, export/copy them together with the `GRID` section into one GRDECL file
— that is all the driver needs. (b) The MRST copy bundled here
(`readGRDECL`/`writeGRDECL`) can read and re-write GRDECL files if you prefer to
assemble the file in MATLAB.

**Only the first iteration needs this export.** From iteration 2 on the driver
writes the updated `PERM_iter.GRDECL` itself; you only have to import it back
into the simulator (or into Petrel) before the next run.

`PERMX`/`PERMY`/`PERMZ` are clamped to `[PERM_min, PERM_max]` (default
0.01–800 mD) before use; when the output path equals the input path a
`.bak_<timestamp>` copy is created first.

## 2. Initial water saturation — `SW_iter.GRDECL` (from Petrel)

**Keywords read by the driver**

| Keyword | Description |
| --- | --- |
| `SWAT` | initial water saturation, fraction (**modified** by the inversion) |
| `NTG` | net-to-gross ratio |
| `ACTNUM` | optional; when absent the active mask is taken as `NTG > 0` |

**How to export from Petrel**: exactly as in §1 (same dialog), but tick
**`SWAT`** and **`NTG`**, and save as `SW_iter.GRDECL`.

`SWAT` must be the **initial** water saturation of the state you are inverting
(for iteration 1: the static initial condition your deck starts from — a
J-function / capillary-pressure height model, a water-saturation model, or a
`SWATINIT`-style field). Values are clipped to `[SW_min, SW_max]`, which **you**
must set in the configuration block (README §0).

As for the permeability, from iteration 2 on the driver rewrites this file.

## 3. Streamlines — exported by the **case model** (mandatory)

The whole method is driven by the streamline snapshots, so the simulation run
must write them:

* switch the streamline output on in the run (Intersect writes the Eclipse
  **unformatted** files `<caseName>.SLNSPEC` and `<caseName>.SLN0001 …
  .SLN####`; other Eclipse-compatible simulators with a streamline module write
  the same family of files);
* dump the snapshots with the same frequency as the production data — monthly in
  the published applications. **One `.SLN####` file = one snapshot;**
* copy them into

  ```
  caseRoot/model.sim/<caseName>/<caseName>.SLNSPEC
  caseRoot/model.sim/<caseName>/<caseName>.SLN0001
  caseRoot/model.sim/<caseName>/<caseName>.SLN0002
  ...

  ```

  rename `model.sim` to your own simulator case directory name, and set
  `caseName` to the run name (the driver derives the streamline folder path from
  it, see the `SLN_headpath` line).
* **`caseName` must also appear in the title of the simulated block of `wcut`**
  (§4). If it does not, the C2 driver lists the block titles it found and stops
  with an explicit error, instead of silently using the wrong run.

**Fields read** (through
[`../src/file2Streamline.m`](../src/file2Streamline.m)):
`INTEHEAD` (snapshot date), `ID_BEG`, `ID_END`, `ID_CELL`, `IFRACRES`,
`PFRACRES`, `PFRACWAT`, `PFRACOIL`, `FLORES`, `FLRWAT`, `FLROIL`, `SWAT`, `SO`,
and the geometry arrays. If your simulator writes a different keyword set, adapt
`file2Streamline.m` accordingly.

**Local grid refinement** (`CARFIN`, as written by Petrel) is detected
automatically and streamline cells inside refined cells are mapped back to their
parent global cells (`lgrcell2glocell`), so the two properties files and the
streamlines may live on a refined grid without extra work.

## 4. Water-cut histories — `wcut`

A plain-text file (no extension) holding **two blocks**: the simulated water cut
of the current run and the observed (field) water cut. Both use the same layout.

### 4.1 Layout

For a block whose title line (containing `SUMMARY OF RUN`) is line `h`:

| Line | Content |
| --- | --- |
| `h` | block title — **must contain `caseName`** for the simulated block and **`Observed`** (case-insensitive) for the field block |
| `h+3` | number of reporting steps (the first integer on the line is used) |
| `h+6` | well names; the **first two tokens are labels**, the names start at token 3 |
| `h+11` … | one line per reporting step: `date`, `step`, `cumulative days`, then one water-cut value per well |

`undef` and `-1` are read as 0. Dates may be ISO-style or Chinese-locale
(`01-1月-1995`) — the C2 driver parses the Chinese format explicitly.

A ready-to-use skeleton is
[`../examples/wcut_template.txt`](../examples/wcut_template.txt) (the "free
line" rows are ignored, the numbered rows are the ones that matter).

### 4.2 How the drivers find the two blocks

* **C2 driver** — the blocks are located automatically from their
  `SUMMARY OF RUN` markers; the simulated block is matched by `caseName`, the
  observed block by the string `Observed`. This is the mode to use when your
  export contains several runs (e.g. an earlier scheme plus the current run).
* **WLW driver** — the export has no markers, so the six line numbers are given
  in the configuration block:

  ```matlab
  wcut_fixed_cols = [names_sim  start_sim  end_sim  names_obs  start_obs  end_obs];
  ```

  For the published WLW export these are `7 / 12 / 310 / 318 / 323 / 621`
  (299 monthly steps per block; the two blocks start at lines 1 and 312, which
  is consistent with the `h+6` / `h+11` offsets above). **Count the lines of
  your own export and update this vector** — if the numbers are wrong the driver
  silently reads the wrong rows, so this is worth a careful check.

### 4.3 Producing the file

* *Simulated block*: export the well water-cut history of the current run from
  the simulator (well summary / history table; one column per producer,
  monthly). Keep it in fraction, not percent.
* *Observed block*: export the field production history of the same wells over
  the same dates (producer water cut, monthly).
* Concatenate the two exports into one file named `wcut` (no extension) in
  `caseRoot`.

### 4.4 The mismatch is built from these two blocks

Nothing else has to be exported. The saturation update is driven by

```
Δf_w(k, j) = f_w^sim(k, j) − f_w^obs(k, j)        (simulated − observed water cut)
```

which the driver forms itself, well by well and date by date, and keeps in
memory. Three rules it follows:

* **Wells are matched by name.** The two blocks need not contain the same wells
  in the same order — in the main case the simulated block has 1005 wells and the
  observed one 993 (992 shared). The driver reads the simulated block by its
  original column index, so no well is silently paired with its neighbour.
* **A cell with `undef` on either side is dropped** (stored as 0, which the
  update skips), so missing observations never enter as a spurious mismatch.
* **Trailing dates with no observed data are stripped.** If the last reporting
  date of the observed block is a placeholder (all `undef`, or all zero while the
  previous date is not), differencing it would turn `f_w^sim` into the mismatch;
  the driver therefore walks back from the end and drops such dates. In the main
  case that leaves 350 of the 351 reporting dates.

## 5. Relative-permeability table — `Krw.xlsx`

An Excel workbook with **three columns**:

| Column | Content |
| --- | --- |
| 1 | water saturation `S_w` |
| 2 | water relative permeability `k_rw(S_w)` |
| 3 | oil relative permeability `k_ro(S_w)` |

The driver converts it to a fractional-flow curve with the viscosities `miuo`
and `miuw` of the configuration block.

> **Note.** The current algorithm does not consume the derived curve (it is kept
> from the original research codes, together with `firstmis_grid`,
> `endcell_wellid` and `endtime_weight`), **but the file is still read at
> start-up** with `xlsread`. So either provide the file, or comment out the "读取
> 相渗曲线" block in Part 1. Without Excel installed, replace `xlsread` by
> `readmatrix` (one line).

---

## 6. What the drivers write

| File | Content |
| --- | --- |
| `PERM_iter.GRDECL` | `PERMX`, `PERMY`, `PERMZ` (when present), `NTG` after the streamline-multiplier projection |
| `SW_iter.GRDECL` | `SWAT`, `NTG` after the back-projection of the water-cut mismatch (`PORO` only if `write_slnmask_to_poro = true`, for diagnostics) |
| `perm_inversion_summary.txt` | per-well table: `well, t_sim, t_obs, E_bt, E_bt_soft, E_wc, E_tot, N_cand, M_star, df_line, df_obs, Lambda_f, wc_err` |
| diagnostic figures | only when `make_plots = true` |

The written GRDECL files are **property files** — they contain the keywords the
driver read, not the grid geometry. Import them as property updates of the same
grid (or include them in the deck), otherwise the next simulation will not see
the update.

> **Debug switch.** With `write_slnmask_to_poro = false` (default) the
> streamline visit count is not written anywhere. Setting it to `true` stores
> that count in the `PORO` keyword of `SW_iter.GRDECL`, which would overwrite the
> porosity of the model if the deck takes `PORO` from that file — use it only for
> inspection.

---

## 7. Sanity checklist before the first run

1. `SPECGRID` in `PERM_iter.GRDECL` and `SW_iter.GRDECL` describe the same grid,
   and the cell count matches `numel(PERMX) == numel(SWAT)`.
2. The number of `.SLN####` files is ≥ 2 and their dates overlap the production
   history.
3. The simulated block of `wcut` carries the same name as the streamline folder
   (`caseName`), and its well names match those in `SLNSPEC`.
4. The observed block of `wcut` covers the same wells and (approximately) the
   same dates as the simulated block; the shared wells are what enters the
   inversion.
5. `TOF_times`, `SW_min`, `SW_max` are set for **your** case (README §0).
6. The driver prints, at start-up, which `wcut` blocks it used and how many
   streamlines it read — check those two lines first whenever the update looks
   wrong.
