# streamline-alt-inversion

MATLAB implementation of the **streamline-based alternating inversion of initial
water saturation and permeability** for automatic history matching of
large-scale multi-well waterflood reservoirs.

This repository accompanies the manuscript:

> **Multi-Parameter Fine-Scale Alternating Inversion Method for Large-Scale
> Multi-Well Waterflooding Reservoirs**
> Lihui Deng, Han Zhang, Chengcheng Niu, Xuri Huang, Hu Jia, Wei He, Li Yang
> *Petroleum Science* (submitted; citation to be updated upon publication)

```bash
git clone https://github.com/dlhden/streamline-alt-inversion.git
```

Everything needed to **run** the code is included (MRST is bundled, see §3) —
you need MATLAB, the input files listed in §5, and (only to *generate* those
files) a streamline-capable simulator.

---

## 0. Read this first

Three things are needed before the first run: **(0.1) the input data items**,
**(0.2) a short list of parameters you must calibrate on your own reservoir**
(the rest can be copied from the paper), and **(0.3) the iteration procedure**.
Sections 5–8 give the details; this section is the checklist.

### 0.1 What data you need

Everything lives in the folder `caseRoot`, except the streamlines, which live in
`caseRoot/model.sim/<caseName>/`. Five mandatory items plus one optional, of
which **only two are static**:

| # | Item | File | Produced from | Redone every iteration? |
| --- | --- | --- | --- | --- |
| 1 | current permeability field | `PERM_iter.GRDECL` (`PERMX`,`PERMY`,`PERMZ`, `NTG`, and the grid geometry) | Petrel property export, or the deck itself (§5.1) | **No** — export once (static/geological field); afterwards the driver writes it |
| 2 | current initial water saturation | `SW_iter.GRDECL` (`SWAT`, `NTG`) | the model's initial-condition workflow (J-function, S-height, …) (§5.2) | **No** — export once; afterwards the driver writes it |
| 3 | streamlines of the current run | `model.sim/<caseName>/<caseName>.SLNSPEC` + `.SLN0001 …` | **the simulator**, with streamline output switched on (§5.3) | **Yes** — one dump per simulation |
| 4 | water-cut histories | `wcut` | simulated block: the run's well water-cut table; observed block: field production history (§5.4) | **Yes** — the simulated block |
| 5 | relative-permeability table | `Krw.xlsx` (`Sw`, `krw`, `kro`) | core / SCAL data (§5.6) | No (must exist — the driver reads it — but it only builds `f_w(S_w)` for diagnostics; the update itself does not consume it) |
| 6 *(optional)* | water-cut mismatch series | `swat_mismatch` | simulated − observed water cut, per well per reporting date (§5.5). **Only read when `mis_source="file"`; set `mis_source="internal"` and it is computed from item 4** | Yes (only in `"file"` mode) |

**Item 6 can be deleted from your workflow.** We checked the file against the
water-cut tables of the same run, well by well and date by date: its content *is*
`Δf_w = f_w^sim − f_w^obs`, the difference of the two blocks inside `wcut`
(Pearson 0.981, median absolute difference 4×10⁻⁴ — the residual is the
truncation of the exported digits). So `mis_source="internal"` reconstructs it
from item 4 with no Petrel export. Switching to `"internal"` also widens the well
set to the full intersection of the two blocks (993 vs 927 wells in the main
case), so it is not bit-identical to the `"file"` mode that produced the
manuscript numbers — keep the default `"file"` if you want to reproduce them.

A note on the name: `swat_mismatch` does **not** contain a saturation mismatch.
It is a water-cut mismatch, inherited from a Petrel objective-function export
(`HM_WCT`, unit `sm3/sm3`). We verified this two ways: the paired differences
above, and the fact that every one of the 155,560 paired cells satisfies
`Δf_w + f_w^obs ≤ 1` — impossible for a saturation difference de-projected from
the fractional-flow curve, which would reach `1 − S_wc` at most.

No field data are distributed with this repository, and no item 3–4 can be
reconstructed from the other ones alone: the streamline dump is a simulator
output that must be requested when the case is run.

### 0.2 Which parameters must be calibrated, and which you can copy

The drivers ship with the values used in the paper. They fall into three
classes — the full table is in §8:

**Class A — must be derived from your own reservoir. The paper values are the
two published cases, *not* transferable defaults.**

