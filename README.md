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

Everything needed to **run** the code is included in this repository (MRST is
bundled, see §3) — you only need MATLAB.

---

## 1. What the code does

One outer iteration = **one** full-physics simulation (Intersect) followed by one
post-processing pass in MATLAB/MRST that produces **two** updated fields at once:

| Step | Output | Governing quantities |
| --- | --- | --- |
| Initial water-saturation update | `SW_iter.GRDECL` (`SWAT`) | producer water-cut mismatch, streamline geometry, method-of-characteristics back-projection |
| Permeability correction | `PERM_iter.GRDECL` (`PERMX`) | breakthrough-time mismatch, post-breakthrough water-cut increment, minimum-streamline-subset selection |

Both updates are driven by the **same** streamline snapshot. That is the point of
the method: the initial-saturation error is not silently absorbed by artificial
permeability changes, and the permeability correction is restricted to the
dynamically sufficient subset of streamlines whose cumulative hypothetical
water-cut increment reaches the observed post-breakthrough increment.

## 2. Repository layout

```
streamline-alt-inversion/
├── startup.m                     % adds src/, examples/ and libs/mrst to the MATLAB path
├── src/
│   ├── main_SL_inversion_C2.m    % driver, main case
│   ├── main_SL_inversion_WLW.m   % driver, second case
│   └── file2Streamline.m         % reshapes Eclipse .SLN* records into MATLAB streamline structs
├── libs/
│   ├── README.md                 % provenance / trimming of the bundled MRST subset
│   └── mrst/                     % MRST 2024b (trimmed), GPL-3.0
├── examples/
│   ├── tiny.GRDECL               % miniature Eclipse grid (format sample)
│   ├── tiny.SLNSPEC              % miniature Eclipse unformatted result file
│   └── test_toolbox.m            % self-check of the bundled toolbox
└── docs/
    ├── dependencies.md           % what is used, versions, verification
    └── input_data.md             % required input files and their formats
```

The two drivers are **one and the same engine**: they are identical except for
the configuration block (§5). All subfunctions live inside each file, so each
driver is self-contained.

## 3. Requirements

| | |
| --- | --- |
| MATLAB | **R2020b or later** (`string` literals, `datetime`, `contains`, `smoothdata`) |
| MRST | **bundled** in `libs/mrst` — MRST 2024b, trimmed to a 5.5 MB self-contained subtree, GPL-3.0. Nothing to install. |
| Simulator | Intersect (or another Eclipse-compatible simulator with streamline output) — only needed to **produce** the input files, not to read the code. |

Details, including the dependency-closure and runtime verification, are in
[`docs/dependencies.md`](docs/dependencies.md).

## 4. Quick start

```matlab
>> cd streamline-alt-inversion
>> startup                       % adds src/, examples/ and libs/mrst to the path
>> test_toolbox                  % optional: verifies the bundled toolbox
>> edit src/main_SL_inversion_C2.m      % set caseRoot and caseName
>> main_SL_inversion_C2
```

Then import the updated `PERM_iter.GRDECL` / `SW_iter.GRDECL` back into the
reservoir simulator, run the next simulation, increment `iter_index`, and repeat.

Expected `test_toolbox` output:

```
[1] MRST entry functions on the path                     5/5 ok
[2] readGRDECL -> writeGRDECL -> readGRDECL round trip   OK
[3] readEclipseOutputFileUnFmt on tiny.SLNSPEC           OK
[4] file2Streamline on the path                          OK
ALL CHECKS PASSED.
```

## 5. The configuration block

Everything you have to touch is in the `EDIT THIS BLOCK` section at the top of a
driver:

```matlab
caseRoot = "path/to/your/case";   % case working directory
caseName = "CASE1";               % run name, must match the block in the wcut file

PERM_path    = fullfile(caseRoot,"PERM_iter.GRDECL");   % in : current permeability field
PERM_outpath = fullfile(caseRoot,"PERM_iter.GRDECL");   % out: updated permeability field
SW_path      = fullfile(caseRoot,"SW_iter.GRDECL");     % in : current saturation field
SW_writepath = fullfile(caseRoot,"SW_iter.GRDECL");     % out: updated saturation field
SLN_headpath = fullfile(caseRoot,"model.sim",caseName); % in : streamline files of this run
wcut_readpath= fullfile(caseRoot,"wcut");               % in : water-cut histories
mis_readpath = fullfile(caseRoot,"swat_mismatch");      % in : saturation-mismatch series
```

