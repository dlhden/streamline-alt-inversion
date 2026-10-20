# Changelog

## v1.1.4 — 2026-10-20

**`mis_source` now defaults to `"internal"`: the driver no longer reads
`swat_mismatch`.**

* The default was `"file"` (reproducing the manuscript), which kept the export in
  the critical path even though the series can be rebuilt from `wcut`. The
  default is now `"internal"`, i.e. one less file to export every iteration, and
  the well set becomes the full intersection of the two `wcut` blocks.
* `mis_source = "file"` still works and is now the explicit "reproduce the
  published numbers" switch. In that mode a missing `swat_mismatch` stops the run
  with an error naming the switch, instead of failing inside the reader.
* README §0.1/§5.5/§6/§8, `docs/input_data.md` §5 and both driver headers
  updated: item 6 is optional and unused by default.
* `build_repo_1012.py` now reads the renamed master sources (`*_1020.m`).

## v1.1.3 — 2026-10-20

**Bug fix in the internal mismatch mode: wrong column when the two `wcut` blocks
have different well sets.**

* `data_case` and `valid_case` were indexed with the *compacted* well index
  instead of the original column of the simulated block. In the main case the
  simulated block holds 1005 wells and the observed one 993, in a different
  order; 13 wells are dropped by the intersection, so every column after the
  first drop was reading another well's simulation history.
* Fixed by keeping `cidx = find(keep)` and reading `data_case(k,cidx(j))`.
  Re-verified against the export: 992 wells, Pearson 0.981, median absolute
  difference 4×10⁻⁴ (unchanged, because the earlier spot-check matched wells by
  name, not by column).
* The start-up message now prints how many simulated wells were discarded for
  lack of an observation, which makes this class of mismatch visible.

## v1.1.2 — 2026-10-20

**`swat_mismatch` can now be computed from `wcut` — and the file was named wrong.**

Source changes

* New switch **`mis_source`** (`"file"` by default, `"internal"` optional). In
  `"internal"` mode the driver builds the saturation-inversion input directly
  from the simulated and observed blocks of `wcut`, so the `swat_mismatch`
  export is no longer part of the workflow. `mis_drop_last` (default `true`)
  drops the last reporting date so the step count matches the historical export.
  The `"file"` branch is unchanged line for line, so the default behaviour is
  byte-identical to v1.1.1.
* The two `wcut` blocks now also carry a **per-cell validity mask** (`undef` on
  either side), so the internal mode reproduces the "skip missing observations"
  rule of the file mode instead of turning `undef` into a spurious mismatch.

What the file actually contains

* We checked `swat_mismatch` against the two `wcut` blocks of the same run, well
  by well and date by date: it **is** `Δf_w = f_w^sim − f_w^obs`
  (Pearson 0.981, median absolute difference 4×10⁻⁴, the residual being the
  truncation of the exported digits). It is a Petrel objective-function export
  (`HM_WCT`, unit `sm3/sm3`).
* Independent confirmation that it is *not* a saturation difference: all
  155,560 paired cells satisfy `Δf_w + f_w^obs ≤ 1`, impossible for
  `ΔS_w = S_w^sim − S_w^obs` (which would reach `1 − S_wc` at most and is not
  bounded by the observed water cut).
* Consequence for the documentation: every place that described the file as
  "observed − simulated" had the sign **wrong**. Corrected to "simulated −
  observed" in README §0.1/§5.5/§15, `docs/input_data.md` §5 and the template.
  This matters — with the old wording a self-made file would have flipped the
  direction of the saturation update.

Behaviour of the internal mode (main case)

| | `"file"` | `"internal"` |
| --- | --- | --- |
| wells entering the saturation branch | 926 | 992 (intersection of the two blocks) |
| wells frozen by `mis_tol = 0.05` | 0 | 37 |
| paired cells vs. the file mode | — | Pearson 0.981, median abs. diff 4×10⁻⁴ |

All 37 frozen wells are among the 66 wells the manual export had dropped; on the
926 shared wells the two modes freeze none. The internal mode is therefore the
better default for a new reservoir, but the `"file"` mode is kept as default
because it is what produced the published numbers.

Documentation

* README §0.1: the data checklist is now **five mandatory items plus one
  optional**; §0.2/§0.3 and the driver headers updated accordingly.
* README §5.5 and `docs/input_data.md` §5: how to switch, what the switch
  changes, and why the sign convention is not negotiable.

## v1.1.1 — 2026-10-20

**Parameter documentation, and one value that did not match the manuscript.**

Source changes

* **`gamma_relax` corrected from `0.2` to `1`.** The manuscript (Table 7 and
  §4.3) reports the initial relaxation factor as $\gamma^{(0)}=1$ with the decay
  $\gamma^{(n)}=\gamma^{(0)}\times0.9^{\,n-1}$, and the published results were
  produced with `1`. The value shipped in v1.1.0 was a stale one carried over
  from an earlier draft of the codes and would not reproduce them. No other
  parameter value changed.
