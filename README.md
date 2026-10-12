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

## 0. Read this first: two parameters you must set yourself

The drivers ship with the values used in the paper, but two of them are
**case-specific and must not be copied blindly**:

| Parameter | Why you must set it | Where |
| --- | --- | --- |
| **`TOF_times`** | Streamline time-of-flight is **dimensionless**. The code converts it to physical time with `SW_TOF = TOF * TOF_times` (≈ days) to locate the water front before a given date. The factor depends on the simulator's streamline time step / output units, so it changes from case to case. The two cases in this repository use **1500** (C2) and **20000** (WLW). A wrong value shifts the whole back-projection window and the saturation update becomes meaningless — if the saturation update looks wrong, suspect this first. | configuration block |
| **`SW_min`, `SW_max`** | Saturation clip bounds of the update. There is no universal value: `SW_min` is normally the connate water saturation (`S_wc`) or the smallest saturation your model allows, and `SW_max` is normally `1 − S_orw` or the simulator deck's upper limit (the main case uses `0.999883`, taken from the deck). `SW_max` must not exceed the deck limit, or the written field will be truncated on the next run. | configuration block |

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
| 5.5 | water-cut mismatch series | `swat_mismatch` | observed − simulated water cut, per well and per reporting date |
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
* dump them at the same frequency as the production data (monthly in the
  published cases) — the number of `.SLN####` files defines the number of
  snapshots;
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

### 5.5 Water-cut mismatch series — `swat_mismatch`

Per well and per reporting date, the **observed − simulated** water cut (the
quantity the saturation inversion back-projects). Zero means *not used* (the
driver skips zeros); `-1` and `undef` are also read as zero. Layout:
[`docs/input_data.md`](docs/input_data.md) §5,
`examples/swat_mismatch_template.txt`.

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
mis_readpath = fullfile(caseRoot,"swat_mismatch");      % in : mismatch series
krw_readpath = fullfile(caseRoot,"Krw.xlsx");           % in : relative-permeability table

write_slnmask_to_poro = false;    % debug only: write the streamline visit count to PORO
```

If an output path equals its input path, the input file is backed up first as
`<name>.bak_yyyyMMdd_HHmmss`.

## 7. The outer-iteration run book

```text
iter_index = 1  ──►  run the simulator (streamline output ON)
                     export  wcut  and  swat_mismatch  of this run
                     run  main_SL_inversion_XX
                       ├─ writes PERM_iter.GRDECL  (updated PERMX/PERMY/PERMZ)
                       ├─ writes SW_iter.GRDECL    (updated SWAT)
                       └─ writes perm_inversion_summary.txt
iter_index = 2  ──►  import both updated fields into the deck, run the simulator
                     again, re-export wcut + swat_mismatch, run the driver ... repeat