| Parameter | Why it cannot be copied | How to set it | Paper |
| --- | --- | --- | --- |
| `TOF_times` | streamline TOF is **dimensionless**; the code converts it to physical time with `SW_TOF = TOF × TOF_times` (≈ days) to locate the water front at a given date. The factor depends on the simulator's streamline time step / output units. The two cases here differ by a factor of **13** (1500 vs 20000). A wrong value shifts the whole back-projection window and the saturation update becomes meaningless. | run 1–2 iterations; check that the printed saturation change and the water-cut fit move in the right direction; if not, change the order of magnitude | 1500 (C2) / 20000 (WLW) |
| `SW_min`, `SW_max` | saturation clip bounds: `SW_min` is the connate water saturation (or the smallest value your model allows), `SW_max` is `1 − S_orw` or the deck's upper limit. `SW_max` above the deck limit gets truncated on the next run. | read them off your `SWOF`/`KRW` table and the deck | 0.01 / 0.999883 |
| `PERM_min`, `PERM_max` | geological bounds of the multiplier projection; they are the permeability range of *your* field | from the core/log permeability distribution | 0.01 / 800 mD |
| `miuo`, `miuw` | fluid viscosities used when building `f_w(S_w)` from `Krw.xlsx` | your PVT | 2.8 / 1 mPa·s |
| `wct_break_thr` | fallback breakthrough threshold; must sit above the noise floor of the observed water cut, otherwise shut-in / restart spikes are read as breakthrough | look at the observed water-cut noise of a few wells | 0.02 |
| `kappa_w` + `df_obs_mode` | the **calibrated pair** of §4 of the manuscript (Table 5): they fix the scale of the per-streamline hypothetical increment relative to the observed one. The optimum depends on the streamline density and on how strongly the observed water cut is smoothed. WLW: (0.5, two-sample window); main case: (1.5, `[t_b, t_e]`). Because `Δf ∝ a^κ` is monotone, κ does not change the *ranking* of streamlines, only the subset length — so a sub-optimal κ still works, it just makes the support longer (or collapses it onto one streamline). | scan κ ∈ {0.25, 0.5, 0.75, 1, 1.5, 2} × the two windows and keep the pair where the median `Δf_pre/Δf_obs` is closest to 1 **and** roughly half of the producers still get a non-degenerate subset (`M* < N_cand`); no new simulation is needed, see §8.1.1 | 0.5 + two-sample |
| `sl_years` | validity window of a streamline snapshot (years); tied to the snapshot cadence and to the length of the history | ≈ number of years you can trust one flow field; with annual snapshots the paper uses 6 | 6 |
| `wcut_fixed_cols` | line layout of *your* `wcut` export (WLW driver only; the C2 driver detects blocks automatically) | count the lines of your export header | `[7 12 310 318 323 621]` |
| `caseRoot`, `caseName` | your paths; `caseName` must equal both the streamline folder name and the title of the simulated block inside `wcut` | — | placeholders |

**Class B — copy the paper values.** They were used unchanged in both published
cases (two reservoirs, 1006 and ~1000 wells) and no sensitivity run in the
manuscript required changing them: `gamma_relax`, `gamma_decay`, `fit_tol`,
`swing_hi`, `swing_boost`, `e_bt_tol`, `e_wc_tol`, `w_bt`, `beta_weight`,
`eps_tau`, `eps_f`, `eps_df`, `jump_back`, `jump_fwd`, `chi_min`, `chi_max`,
`sw_front_min`, `alpha`, `max_vary`, `decay_times`, `sw_decay`, `mis_tol`,
`dedup_cells`, `normalize_cnt`, `soft_clip`, `sw_write_mode`, `sw_seg_weight`,
`sw_dedup_seg`, `fix_etot_combine`, `fix_break_fallback`, `mis_source`,
`mis_drop_last`.

**Class C — copy, then rescale if your discretisation differs.** These are
counts of grid cells or snapshots, so a much coarser / finer grid or a different
dump frequency needs a proportional change: `sw_end_cells` (5), `sw_end_frac`
(0.5), `sw_seg_maxlen` (150 cells), `sln_expand_nb` (2 snapshots).

### 0.3 How to operate it

```text
[once]  export PERM_iter.GRDECL + SW_iter.GRDECL  (items 1–2)
        switch the simulator's streamline output ON

per outer iteration n = 1, 2, … :
  1. run the simulator for this iteration
  2. export  wcut  (item 4);  swat_mismatch  (item 6) only if mis_source="file"
  3. MATLAB:  startup;  iter_index = n;  main_SL_inversion_C2
       -> PERM_iter.GRDECL, SW_iter.GRDECL, perm_inversion_summary.txt
  4. import both updated fields into the deck as property updates of the same grid
  5. n <- n + 1, go to 1
stop when the history-period water-cut fit stops improving; select the model on the
history fit only, then evaluate the prediction once (that is the protocol used in
the paper — the prediction is never used to choose the iteration)
```

```matlab
>> cd streamline-alt-inversion
>> startup                              % adds src/, examples/ and the bundled MRST
>> test_toolbox                         % optional self-check
>> edit src/main_SL_inversion_C2.m      % caseRoot, caseName, and the Class A parameters
>> main_SL_inversion_C2
```

What to watch on the console: the printed `gamma_eff`, the saturation step
`gain`, the saturation-change statistics, and the per-well list of frozen
producers with the reason. §7 explains how to read them.

---

## 1. What the code does

One outer iteration = **one** full-physics simulation (Intersect) followed by one
post-processing pass in MATLAB/MRST that produces **two** updated fields at once:

| Step | Output | Governing quantities |
| --- | --- | --- |
| Initial water-saturation update | `SW_iter.GRDECL` (`SWAT`) | producer water-cut mismatch, streamline geometry, method-of-characteristics back-projection |
| Permeability correction | `PERM_iter.GRDECL` (`PERMX`/`PERMY`/`PERMZ`) | breakthrough-time mismatch, post-breakthrough water-cut increment, minimum-streamline-subset selection |

Both updates are driven by the **same** streamline snapshot (the streamlines are
read only once per iteration). That is the point of the method: the
initial-saturation error is not silently absorbed by artificial permeability
changes, and the permeability correction is restricted to the dynamically
sufficient subset of streamlines whose cumulative hypothetical water-cut
increment reaches the observed post-breakthrough increment.

## 2. Repository layout