If an output path equals its input path, the input file is backed up first as
`<name>.bak_yyyyMMdd_HHmmss`.

### The only differences between the two drivers

| Line | Setting | `main_SL_inversion_C2` (main case) | `main_SL_inversion_WLW` (second case) |
| --- | --- | --- | --- |
| 1 | function name | `main_SL_inversion_C2` | `main_SL_inversion_WLW` |
| 4 | header comment | "main case" | "second case" |
| 47 | `gamma_decay` | `0.9` | `0.8` |
| 55 | `recent_frac` note | — | unused because `w_recent = 0` |
| 56 | `w_recent` | `0.5` | `0` (recent-window weighting off) |
| 57 | `obs_drop_tol` | `0.30` | `1.0` (sharp-decline freezing off) |
| 58 | `osc_damp` | `0.5` | `1` (oscillation damping off) |
| 75 | `d_time` | `0.5` | `1` |

Net effect: **8 lines**, all inside the configuration block. Everything else —
grid handling, wcut parsing, breakthrough detection, minimum-subset selection,
back-projection — is the same code.

The last three parameters switch off the safeguard mechanisms that were
introduced for the main case. The two cases also use different values of the
relaxation schedule (`gamma_decay`) and of the mismatch-sharing constant
(`d_time`), which sets the saturation-update magnitude and therefore has to be
calibrated per case: the mismatch series of the two fields have different
units/scales.

## 6. Input data and outputs

* [`docs/input_data.md`](docs/input_data.md) — the input items and their exact formats.
* Written by the drivers:

| File | Content |
| --- | --- |
| `PERM_iter.GRDECL` | `PERMX` after the streamline-multiplier projection (also carries grid geometry) |
| `SW_iter.GRDECL` | `SWAT` after the back-projection of the water-cut mismatch |
| `perm_inversion_summary_iter<NN>.txt` | per-well table: `well, t_sim, t_obs, E_bt, E_bt_soft, E_wc, drive, N_cand, M_star, df_line, df_obs, Lambda_f, wc_err, snapshot, osc_damped` |
| `well_update_state.mat` | per-producer state carried between iterations (previous correction sign, for oscillation damping) |
| diagnostic figures | only when `make_plots = true` |

No field data are distributed with this repository. All paths and case names in
the drivers are placeholders (`path/to/your/case`).

## 7. Parameter reference

All parameters are defined in one block at the top of each driver and map
directly onto the equations of the manuscript.

**Permeability inversion**

| Parameter | Meaning |
| --- | --- |
| `iter_index` | current outer-iteration index |
| `gamma_relax`, `gamma_decay`, `gamma_min` | relaxation factor and its decaying schedule, `gamma_eff = max(gamma_relax*gamma_decay^(n-1), gamma_min)` |
| `fit_tol`, `swing_hi`, `swing_boost` | producer freezing tolerance, critical band and its step amplification |
| `e_bt_tol`, `e_wc_tol` | dead zones of the breakthrough-time and water-cut-level signals |
| `w_bt` | weight of the breakthrough-time signal (the water-cut-level signal takes `1 - w_bt`) |
| `recent_frac`, `w_recent` | recent-window length and its weight in the water-cut-level signal (`w_recent = 0` disables it) |
| `obs_drop_tol` | threshold of the sharp-decline detector (`>= 1` disables it) |
| `osc_damp` | oscillation-damping factor (`1` disables it) |
| `beta_weight` | weight `beta` of the travel-time contribution in the combined streamline contribution |
| `kappa_w` | tempering exponent of the flow-fraction weighting |
| `eps_tau`, `eps_f`, `eps_df` | regularisation constants and derivative threshold for breakthrough detection |
| `jump_back`, `jump_fwd` | sampling window around the instantaneous water-cut jump |
| `chi_min`, `chi_max` | per-iteration bounds of the streamline permeability multiplier |
| `PERM_min`, `PERM_max` | geological permeability bounds (mD) |
| `sw_front_min` | minimum saturation gradient required to identify a water front |
| `wcut_fixed_cols` | fallback line numbers for the `wcut` layout when the file has no `SUMMARY OF RUN` markers |
| `write_slnmask_to_poro` | debug switch; when `true` the streamline-visit count is written into the `PORO` keyword of the output GRDECL — **leave `false`**, otherwise the porosity of the model is overwritten |

**Saturation inversion**