```

* The console prints the current `gamma_eff`, the saturation step `gain`, the
  saturation-change statistics (`最大改变量 …`) and, for every frozen producer,
  the reason. Use these to judge whether the iteration behaved sensibly.
* Stop when the water-cut fit stops improving (the paper selects the stopping
  iteration from the **history-period** fit only, and evaluates prediction once).

## 8. Parameter reference

All parameters are defined in one block at the top of each driver. Parameters
marked **[tune]** are case-specific and were calibrated per reservoir in the
published applications.

**Permeability inversion**

| Parameter | Meaning |
| --- | --- |
| `iter_index` | current outer-iteration index (1 at the first iteration with a streamline dump) |
| `gamma_relax`, `gamma_decay` | relaxation factor and its geometric decay, `gamma_eff = gamma_relax * gamma_decay^(iter_index-1)` |
| `fit_tol` | producer freezing tolerance: wells whose mean relative water-cut error is below it are not corrected this iteration |
| `swing_hi`, `swing_boost` | critical band `[fit_tol, swing_hi)` and the step amplification applied inside it |
| `e_bt_tol`, `e_wc_tol` | dead zones of the breakthrough-time and water-cut-level signals |
| `w_bt` | weight of the breakthrough-time signal (the water-cut-level signal takes `1 - w_bt`) |
| `beta_weight` | weight `beta` of the travel-time contribution in the combined streamline contribution |
| `kappa_w` | tempering exponent of the flow-fraction weighting (`1` = strict flow weighting) |
| `eps_tau`, `eps_f`, `eps_df` | regularisation constants and the derivative threshold used for breakthrough detection |
| `jump_back`, `jump_fwd` | sampling window around the instantaneous water-cut jump |
| `chi_min`, `chi_max` | per-iteration bounds of the streamline permeability multiplier |
| `PERM_min`, `PERM_max` | geological permeability bounds (mD) |
| `sw_front_min` | minimum saturation gradient required to identify a water front on a streamline |
| `fix_etot_combine` | combine the two signals *before* the `tanh` (avoids the saturation-induced cancellation of large mismatches) |
| `fix_break_fallback` | fall back to "first time the water cut exceeds `wct_break_thr`" when the derivative criterion finds no breakthrough |
| `wct_break_thr` **[tune]** | water-cut threshold of that fallback |
| `sln_expand_nb` **[tune]** | number of snapshots to expand forward/backward when the frozen snapshot contains no streamline ending at the well (`0` disables) |
| `make_plots` | draw per-well diagnostic figures |
| `write_slnmask_to_poro` | **debug only.** When `true`, the streamline visit count overwrites the `PORO` keyword of the written GRDECL — leave it `false` for production runs |

**Saturation inversion**

| Parameter | Meaning |
| --- | --- |
| `miuo`, `miuw` | oil / water viscosity used when building `f_w(S_w)` from `Krw.xlsx` |
| `sl_years` | validity window of a streamline snapshot (years) |
| `alpha` | explicit step factor applied to the accumulated mismatch (`1` in the reported applications) |
| `TOF_times` **[must be tuned]** | dimensionless-TOF → physical-time conversion factor (§0) |
| `SW_min`, `SW_max` **[must be set by you]** | saturation clip bounds (§0) |
| `max_vary` | maximum saturation change per cell and per iteration (before the decay gain) |
| `decay_times` | divisor of the lower back-projection time bound |
| `endtime_weight` | **unused** (kept from the original codes) |
| `sw_decay` | per-iteration gain decay, `gain = sw_decay^(iter_index-1)` |
| `mis_tol` | producer freezing tolerance on the mean absolute saturation mismatch |
| `dedup_cells` | de-duplicate cells in the single-point write mode |
| `normalize_cnt` | divide the update of repeatedly touched cells by `sqrt(count)` (hot-spot suppression) |
| `soft_clip` | `tanh` soft clipping of the update (`false` → hard `min`/`max`) |
| `sw_write_mode` | `"single"` = write only the front cell `GLO_CELL(k_i)` (original behaviour); `"segment"` = spread the same total over the whole `[k_i → well]` segment |
| `sw_seg_weight` | in-segment weights: `"uniform"` or `"end_boost"` (uniform + extra weight on the last `sw_end_cells` cells) |
| `sw_end_cells`, `sw_end_frac` **[tune]** | number of well-end cells that must receive an update and the share of the update given to them |
| `sw_seg_maxlen` **[tune]** | maximum segment length (cells); `0` = unlimited |
| `sw_dedup_seg` | keep per-cell de-duplication in segment mode (default `false`; see the comment in the driver) |

## 9. Differences between the two drivers

| Aspect | `main_SL_inversion_C2` (main case) | `main_SL_inversion_WLW` (second case) |
| --- | --- | --- |
| configuration block | its own paths | its own paths |
| `TOF_times` | `1500` | `20000` |
| `wcut` reading | blocks found automatically via `SUMMARY OF RUN`; the simulated block is matched by `caseName`, the observed block by `Observed` | fixed line numbers `wcut_fixed_cols = [7 12 310 318 323 621]` |
| date parsing | `parse_run_date` (Chinese locale `zh_CN`, e.g. `01-1月-1995`) for both files | plain `datetime(...)` (ISO-style dates) |
| `swat_mismatch` reading | number of steps taken from the header (line 4) | all lines from 12 up to the last one |
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
| mismatch series reading | Part 3 |
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
* `TOF_times` and the saturation bounds are **not** universal constants — see §0.
* The two drivers share one engine but they were **not** run with identical
  per-case settings: `TOF_times` differs, the `wcut` layouts differ, and the
  saturation-write parameters (`sw_end_cells`, `sw_seg_maxlen`) are
  case-specific. A single parameter set is not expected to reproduce both case
  studies from a cold start.
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

1. **初始含水饱和度反演** —— 由生产井含水率失配（`swat_mismatch`）经流线反投影
   （特征线法）更新 `SWAT`，写出 `SW_iter.GRDECL`；
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

**必须自己确定的两件事**（详见 §0）：

* `TOF_times`：流线 TOF 无量纲量 → 物理时间的换算倍数，与模拟器的流线时间步长/单位
  有关，**不能照搬**。本仓库两个案例分别取 1500（C2）与 20000（WLW）。取错会让反投影
  时间窗整体错位，饱和度修正完全打不准 —— 结果异常时先查这个参数。
* `SW_min` / `SW_max`：饱和度更新的截断上下限，通常分别取束缚水饱和度与
  `1 − S_orw`（或 deck 的含水饱和度上限）；`SW_max` 不能超过 deck 上限，否则下一轮
  模拟会把写出的场截断。

**需要准备的输入**（详见 §5 与 [`docs/input_data.md`](docs/input_data.md)）：

| 输入 | 怎么来 |
| --- | --- |
| `PERM_iter.GRDECL` | 从 Petrel 导出网格属性：勾选 `PERMX/PERMY/PERMZ/NTG`，并保留 `SPECGRID/COORD/ZCORN/ACTNUM` 几何 |
| `SW_iter.GRDECL` | 同上，勾选 `SWAT`（初始含水饱和度）与 `NTG` |
| `model.sim/<caseName>/*.SLN*` | **由算例模型导出**：模拟器打开流线输出，产出 `<caseName>.SLNSPEC` 与 `.SLN0001…`，与生产数据同频率 |
| `wcut` | 模拟块（本轮井含水率）+ 实测块（油田生产历史）拼成一个文本文件 |
| `swat_mismatch` | 逐井逐时刻的"实测 − 模拟"含水率之差（即含水率误差序列） |
| `Krw.xlsx` | 相渗数据：三列 `Sw / krw / kro`（当前算法未用到其派生曲线，但启动时会读取） |

两份驱动的差异只有（1）配置块（读取路径 + `TOF_times`）与（2）`wcut` 读取段
（C2 按 `SUMMARY OF RUN` 自动分块，WLW 用固定行号 `wcut_fixed_cols`），其余逐行一致。
源码注释为中文。