```
streamline-alt-inversion/
├── startup.m                             % adds src/, examples/ and libs/mrst to the MATLAB path
├── CHANGELOG.md                          % what changed between releases
├── src/
│   ├── main_SL_inversion_C2.m            % driver, main case  (C2 block, Ordos Basin)
│   ├── main_SL_inversion_WLW.m           % driver, second case (WLW block)
│   └── file2Streamline.m                 % reshapes Eclipse .SLN* records into MATLAB streamline structs
├── libs/
│   ├── README.md                         % provenance / trimming of the bundled MRST subset
│   └── mrst/                             % MRST 2024b (trimmed), GPL-3.0
├── examples/
│   ├── tiny.GRDECL                       % miniature Eclipse grid (format sample)
│   ├── tiny.SLNSPEC                      % miniature Eclipse unformatted result file
│   ├── wcut_template.txt                 % line-by-line template of the wcut file (§5.4)
│   ├── swat_mismatch_template.txt        % line-by-line template of the mismatch file (§5.5)
│   └── test_toolbox.m                    % self-check of the bundled toolbox
└── docs/
    ├── dependencies.md                   % what is used, versions, verification
    └── input_data.md                     % export recipes (Petrel / simulator) and file formats
```

The two drivers are **one and the same engine**: they share every algorithm,
every parameter value and every computation block, and differ only in
(1) the configuration block (read paths + `TOF_times`) and (2) the `wcut`
reading section, because the two exports have different layouts (§9).
All subfunctions live inside each file, so each driver is self-contained.

## 3. Requirements

| | |
| --- | --- |
| MATLAB | **R2020b or later** (`string` literals, `datetime`, `contains`, `smoothdata`, `filesep`) |
| MRST | **bundled** in `libs/mrst` — MRST 2024b trimmed to a 5.5 MB self-contained subtree, GPL-3.0. Nothing to install. |
| Excel | the relative-permeability table `Krw.xlsx` is read with `xlsread`, so a Windows MATLAB with Excel installed is assumed. Without Excel, replace `xlsread` with `readmatrix` (one line), or comment that block out — see §5.6. |
| Simulator | Intersect (or another Eclipse-compatible simulator with Eclipse *unformatted* streamline output) — needed only to **produce** the input files, not to read the code. |

Details, including the dependency-closure and runtime verification, are in
[`docs/dependencies.md`](docs/dependencies.md).

## 4. Quick start

```matlab
>> cd streamline-alt-inversion
>> startup                        % adds src/, examples/ and libs/mrst to the path
>> test_toolbox                   % optional: verifies the bundled toolbox
>> edit src/main_SL_inversion_C2.m      % set caseRoot and caseName, check TOF_times / SW_min / SW_max
>> main_SL_inversion_C2
```

Expected `test_toolbox` output:

```
[1] MRST entry functions on the path                     5/5 ok
[2] readGRDECL -> writeGRDECL -> readGRDECL round trip   OK
[3] readEclipseOutputFileUnFmt on tiny.SLNSPEC           OK
[4] file2Streamline on the path                          OK
ALL CHECKS PASSED.
```

Then import the updated `PERM_iter.GRDECL` / `SW_iter.GRDECL` back into the
reservoir simulator, run the next simulation **with streamline output**,
increment `iter_index`, and repeat.

## 5. Preparing the input data

All items live in the folder given by `caseRoot`, except the streamlines, which
live in `caseRoot/model.sim/<caseName>/`. The detailed formats and the full
export recipes are in [`docs/input_data.md`](docs/input_data.md); this is the
short version.

| # | Item | File | Produced from |
| --- | --- | --- | --- |
| 5.1 | current permeability field | `PERM_iter.GRDECL` | Petrel grid/property export (`PERMX`, `PERMY`, `PERMZ`, `NTG`) |
| 5.2 | current initial water saturation | `SW_iter.GRDECL` | Petrel grid/property export (`SWAT`, `NTG`) |
| 5.3 | streamlines of the current run | `model.sim/<caseName>/<caseName>.SLNSPEC`, `.SLN0001 …` | the **simulator** (streamline output switched on) |
| 5.4 | water-cut histories | `wcut` | simulated block: the run's well water-cut table; observed block: field production history |
| 5.5 | water-cut mismatch series | `swat_mismatch` | simulated − observed water cut, per well and per reporting date (optional: `mis_source="internal"` builds it from `wcut`) |
| 5.6 | relative-permeability table | `Krw.xlsx` | core/SCAL data: columns `Sw`, `krw`, `kro` |

### 5.1 Permeability field — `PERM_iter.GRDECL` (export from Petrel)

* In Petrel, right-click the **grid** (or a property set) in the *Models* pane →
  **Export** → the Eclipse/GRDECL option (wording varies by version:
  *"Simulation data…"*, *"Properties (GRDECL)"*, or the format list containing
  **GRDECL / Eclipse keywords**); alternatively **File → Export → Simulation
  data**.
* Tick **`PERMX`, `PERMY`, `PERMZ`, `NTG`**; keep **grid geometry**
  (`SPECGRID`, `COORD`, `ZCORN`, `ACTNUM`) in the file as well — the driver
  builds the grid with `processGRDECL`/`computeGeometry` and needs it.
* Save as `PERM_iter.GRDECL` in `caseRoot`.
* For iteration 0 this is the static (geological) permeability; **later
  iterations do not need an export** — the driver writes this file itself.

### 5.2 Initial water saturation — `SW_iter.GRDECL` (export from Petrel)

* Same export route, tick **`SWAT`** and **`NTG`** (`ACTNUM` is used when
  present, otherwise the active mask is `NTG > 0`).
* `SWAT` must be the **initial** water saturation of the current model (for
  iteration 0: the static initial condition your deck starts from — J-function,
  capillary-pressure/height model, water-saturation model, …).
* Save as `SW_iter.GRDECL` in `caseRoot`. Later iterations are written by the
  driver.