| Parameter | Meaning |
| --- | --- |
| `sl_years` | validity window of a streamline snapshot (years) |
| `d_time` | mismatch-sharing constant that sets the saturation-update magnitude (calibrated per case) |
| `TOF_times` | conversion factor from dimensionless streamline TOF to physical time |
| `SW_min`, `SW_max` | saturation clip bounds |
| `max_vary` | maximum saturation change per cell per iteration |
| `decay_times` | divisor of the lower back-projection time bound |
| `sw_decay`, `gain_min` | gain decay factor and its lower bound |
| `mis_tol` | producer freezing tolerance on the mean absolute saturation mismatch |
| `dedup_cells`, `normalize_cnt`, `soft_clip` | cell de-duplication, `sqrt(count)` normalisation of hot cells, `tanh` soft clipping (`false` falls back to hard `min`/`max`) |

## 8. Method → code map

| Manuscript | Where in the code |
| --- | --- |
| grid and geometry | Part 1 (`readGRDECL` / `processGRDECL` / `computeGeometry`) |
| wcut parsing, breakthrough detection, `E_bt`, `E_wc` | Part 2 |
| streamline reading and LGR mapping | Part 3 (`file2Streamline` + `lgrcell2glocell`) |
| minimum-streamline-subset selection, multipliers, projection | Part 5 |
| back-projection of the water-cut mismatch | Part 6 |

## 9. Notes and limitations

* The inversion inherits the **frozen-flow-field** assumption of
  streamline-based methods: within one reconstruction interval the pressure and
  velocity fields are held fixed. The reconstruction interval matches the
  production-data sampling, and the flow field is refreshed after every outer
  iteration.
* All saturation updates are bounded per cell and per producer and decay with
  the iteration index, so the initial hydrocarbon pore volume changes only
  marginally (below 0.2 % in the reported applications).
* The two drivers share one engine but are **not** run with identical
  hyperparameters: `gamma_decay` and the mismatch-sharing constant `d_time` are
  calibrated per case, and the three safeguard mechanisms are only enabled in
  the main case. A single parameter set is not expected to reproduce both case
  studies from a cold start.
* Comments in the source files are written in Chinese; identifiers and all
  documentation are in English.
* `processGRDECL` requires a well-formed Eclipse grid (faults, dipping layers and
  `CARFIN` refinements are handled). `examples/tiny.GRDECL` is only a *format
  sample* for the reader/writer, not a buildable deck.

## 10. License

Released under the **GNU General Public License v3.0** ([`LICENSE`](LICENSE)),
consistent with the MRST ecosystem: `libs/mrst` is redistributed unmodified
under GPL-3.0, which makes the combined work GPL-3.0.

## 11. Citation

If you use this code, please cite the manuscript above. A DOI will be added
after publication. Bug reports and questions are welcome through the GitHub
issue tracker.

---

## 12. 中文说明（摘要）

本仓库是上述论文方法的 MATLAB 实现。每次外层迭代只需**一次** Intersect 正演模拟，
随后在 MATLAB 中同时完成两件事：

1. **初始含水饱和度反演** —— 由生产井含水率失配经流线反投影（特征线法）更新
   `SWAT`，写出 `SW_iter.GRDECL`；
2. **渗透率反演** —— 由见水时间失配与突破后含水增量，经最小流线子集筛选后
   沿流线做乘性修正并投影回网格，更新 `PERMX`，写出 `PERM_iter.GRDECL`。

两个更新共用同一时刻的流线快照，避免初始饱和度误差被渗透率"顶包"。

**依赖**：MATLAB R2020b 及以上即可 —— MRST 已**内置**在 `libs/mrst`
（MRST 2024b 裁剪版，5.5 MB，GPL-3.0），无需另行安装。

**用法**：

```matlab
>> cd streamline-alt-inversion
>> startup                    % 把 src/、examples/ 与内置 MRST 加入路径
>> test_toolbox               % 可选：自检内置工具箱是否完整
>> edit src/main_SL_inversion_C2.m    % 只需改 caseRoot 与 caseName 两行
>> main_SL_inversion_C2
```

运行后把 `PERM_iter.GRDECL` / `SW_iter.GRDECL` 导回模拟器跑下一轮，`iter_index` 加一，重复。

**两份驱动的差异只有 8 行**（见 §5 表格），全部落在配置块内：函数名、头部注释、
`gamma_decay`、三个 safeguard 开关（`w_recent` / `obs_drop_tol` / `osc_damp`）、
失配分摊常数 `d_time`。其余代码逐行一致。

输入文件格式见 [`docs/input_data.md`](docs/input_data.md)；超参数含义见 §7，并与论文公式一一对应。
源码注释为中文。
