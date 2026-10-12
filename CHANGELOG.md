# Changelog

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