### 5.3 Streamlines — must be exported by the case model

The method needs the streamline snapshot of **each** simulation run:

* switch on the simulator's streamline output (Intersect writes the Eclipse
  **unformatted** files `<caseName>.SLNSPEC` and `<caseName>.SLN0001 …`);
* dump them at a cadence comparable to the reporting interval of the production
  data — the number of `.SLN####` files defines the number of snapshots. The two
  published cases use **30 dumps** (main case, one per year over its 30-year
  history) and **100 dumps** (WLW). Annual dumps are already sufficient for a
  30-year history; a finer cadence only places the back-projection window more
  precisely, and `sl_years` (§8.1) sets how long one snapshot is trusted.
* put them in `caseRoot/model.sim/<caseName>/` and set `caseName` to that
  folder name. **`caseName` must also match the block title of the simulated
  water-cut block inside `wcut`**, otherwise the driver stops with an explicit
  error.
* Local grid refinement is handled: `CARFIN` blocks written by Petrel are
  detected and streamline cells in refined cells are mapped back to their
  parent global cells.

### 5.4 Water-cut histories — `wcut`

A plain-text file with the **simulated** water cut of the current run and the
**observed** field water cut, one column per well, in the layout documented in
[`docs/input_data.md`](docs/input_data.md) §4 and shown in
`examples/wcut_template.txt`. The two blocks are concatenated in one file:

* the *simulated* block title must contain `caseName`;
* the *observed* block title must contain `Observed` (case-insensitive).

The C2 driver locates the blocks automatically by their `SUMMARY OF RUN`
markers; the WLW driver uses the fixed line numbers `wcut_fixed_cols` from the
configuration block (its export has no markers).

### 5.5 Water-cut mismatch series — `swat_mismatch` (optional)

Per well and per reporting date, the **simulated − observed** water cut, i.e.
`Δf_w = f_w^sim − f_w^obs`. Positive means the model waters out too early, which
drives the saturation update down; negative means the opposite. Zero means *not
used* (the driver skips zeros); `-1` and `undef` are also read as zero. Layout:
[`docs/input_data.md`](docs/input_data.md) §5,
`examples/swat_mismatch_template.txt`.

**You do not have to produce this file.** It is exactly the difference between
the two blocks of `wcut` (§5.4), which you already have — verified well by well
and date by date on the main case (Pearson 0.981, median absolute difference
4×10⁻⁴, the residual being digit truncation in the export). Set

```matlab
mis_source = "internal";   % build Δf_w from the two wcut blocks, no export needed
```

and the driver fills `mis_data` itself, using the per-cell validity mask so
that `undef` on either side is treated exactly as before. `mis_drop_last = true`
(default) drops the last reporting date, matching the step count of the Petrel
export the manuscript used.

Keep `mis_source = "file"` (the default) if you want to reproduce the paper
numbers: the internal mode uses the full intersection of the two `wcut` blocks
and therefore *more* wells (993 vs 927 in the main case — the 66 extra wells are
mostly low-mismatch ones, 37 of which fall below `mis_tol` and get frozen), so
it is not bit-identical.

Despite its name, the file holds a **water-cut** mismatch, not a saturation
mismatch — it comes from a Petrel objective-function export (`HM_WCT`, unit
`sm3/sm3`). Two independent checks: the paired differences above, and the fact
that all 155,560 paired cells satisfy `Δf_w + f_w^obs ≤ 1`, which a saturation
difference de-projected from the fractional-flow curve could not (it would reach
`1 − S_wc` at most). This also explains why `mis_tol = 0.05` is a water-cut
threshold on the scale of `fit_tol`, not a saturation tolerance.

### 5.6 Relative-permeability table — `Krw.xlsx`

Excel table with three columns `Sw`, `krw`, `kro` (viscosities `miuo`/`miuw`
are set in the configuration block). **Note:** the current algorithm does not
consume the derived fractional-flow curve — it is a leftover of the original
research codes together with `firstmis_grid` / `endcell_wellid` — but the driver
still **reads** the file at start-up, so either provide it or comment out that
block (Part 1, "读取相渗曲线").

## 6. The configuration block

Everything you have to touch is in the `EDIT THIS BLOCK` section at the top of a
driver:

```matlab
caseRoot = "path/to/your/case";   % case working directory
caseName = "CASE1";               % run name: streamline folder name AND the simulated block in wcut

PERM_path    = fullfile(caseRoot,"PERM_iter.GRDECL");   % in : current permeability field
PERM_outpath = fullfile(caseRoot,"PERM_iter.GRDECL");   % out: updated permeability field
SW_path      = fullfile(caseRoot,"SW_iter.GRDECL");     % in : current saturation field
SW_writepath = fullfile(caseRoot,"SW_iter.GRDECL");     % out: updated saturation field
SLN_headpath = fullfile(caseRoot,"model.sim",caseName); % in : streamline files of this run
wcut_readpath= fullfile(caseRoot,"wcut");               % in : water-cut histories
mis_readpath = fullfile(caseRoot,"swat_mismatch");      % in : mismatch series (mis_source="file" only)
krw_readpath = fullfile(caseRoot,"Krw.xlsx");           % in : relative-permeability table

mis_source    = "file";           % "file": read mis_readpath | "internal": build it from wcut
mis_drop_last = true;             % internal: drop the last date (match the Petrel export)

write_slnmask_to_poro = false;    % debug only: write the streamline visit count to PORO
```

If an output path equals its input path, the input file is backed up first as
`<name>.bak_yyyyMMdd_HHmmss`.