* New switch **`df_obs_mode`** (`'two_sample'` by default, `'stage'` optional)
  for Eq. (35). `'two_sample'` is the window used in the published runs,
  `[t_b−Δt_s, t_b+Δt_s]`; `'stage'` reads `[t_b, t_e]`, up to the first time the
  derivative of the observed water cut falls below `eps_df`. The default branch
  is byte-identical to the previous behaviour.
* `kappa_w` and `df_obs_mode` are documented as a **calibrated pair**: the
  working point is case-specific (WLW: `0.5` + two-sample window; main case:
  `1.5` + `[t_b,t_e]`), while the working *behaviour* is not (both reach a median
  `Δf_pre/Δf_obs` of ≈0.95–0.98 with ≈50 % of the producers degenerated and a
  median subset of 3 streamlines). κ enters as a monotone power, so it changes
  the subset length but not the ranking of the streamlines.

Documentation

* Both drivers now carry a header block listing **the six input data items**
  (and which of them must be re-exported every iteration) and a **three-class
  parameter map**: `[A]` must be calibrated on your own reservoir, `[B]` can be
  copied from the paper, `[C]` can be copied but has to be rescaled with the grid
  or the snapshot cadence. The same tags appear inline on every parameter line.
* README §0 rewritten as the single entry point: §0.1 the data checklist
  (file, source, re-exported or not), §0.2 the A-class parameters with the
  reason they cannot be copied and how to set them, §0.3 the iteration procedure.
* README §8 split into §8.1 (Class A, with values and setting procedure), §8.2
  (Class B, with the paper values in a column) and §8.3 (Class C).
* New README §8.1.1: how to run the `kappa_w`/`df_obs_mode` scan **without
  re-running the simulator** — the driver is pure post-processing and
  `perm_inversion_summary.txt` already contains `N_cand`, `M_star`, `df_line`,
  `df_obs`, so the criterion of Table 5 is a few lines of arithmetic per run.

## v1.1.0 — 2026-10-12

**Algorithms updated to the version that produced the results in the manuscript**
(the two drivers are now the *unified alternating* implementation, and they
differ from each other only in the configuration block and in the `wcut` reading
section).

Source changes

* `src/main_SL_inversion_C2.m`, `src/main_SL_inversion_WLW.m` — replaced by the
  current drivers (function names follow the file names; paths are placeholders
  `caseRoot` / `caseName` instead of any local absolute path).
* Permeability inversion: the step is driven by the weighted sum
  `E_tot = tanh(w_bt·E_bt^raw − (1−w_bt)·E_wc^raw)` (combine before the `tanh`,
  so that large mismatches are no longer cancelled by saturation); breakthrough
  detection has a fallback ("first time the water cut exceeds `wct_break_thr`")
  and the frozen snapshot is expanded by `sln_expand_nb` snapshots when it
  contains no streamline ending at a producer.
* Saturation inversion: the update is written over the whole `[k_i → well]`
  segment (`sw_write_mode = "segment"`, `sw_seg_weight = "end_boost"`,
  `sw_end_cells`, `sw_end_frac`, `sw_seg_maxlen`) instead of a single cell, with
  the total amount preserved; hot-spot suppression stays (`SWAT_cnt`,
  `sqrt`-normalisation, `tanh` soft clipping).
* Removed the previously published safeguards and the mismatch-sharing constant
  (`w_recent` / `recent_frac`, `obs_drop_tol`, `osc_damp`, `d_time`) — they are
  not part of the current implementation, so the per-case hyperparameter set is
  now **`TOF_times` only**.
* New switch `write_slnmask_to_poro` (default `false`): the streamline visit
  count is no longer written into the `PORO` keyword of `SW_iter.GRDECL`
  unconditionally, which prevents accidental overwriting of the model porosity.
* Paths are joined with `filesep` (portable); the WLW driver's water-cut line
  numbers are now the configuration item `wcut_fixed_cols`.
* Per-case settings of the two applications: `TOF_times = 1500` (C2) and
  `20000` (WLW); saturation bounds `[0.01, 0.999883]`. Both are documented as
  user-calibrated quantities in the drivers and in the README.

Documentation

* `README.md` — rewritten: what the code does, requirements, quick start,
  input-data preparation, the outer-iteration run book, the full parameter
  reference, the differences between the two drivers, outputs, method→code map
  and limitations, plus a Chinese summary. §0 calls out the two parameters every
  user must set (`TOF_times`, `SW_min`/`SW_max`).
* `docs/input_data.md` — rewritten: how to export permeability and initial water
  saturation from Petrel, how the case model must export streamlines, how to
  build `wcut` and `swat_mismatch`, the `Krw.xlsx` table, and a pre-run sanity
  checklist.
* `examples/wcut_template.txt`, `examples/swat_mismatch_template.txt` — line-by-
  line skeletons of the two text inputs (verified to parse with the drivers'
  offset logic).
* `docs/dependencies.md` — corrected: `Krw.xlsx` is read with `xlsread` (Excel
  required, with two one-line workarounds documented).

## v1.0.0 — 2026-10-10

First public release: the two alternating drivers, `file2Streamline.m`, the
trimmed MRST 2024b subtree in `libs/mrst`, `startup.m` and the toolbox self-check.