## 7. The outer-iteration run book

§0.3 is the one-screen version of this section. Each call of the driver consumes
one simulation result (streamlines + `wcut`, plus `swat_mismatch` in `"file"`
mode) and produces the two updated fields, so the only thing that changes
between calls is `iter_index` — plus the re-exported data.

```text
iter_index = 1  ──►  run the simulator (streamline output ON)
                     export  wcut  of this run   (+ swat_mismatch if mis_source="file")
                     run  main_SL_inversion_XX
                       ├─ writes PERM_iter.GRDECL  (updated PERMX/PERMY/PERMZ)
                       ├─ writes SW_iter.GRDECL    (updated SWAT)
                       └─ writes perm_inversion_summary.txt
iter_index = 2  ──►  import both updated fields into the deck, run the simulator
                     again, re-export wcut (+ swat_mismatch), run the driver ... repeat
```

* The console prints the current `gamma_eff`, the saturation step `gain`, the
  saturation-change statistics (`最大改变量 …`) and, for every frozen producer,
  the reason. Use these to judge whether the iteration behaved sensibly.
* Stop when the water-cut fit stops improving (the paper selects the stopping
  iteration from the **history-period** fit only, and evaluates prediction once).

## 8. Parameter reference

Every parameter is defined in one block at the top of each driver. They are
grouped by **what you are allowed to copy**: **A** (§8.1) must be calibrated on
your own reservoir, **B** (§8.2) can be taken from the paper unchanged, **C**
(§8.3) can be taken from the paper but has to be rescaled if your grid or
snapshot cadence differs. §0.2 is the short version of the A-class list.

The sensitivity of the B-class values is reported in Table 7 of the manuscript;
none of them had to leave its base value to obtain the published results.

### 8.1 Class A — calibrate per reservoir

| Parameter | Value in the paper | Meaning and how to set it |
| --- | --- | --- |
| `TOF_times` | `1500` (C2), `20000` (WLW) | Dimensionless-TOF → physical-time factor, `SW_TOF = TOF * TOF_times` (≈ days). It depends on the simulator's streamline time step / output unit; the two cases here differ by 13×. **If the saturation update looks wrong, suspect this first.** Check after 1–2 iterations: does the printed saturation change and the water-cut fit move in the right direction? If not, change the order of magnitude. |
| `SW_min`, `SW_max` | `0.01`, `0.999883` | Saturation clip bounds. `SW_min` = connate water saturation (or the smallest saturation your model allows); `SW_max` = `1 − S_orw`, or the deck's upper limit (0.999883 is the deck limit of the main case). `SW_max` above the deck limit is truncated by the simulator on the next run. |
| `PERM_min`, `PERM_max` | `0.01`, `800` mD | Geological bounds of the projected multiplier. Take the permeability range of your field. |
| `miuo`, `miuw` | `2.8`, `1` mPa·s | Fluid viscosities used to build `f_w(S_w)` from `Krw.xlsx`. |
| `wct_break_thr` | `0.02` | Fallback breakthrough threshold ("first time the water cut exceeds …"). Must sit above the noise floor of the observed water cut, otherwise shut-in / restart spikes are read as breakthroughs. |
| `kappa_w` | `0.5` | Tempering exponent of the flow-fraction weighting, Eq. (30). Calibrated together with `df_obs_mode` (§8.1.1). Because `Δf ∝ a^κ` is monotone, κ does **not** change the ranking of the streamlines and does not change which one is selected first — it only changes how many of them are needed to reach the observed increment. A sub-optimal κ therefore still converges, with a longer (or, at very small κ, a collapsed) subset. |
| `df_obs_mode` | `"two_sample"` | Window used to read `Δf^obs` in Eq. (35): `"two_sample"` = one sampling interval on each side of breakthrough, `[t_b − Δt_s, t_b + Δt_s]`; `"stage"` = `[t_b, t_e]`, where `t_e` is the first time after `t_b` at which the derivative of the observed water cut falls below `eps_df`. |
| `sl_years` | `6` | Validity window (years) of one streamline snapshot. Set it from the snapshot cadence and from how long you trust a single flow field. |
| `wcut_fixed_cols` | `[7 12 310 318 323 621]` | Line layout of *your* `wcut` export — WLW driver only; the C2 driver finds the blocks by their `SUMMARY OF RUN` markers. |
| `caseRoot`, `caseName` | placeholders | Path and case name. `caseName` must equal both the streamline folder name and the title of the simulated block inside `wcut`. |

#### 8.1.1 Calibrating `kappa_w` and `df_obs_mode`

The pair controls how the per-streamline hypothetical increment is scaled against
the observed one: the single-front estimate of Eq. (30) is systematically too
small when many low-rate streamlines feed one producer, and κ tempers that
dilution. The manuscript's Table 5 is exactly this scan, run on both reservoirs.

The scan does **not** require new simulations — the driver is pure
post-processing of one streamline snapshot, and `perm_inversion_summary.txt`
already contains the three numbers the criterion needs (`N_cand`, `M_star`,
`df_line`, `df_obs`). Procedure:

1. Point `PERM_outpath` / `SW_writepath` at a scratch folder, so that the scan
   does not overwrite the fields of the real iteration.
2. For each candidate pair `(kappa_w, df_obs_mode)`, set the two values, run the
   driver once with the same `iter_index`, and keep
   `perm_inversion_summary.txt`.
3. From each summary, compute
   `median(df_line ./ (df_obs + 1e-4))` over the producers, and the share of
   producers with `M_star == N_cand` (the degenerated ones, whose threshold was
   never reached and which therefore fall back to the full candidate set).
4. Choose the pair where the median ratio is closest to 1 **and** roughly half of
   the producers still get a non-degenerate subset — i.e. a median `M_star` of a
   few streamlines out of a median `N_cand` of ~10. A median `M_star = 1` means
   the rule has collapsed onto the single most influential streamline, which is
   the opposite failure mode and is just as undesirable as full-set selection.

Reference points from the manuscript (8 columns of Table 5, 479 producers for
WLW and 426 for the main case): WLW is closest to unity at `(0.5, two_sample)`
with a median ratio 0.976, 50.9 % degenerated and a median subset of 3 out of 13;
the main case is closest at `(1.5, stage)` with 0.951, 50.2 % and 3 out of 8.
Both settings are equally "correct" — the working point is case-specific, the
working *behaviour* is not. The paper deliberately keeps one setting for the two
cases (0.5 + `two_sample`) instead of tuning per case, so that the comparison
against the baseline methods is not favoured by a per-case calibration.

### 8.2 Class B — copy the paper values

**Permeability inversion**

| Parameter | Paper | Meaning |
| --- | --- | --- |
| `iter_index` | `1` | Current outer-iteration index (1 at the first iteration that has a streamline dump). |
| `gamma_relax`, `gamma_decay` | `1`, `0.9` | Relaxation factor and its geometric decay, `gamma_eff = gamma_relax * gamma_decay^(iter_index-1)`. |
| `fit_tol` | `0.20` | Producer freezing tolerance: wells whose mean relative water-cut error is below it are not corrected this iteration. |
| `swing_hi`, `swing_boost` | `0.40`, `1.5` | Critical band `[fit_tol, swing_hi)` and the step amplification applied inside it. |
| `e_bt_tol`, `e_wc_tol` | `0.10`, `0.15` | Dead zones of the breakthrough-time and water-cut-level signals. |
| `w_bt` | `0.5` | Weight of the breakthrough-time signal (the water-cut-level signal takes `1 − w_bt`). |
| `beta_weight` | `0.5` | Weight `β` of the travel-time contribution in the combined streamline contribution, Eq. (33). |
| `eps_tau`, `eps_f`, `eps_df` | `1e-3`, `1e-4`, `0.01` | Regularisation constants of Eqs. (31)–(36) and the derivative threshold used for breakthrough detection. |
| `jump_back`, `jump_fwd` | `1`, `1` | Sampling window around the instantaneous water-cut jump (used when `df_obs_mode = "two_sample"`). |
| `chi_min`, `chi_max` | `0.5`, `2.0` | Per-iteration bounds of the streamline permeability multiplier. |
| `sw_front_min` | `0.05` | Minimum saturation gradient required to identify a water front on a streamline. |
| `fix_etot_combine` | `true` | Combine the two signals *before* the `tanh` (avoids the saturation-induced cancellation of large mismatches). |
| `fix_break_fallback` | `true` | Fall back to "first time the water cut exceeds `wct_break_thr`" when the derivative criterion finds no breakthrough. |
| `make_plots` | `false` | Draw per-well diagnostic figures. |
| `write_slnmask_to_poro` | `false` | **Debug only.** When `true`, the streamline visit count overwrites the `PORO` keyword of the written GRDECL — leave it `false` for production runs. |

**Saturation inversion**

| Parameter | Paper | Meaning |
| --- | --- | --- |
| `alpha` | `1` | Explicit step factor applied to the accumulated mismatch. |
| `max_vary` | `1` | Maximum saturation change per cell and per iteration (before the decay gain). |
| `decay_times` | `3` | Divisor of the lower back-projection time bound. |
| `sw_decay` | `0.9` | Per-iteration gain decay, `gain = sw_decay^(iter_index-1)`. |
| `mis_tol` | `0.05` | Producer freezing tolerance on the mean absolute mismatch. Although the driver variable is called a *saturation* mismatch, the series is a water-cut difference (§5.5), so this tolerance is on the same scale as `fit_tol`. |
| `dedup_cells` | `true` | De-duplicate cells in the single-point write mode. |
| `normalize_cnt` | `true` | Divide the update of repeatedly touched cells by `sqrt(count)` (hot-spot suppression). |
| `soft_clip` | `true` | `tanh` soft clipping of the update (`false` → hard `min`/`max`). |
| `sw_write_mode` | `"segment"` | `"single"` = write only the front cell `GLO_CELL(k_i)` (original behaviour); `"segment"` = spread the same total over the whole `[k_i → well]` segment. |
| `sw_seg_weight` | `"end_boost"` | In-segment weights: `"uniform"`, or `"end_boost"` (uniform + extra weight on the last `sw_end_cells` cells). |
| `sw_dedup_seg` | `false` | Keep per-cell de-duplication in segment mode (see the comment in the driver; `true` disables the segment fix). |
| `endtime_weight` | `3` | **Unused** (kept from the original codes). |

### 8.3 Class C — copy, then rescale with your discretisation

These are counts of cells or snapshots, not dimensionless constants:

| Parameter | Paper | Adjust when |
| --- | --- | --- |
| `sw_end_cells` | `5` | the near-well cell size differs appreciably from the published grids (keep the same physical length, i.e. scale with the cell size); the paper's sensitivity run tolerates 3–5 |
| `sw_end_frac` | `0.5` | the share of the update that must reach the well end; keep 0.5 unless the well-end cells are much larger than the rest |
| `sw_seg_maxlen` | `150` | cells per segment; `0` = unlimited. Scale with the number of cells between the front and the well |
| `sln_expand_nb` | `2` | snapshots added forward/backward when the frozen snapshot contains no streamline ending at a well (`0` disables); larger values are needed when the dump cadence is coarse |
## 9. Differences between the two drivers

| Aspect | `main_SL_inversion_C2` (main case) | `main_SL_inversion_WLW` (second case) |
| --- | --- | --- |
| configuration block | its own paths | its own paths |
| `TOF_times` | `1500` | `20000` |
| `wcut` reading | blocks found automatically via `SUMMARY OF RUN`; the simulated block is matched by `caseName`, the observed block by `Observed` | fixed line numbers `wcut_fixed_cols = [7 12 310 318 323 621]` |
| date parsing | `parse_run_date` (Chinese locale `zh_CN`, e.g. `01-1月-1995`) for both files | plain `datetime(...)` (ISO-style dates) |
| mismatch series | `mis_source="file"`: number of steps from the header (line 4), or every line from 12 up to the last one; `mis_source="internal"`: built from the two `wcut` blocks | same switch (C2 reads blocks automatically, WLW by `wcut_fixed_cols`) |
| model | 370 × 252 × 12 = 1 118 880 cells, no LGR | WLW block, with `CARFIN` refinement (auto-mapped) |

Everything else — grid handling, breakthrough detection, minimum-subset
selection, multipliers, back-projection, write-out — is the same code. If your
own export does not match either layout, adapt the reading block: the C2 version
is the more robust starting point when your export carries block markers.

## 10. Input data and outputs

* [`docs/input_data.md`](docs/input_data.md) — the input items, their exact formats and the export recipes.
* Written by the drivers (next to `PERM_outpath` / `SW_writepath`):

| File | Content |
| --- | --- |
| `PERM_iter.GRDECL` | `PERMX`, `PERMY`, `PERMZ` (when present) and `NTG` after the streamline-multiplier projection |
| `SW_iter.GRDECL` | `SWAT` and `NTG` after the back-projection of the water-cut mismatch (`PORO` only if `write_slnmask_to_poro = true`) |
| `perm_inversion_summary.txt` | per-well table: `well, t_sim, t_obs, E_bt, E_bt_soft, E_wc, E_tot, N_cand, M_star, df_line, df_obs, Lambda_f, wc_err` |
| diagnostic figures | only when `make_plots = true` |

> The written GRDECL files are **property files**: they contain the keys the
> driver read, not the grid geometry. Include them in your deck (or import them
> in Petrel) as property updates of the *same* grid.

No field data are distributed with this repository. All paths and case names in
the drivers are placeholders (`path/to/your/case`).

## 11. Method → code map

| Manuscript | Where in the code |
| --- | --- |
| grid, local refinement and geometry | Part 1 (`readGRDECL` / `processGRDECL` / `computeGeometry`, `lgrcell2glocell`) |
| water-cut reading, breakthrough detection, `E_bt`, `E_wc` | Part 2 |
| mismatch series reading (from file, or built internally from the two `wcut` blocks via `mis_source`) | Part 3 |
| streamline reading (once per iteration) and LGR mapping | Part 4 (`file2Streamline`) |
| minimum-streamline-subset selection, multipliers, projection | Part 5 |
| back-projection of the water-cut mismatch | Part 6 |

## 12. Notes and limitations

* The inversion inherits the **frozen-flow-field** assumption of
  streamline-based methods: within one reconstruction interval the pressure and
  velocity fields are held fixed. The interval matches the production-data
  sampling, and the flow field is refreshed after every outer iteration, because
  every outer iteration is a full simulation.
* All saturation updates are bounded per cell and per producer and decay with
  the iteration index, so the initial hydrocarbon pore volume changes only
  marginally (below 0.2 % in the reported applications).
* `TOF_times`, the saturation bounds and the `kappa_w`/`df_obs_mode` pair are
  **not** universal constants — see §0.2 and §8.1.
* The two drivers share one engine but they were **not** run with identical
  per-case settings: `TOF_times` differs, the `wcut` layouts differ, and the
  saturation-write parameters (`sw_end_cells`, `sw_seg_maxlen`) are counts of
  cells and therefore scale with the grid (§8.3). A single parameter set is not
  expected to reproduce both case studies from a cold start.
* Comments in the source files are written in Chinese; identifiers and all
  documentation are in English.
* `processGRDECL` requires a well-formed Eclipse grid (faults, dipping layers and
  `CARFIN` refinements are handled). `examples/tiny.GRDECL` is only a *format
  sample* for the reader/writer, not a buildable deck.
* Known dead code inherited from the original research codes: `fw_data`
  (fractional-flow curve built from `Krw.xlsx`), `firstmis_grid`,
  `endcell_wellid` and `endtime_weight` are computed but not used by the current
  algorithm; `Krw.xlsx` is nevertheless read at start-up.

## 13. License

Released under the **GNU General Public License v3.0** ([`LICENSE`](LICENSE)),
consistent with the MRST ecosystem: `libs/mrst` is redistributed unmodified
under GPL-3.0, which makes the combined work GPL-3.0.

## 14. Citation

If you use this code, please cite the manuscript above. A DOI will be added
after publication. Bug reports and questions are welcome through the GitHub
issue tracker.

---

## 15. 中文说明（摘要）

本仓库是上述论文方法的 MATLAB 实现。**每次外层迭代只需一次 Intersect 正演模拟**，
随后在 MATLAB 中同时完成两件事：

1. **初始含水饱和度反演** —— 由生产井含水率失配（`swat_mismatch`，即 `Δf_w = f_w^sim − f_w^obs`，
   可由 `wcut` 两块内部生成）经流线反投影（特征线法）更新 `SWAT`，写出 `SW_iter.GRDECL`；
2. **渗透率反演** —— 由见水时间失配与突破后含水增量，经最小流线子集筛选后沿流线做
   乘性修正并投影回网格，更新 `PERMX`/`PERMY`/`PERMZ`，写出 `PERM_iter.GRDECL`。

两个更新共用同一时刻的流线快照，避免初始饱和度误差被渗透率"顶包"。流线每轮只读一次。

**依赖**：MATLAB R2020b 及以上即可 —— MRST 已**内置**在 `libs/mrst`（MRST 2024b
裁剪版，5.5 MB，GPL-3.0），无需另行安装；`Krw.xlsx` 用 `xlsread` 读取，故 Windows +
Excel 环境最省事（无 Excel 时把该行换成 `readmatrix` 或注释掉该段）。

**用法**：

```matlab
>> cd streamline-alt-inversion
>> startup                    % 把 src/、examples/ 与内置 MRST 加入路径
>> test_toolbox               % 可选：自检内置工具箱是否完整
>> edit src/main_SL_inversion_C2.m    % 改 caseRoot 与 caseName，并核对 TOF_times / SW_min / SW_max
>> main_SL_inversion_C2
```

运行后把 `PERM_iter.GRDECL` / `SW_iter.GRDECL` 导回模拟器（**打开流线输出**）跑下一轮，
`iter_index` 加一，重复。

**参数分三类**（完整表见 §8，速查见 §0.2）：

* **[A] 必须按自己的油藏标定，论文值不能照搬**：
  * `TOF_times`：流线 TOF 是无量纲量，到物理时间的换算倍数与模拟器的流线时间步长/单位
    有关。本仓库两案例分别取 1500（C2）与 20000（WLW），**相差 13 倍**。取错会让反投影
    时间窗整体错位，饱和度修正完全打不准 —— 结果异常时先查这个参数。
  * `SW_min` / `SW_max`：饱和度更新的截断上下限，通常分别取束缚水饱和度与
    `1 − S_orw`（或 deck 的含水饱和度上限）；`SW_max` 不能超过 deck 上限。
  * `kappa_w` + `df_obs_mode`：二者的**成对**标定（论文表 5）。最优点随区块变
    （WLW：0.5 + 两步窗口；主案例：1.5 + `[t_b,t_e]`），但工作特性不变（比值中位≈0.95–0.98、
    退化井≈50%、子集中位 3 条）。扫描方法见 §8.1.1 —— **不需要重跑模拟器**，驱动只做后处理。
  * 其余：`PERM_min/PERM_max`、`miuo/miuw`、`wct_break_thr`、`sl_years`、
    `wcut_fixed_cols`（仅 WLW 版）、`caseRoot/caseName`。
* **[B] 可直接沿用论文值**：`gamma_relax/gamma_decay`、`fit_tol`、`swing_hi/swing_boost`、
  `e_bt_tol/e_wc_tol`、`w_bt`、`beta_weight`、`eps_tau/eps_f/eps_df`、`jump_back/jump_fwd`、
  `chi_min/chi_max`、`sw_front_min`、`alpha`、`max_vary`、`decay_times`、`sw_decay`、
  `mis_tol`、`mis_source/mis_drop_last` 以及各布尔开关（两个已发表算例均未改动）。
* **数据可省一项**：`swat_mismatch` 的内容就是 `wcut` 两块之差（模拟 − 实测），置
  `mis_source="internal"` 即由 `wcut` 内部生成，不必每轮再导一次；默认仍为 `"file"`，
  因为论文数字是在该口径下跑出来的（内部模式井集更全，993 vs 927 口，结果不完全逐位一致）。
* **[C] 可沿用，但网格尺度或快照间隔差得多时按比例改**：`sw_end_cells`、`sw_end_frac`、
  `sw_seg_maxlen`、`sln_expand_nb`。

**需要准备的输入**（详见 §5 与 [`docs/input_data.md`](docs/input_data.md)）：

| 输入 | 怎么来 |
| --- | --- |
| `PERM_iter.GRDECL` | 从 Petrel 导出网格属性：勾选 `PERMX/PERMY/PERMZ/NTG`，并保留 `SPECGRID/COORD/ZCORN/ACTNUM` 几何 |
| `SW_iter.GRDECL` | 同上，勾选 `SWAT`（初始含水饱和度）与 `NTG` |
| `model.sim/<caseName>/*.SLN*` | **由算例模型导出**：模拟器打开流线输出，产出 `<caseName>.SLNSPEC` 与 `.SLN0001…`，与生产数据同频率 |
| `wcut` | 模拟块（本轮井含水率）+ 实测块（油田生产历史）拼成一个文本文件 |
| `swat_mismatch` | 逐井逐时刻的"模拟 − 实测"含水率之差（即含水率误差序列）；可选，`mis_source="internal"` 时由 `wcut` 两块生成 |
| `Krw.xlsx` | 相渗数据：三列 `Sw / krw / kro`（当前算法未用到其派生曲线，但启动时会读取） |

两份驱动的差异只有（1）配置块（读取路径 + `TOF_times`）与（2）`wcut` 读取段
（C2 按 `SUMMARY OF RUN` 自动分块，WLW 用固定行号 `wcut_fixed_cols`），其余逐行一致。
源码注释为中文。
