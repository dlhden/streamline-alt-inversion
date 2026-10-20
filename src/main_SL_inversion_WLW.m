function main_SL_inversion_WLW()
% =========================================================================
% Streamline-based alternating inversion of initial water saturation and
% permeability -- combined driver, second case (WLW block)
%
%   One call performs ONE outer iteration and writes both updated fields:
%     - permeability correction   -> PERM_outpath   (PERMX / PERMY / PERMZ)
%     - initial water saturation  -> SW_writepath   (SWAT)
%
%   Workflow (one simulator run per outer iteration):
%       run N  (Intersect, with streamline output)
%         -> this driver  (reads streamlines + wcut; the water-cut mismatch is
%                          built internally from the two wcut blocks)
%         -> PERM_iter.GRDECL / SW_iter.GRDECL
%         -> run N+1 (Intersect) ...   and set iter_index = N+1
%
% 中文说明
% -------------------------------------------------------------------------
% 合并版：渗透率反演 + 含水饱和度反演（一次运行，同时输出两套修正）。
% 同一轮模拟结果（流线 + wcut）同时驱动两类修正，
% 每轮只需一次 Intersect；两类修正共用 iter_index 轮次计数，各自保留独立衰减
% 因子 gamma_decay（渗透率）与 sw_decay（饱和度）。
%
% 本文件与另一案例驱动（main_SL_inversion_C2.m）的差异只有两处：
%   (1) 配置块：读取路径 + TOF_times；
%   (2) 第二部分（wcut 读取）——本案例的 wcut 为「单块」导出（模拟部分 +
%       实测部分），按 wcut_fixed_cols 给出的固定行号读取；C2 版则按
%       'SUMMARY OF RUN' 自动分块。其余算法、参数与计算段两版逐行一致。
%
% 本案例模型：五里湾 WLW 区块，含 CARFIN 局部网格加密（流线网格自动映射
%   回全局网格），PERMX / PERMY / SWAT / NTG 关键字齐全。

% 用法：第 1 轮 iter_index = 1，之后每轮 +1。输出路径与输入相同时会自动
%   备份输入文件为 <name>.bak_时间戳。
%
% 需要准备的数据（第 1、2、5 项一次性；第 3、4 项每轮）
% -------------------------------------------------------------------------
%   1) PERM_iter.GRDECL   当前渗透率场（PERMX/PERMY/PERMZ/NTG + 网格几何），Petrel 导出，仅第 0 轮
%   2) SW_iter.GRDECL     当前初始含水饱和度场（SWAT/NTG），建模初始条件产出，仅第 0 轮
%   3) <caseName>.SLNSPEC + .SLN0001 ...   本轮模拟的流线（模拟器打开流线输出），每轮
%   4) wcut               模拟块（与本轮算例同名）+ 实测块（含 Observed），每轮；
%                         失配 Δf_w = f_w^sim - f_w^obs 由这两块内部求差，无需另导
%   5) Krw.xlsx           Sw/krw/kro 相渗表；必须存在（驱动会读），当前仅用于生成
%                         fw 曲线供诊断，修正量本身不依赖它
%
% 参数分三类（完整说明见 README §8）
% -------------------------------------------------------------------------
% [A] 必须按自己的油藏标定，论文值属于两个已发表算例，不能照搬：
%       TOF_times（1500=C2 / 20000=WLW，差 13 倍）、SW_min/SW_max、
%       PERM_min/PERM_max、miuo/miuw、wct_break_thr、
%       kappa_w + df_obs_mode（成对标定：WLW 最优点 0.5 + 两步窗口，
%       主案例最优点 1.5 + [t_b,t_e]；见 README §8.1.1 的扫描方法）
%       sl_years、wcut_fixed_cols（仅 WLW 版）、caseRoot/caseName
% [B] 可直接沿用论文值（两个油藏、1006 与约 1000 口井均未改动）：
%       gamma_relax=1, gamma_decay=0.9, fit_tol=0.20, swing_hi=0.40,
%       swing_boost=1.5, e_bt_tol=0.10, e_wc_tol=0.15, w_bt=0.5,
%       beta_weight=0.5, eps_tau=1e-3, eps_f=1e-4, eps_df=0.01,
%       jump_back/jump_fwd=1, chi_min/chi_max=0.5/2.0, sw_front_min=0.05,
%       alpha=1, max_vary=1, decay_times=3, sw_decay=0.9, mis_tol=0.05,
%       dedup_cells/normalize_cnt/soft_clip=true,
%       sw_write_mode="segment", sw_seg_weight="end_boost", sw_dedup_seg=false
% [C] 可沿用，但网格尺度或快照间隔差得多时须按比例改：
%       sw_end_cells=5, sw_end_frac=0.5, sw_seg_maxlen=150, sln_expand_nb=2
% =========================================================================

%% ------------------------- 路径设置（EDIT THIS BLOCK）-------------------
caseRoot = "path/to/your/case";   % <<< 案例工作目录
caseName = "CASE1";               % <<< 本轮算例名

PERM_path    = fullfile(caseRoot,"PERM_iter.GRDECL");   % 输入：当前渗透率场
PERM_outpath = fullfile(caseRoot,"PERM_iter.GRDECL");   % 输出：更新后渗透率场
SW_path      = fullfile(caseRoot,"SW_iter.GRDECL");     % 输入：当前饱和度场
SW_writepath = fullfile(caseRoot,"SW_iter.GRDECL");     % 输出：更新后饱和度场
SLN_headpath = fullfile(caseRoot,"model.sim",caseName); % 输入：本轮流线目录（<caseName>.SLNSPEC / .SLN0001 ...）
wcut_readpath= fullfile(caseRoot,"wcut");               % 输入：含水率文件（模拟块 + 实测块）
krw_readpath = fullfile(caseRoot,"Krw.xlsx");           % 输入：相渗曲线（饱和度反演用）

% 含水率失配 Δf_w = f_w^sim - f_w^obs 由 wcut 的模拟块与实测块内部求差生成，
% 见第三部分；不需要任何单独的失配数据文件。

% 调试开关：把「流线经过次数」写入输出 GRDECL 的 PORO 字段。
% 默认 false —— 置 true 会用流线计数覆盖模型孔隙度，仅供诊断，不要用于正式模拟。
write_slnmask_to_poro = false;

% wcut 固定行号布局（本案例导出为「单块」格式，文件内无 SUMMARY OF RUN 标记）：
%   [模拟井名行, 模拟数据起, 模拟数据止, 实测井名行, 实测数据起, 实测数据止]
% 你自己的导出如果不是这个布局，改这一行即可；若文件带 SUMMARY OF RUN 分块
% 标记，可参照另一案例驱动（main_SL_inversion_C2.m）的第二部分按块自动识别。
wcut_fixed_cols = [7 12 310 318 323 621];

% --------------------------- 共用轮次参数 -------------------------------
iter_index  = 1;      % 当前反演轮次（第 1 轮填 1，之后每轮 +1）

% 参数分类：[A] 必须按本油藏标定（论文值属于两个已发表算例，不可照搬）
%           [B] 可直接沿用论文值   [C] 沿用后按网格尺度/快照间隔调整
% --------------------- 渗透率反演参数（v2 算法）-------------------------
gamma_relax = 1;    % Eq.(39) 松弛因子 gamma，控制修正步长
gamma_decay = 0.9;    % 逐轮衰减因子：gamma_eff = max(gamma_relax * gamma_decay^(iter_index-1), gamma_min)
gamma_min   = 0;      % 步长下限（<1012 版为 0.5>）；置 0 表示不设下限。
                      % 与旧版逐位对齐时：gamma_relax=5、gamma_min=0.5（1012 版即此设置），
                      % 否则同一份数据算出的渗透率乘子会相差约 5 倍。
fit_tol     = 0.20;   % 井冻结门限：含水率平均相对误差 < fit_tol 的井本轮不修正
e_bt_tol    = 0.10;   % 见水时间失配死区：|E_bt| < e_bt_tol 的井不做修正
w_bt        = 0.5;    % v2 见水时间驱动权重 w_bt（含水率水平驱动权重为 1-w_bt）
e_wc_tol    = 0.15;   % v2 含水率水平失配死区：|E_wc| < e_wc_tol 视为水平已匹配
swing_hi    = 0.40;   % v2 临界井上界：wc_err ∈ [fit_tol, swing_hi] 的井为临界井
swing_boost = 1.5;    % v2 临界井步长放大倍数（直接面向 <20% 达标指标）
beta_weight = 0.5;    % Eq.(33) 组合贡献权重 beta（TOF 与饱和度贡献之间）
kappa_w     = 0.5;    % [A] Eq.(30) 流量份额调和指数 kappa（表 5：WLW 标定最优 0.5，主案例自身最优 1.5）
df_obs_mode = 'two_sample';  % [A] Eq.(35) 实测增量窗口：'two_sample'（前后各 1 步，论文默认）| 'stage'（[t_b,t_e]）
eps_tau     = 1e-3;   % Eq.(31-32) TOF 正则化常数（与 TOF 同单位）
eps_f       = 1e-4;   % Eq.(36) 含水率增量正则化常数
eps_df      = 0.01;   % 含水率导数阈值（见水识别 + 上升阶段结束判据）
jump_back   = 1;      % Eq.(35) 瞬时跳变窗口：见水前 jump_back 个采样点
jump_fwd    = 1;      % Eq.(35) 瞬时跳变窗口：见水后 jump_fwd 个采样点
chi_min     = 0.5;    % Eq.(39) 流线乘子下限
chi_max     = 2.0;    % Eq.(39) 流线乘子上限
PERM_min    = 0.01;   % [A] 渗透率地质下限 (mD)
PERM_max    = 800;    % [A] 渗透率地质上限 (mD)
sw_front_min= 0.05;   % 判定流线存在明显水线前缘的最小 SW 梯度
make_plots  = false;  % 是否绘制单井诊断图

% ------------- [同步修复] "大误差井零修正"三处结构性缺陷开关（C2/WLW 同步）----
% 修复逻辑两版完全一致；标注 [标定] 的参数可按油藏分别调整。
fix_etot_combine   = true;  % [修复②] 组合驱动改"先加权求和再 tanh"，避免同号信号饱和后完全抵消
fix_break_fallback = true;  % [修复③] 见水识别回退：导数阈值法无解时改用"首超阈值时刻"
wct_break_thr      = 0.02;  % [修复③][A] 见水回退阈值：含水率首次超过该值即视为见水
sln_expand_nb      = 2;     % [修复①][C] 冻结快照无候选流线时向前后各扩展的快照数（0=关闭退回原行为）

% --------------------- 饱和度反演参数（v2 算法）-------------------------
miuo = 2.8;   % [A] 原油粘度 (mPa·s)
miuw = 1;     % [A] 水粘度 (mPa·s)
sl_years = 6;   % [A] 单帧流线快照的有效期（年），按快照间隔与资料跨度取
alpha = 1;
% ================== !!! TOF_times 必须按案例标定，不能照搬 !!! ==================
% 流线 TOF 是无量纲量，本代码用 SW_TOF = TOF * TOF_times（近似为「天」）把它换算
% 成物理时间，用于确定"某时刻之前水线前缘的位置"（反投影时间窗）。该换算倍数与
% 模拟器的流线时间步长 / 输出单位有关，不同油藏、不同算例都不能套用：
%   - 本仓库两个案例分别取 1500（C2，370x252x12）与 20000（WLW）；
%   - 倍数不对时反投影时间窗整体错位，饱和度修正的方向和幅度都会不对 —— 结果
%     异常时请先检查这个参数。
% 建议：先试算 1~2 轮，观察运行时打印的"饱和度计算完成，最大改变量…"以及含水率
%   拟合曲线是否朝正确方向变化，再据此调大 / 调小倍数量级。
TOF_times = 20000;    % 流线 TOF 无量纲 -> 物理时间换算倍数（SW_TOF = TOF * TOF_times，近似为天）

% ================= 饱和度上下限必须由用户自行确定 ==========================
% SW_min / SW_max 是饱和度更新的物理截断边界，取决于你的模型和相渗曲线，
% 不存在通用取值：
%   SW_min —— 通常取束缚水饱和度（或模型允许的最小含水饱和度）；
%   SW_max —— 通常取 1 - S_orw，或模拟器 deck 中的含水饱和度上限
%              （本案例的 0.999883 即取自 deck 上限）。
% 注意 SW_max 必须不超过 deck 的上限，否则写出的 SW_iter.GRDECL 会被模拟器
% 在下次运行时截断。本案例 SW_min = 0.01 相当于不额外约束（初始场各处的含水
% 饱和度都已高于束缚水）。
SW_min = 0.01;
SW_max = 0.999883;

max_vary = 1;
decay_times = 3;
endtime_weight = 3;
sw_decay    = 0.9;    % 逐轮衰减因子：gain = sw_decay^(iter_index-1)
mis_tol     = 0.05;   % 井冻结门限：平均|饱和度失配| < mis_tol 的井本轮不修正
dedup_cells = true;   % 恢复同一流线单元的去重（防止同一网格被反复修正）
normalize_cnt = true; % v2 按 sqrt(计入次数) 归一化热点网格修正量
soft_clip     = true; % v2 tanh 软截断（false 退回 max/min 硬截断）

% ------------- [修复A] 饱和度写入方式：k_i 单点 -> k_i→井端分段（C2/WLW 同步）----
% 背景：原实现每条流线只写 1 个网格 GLO_CELL(k_i)（水的前缘位置，多落在流线中部），
%       诊断实测（C2，955 口失配井）：36.2% 的井端网格 ΔSW 恒为 0，井含水率几乎不动。
% 修复：把该条流线的修正总量按权重分配到 [k_i, 井端] 整段（总量守恒），并保证井端
%       sw_end_cells 个网格必获修正；段长上限防极长流线一次改太多网格。
sw_write_mode = "segment";  % "single"=原行为(单点 GLO_CELL(k_i)) | "segment"=k_i→井端分段写入
sw_seg_weight = "end_boost";% 段内权重："uniform" 段内均匀 | "end_boost" 均匀 + 井端加强（推荐）
sw_end_cells  = 5;          % [C] 井端强制参与的网格数 b（建议 3~5）
sw_end_frac   = 0.5;        % [C] 分配给井端 b 个网格的修正量占比（其余均匀铺满整段）
sw_seg_maxlen = 150;        % [C] 分段长度上限（0=不限制）；超限时向井端收缩
sw_dedup_seg  = false;      % 分段模式是否保留"同井同网格只计一次"去重（默认 false，理由见下）
%       说明：分段模式下若沿用逐格去重，井端网格只会被该井第一条流线写入一次、其余全部
%             被丢弃 -> 修复失效。热点网格仍由 SWAT_cnt + sqrt 归一化 + tanh 软截断控制；
%             需严格复刻原去重语义时置 sw_dedup_seg = true。


% =========================================================================
% 第一部分：读取网格（渗透率场 + 饱和度场共用同一套网格与 LGR 信息）
% =========================================================================
disp('读取原始文件中')
filelist = readtxtfile(PERM_path);
disp('读取网格数据中')
grdecl_perm = readGRDECL(PERM_path,'keywords',{'PERMX','PERMY','PERMZ','NTG'});
disp('处理网格数据中')
G = processGRDECL(grdecl_perm);
G = computeGeometry(G);

[xdim,ydim,zdim] = deal(G.cartDims(1),G.cartDims(2),G.cartDims(3));
gridnum = xdim*ydim*zdim;

PERMXnumarray = grdecl_perm.PERMX;
PERMYnumarray = grdecl_perm.PERMY;
PERMXnumarray = min(PERMXnumarray, PERM_max);
PERMXnumarray = max(PERMXnumarray, PERM_min);
PERMYnumarray = min(PERMYnumarray, PERM_max);
PERMYnumarray = max(PERMYnumarray, PERM_min);
% PERMZ 与 PERMX/PERMY 同步修正（同一 dlnK 乘子，保持 Kv/Kh 各向异性比不变）；
% 若 GRDECL 中无 PERMZ 关键字则跳过，不影响主流程
has_PERMZ = isfield(grdecl_perm,'PERMZ') && ~isempty(grdecl_perm.PERMZ);
if has_PERMZ
    PERMZnumarray = grdecl_perm.PERMZ;
    PERMZnumarray = min(PERMZnumarray, PERM_max);
    PERMZnumarray = max(PERMZnumarray, PERM_min);
else
    warning('PERM_iter.GRDECL 中未找到 PERMZ 关键字，本轮仅修正 PERMX/PERMY');
end

% LGR 信息（若模型含局部网格加密，流线 CELL 需转换到全局网格）
LGRcell = {};
for i = 1:size(filelist,2)
    if contains(filelist{i},'CARFIN                                 -- Generated : Petrel')
        LGRcell{end+1,1} = filelist{i+1};
    end
end
lgr_glo = zeros(0,6);
lgr_sum = zeros(0,3);
for i = 1:size(LGRcell,1)
   t = split(LGRcell{i,1});
   lgr_glo(end+1,:) = str2double(t(3:8)');
   lgr_sum(end+1,:) = str2double(t(9:11)');
end
lgr_binsta = [gridnum; gridnum + cumsum(lgr_sum(1:end-1,1).*lgr_sum(1:end-1,2).*lgr_sum(1:end-1,3))];
lgr_binend = gridnum + cumsum(lgr_sum(:,1).*lgr_sum(:,2).*lgr_sum(:,3));

% ------------------------- 读取饱和度场 ---------------------------------
disp('读取饱和度场中')
grdecl_sw = readGRDECL(SW_path,'keywords',{'SWAT','NTG'});
NTG = grdecl_sw.NTG;
SWATnumarray = grdecl_sw.SWAT;
SWATnumarray = min(SWATnumarray, SW_max);
SWATnumarray = max(SWATnumarray, SW_min);
if isfield(grdecl_sw,'ACTNUM')
    ACTNUM = double(grdecl_sw.ACTNUM & NTG > 0);
else
    ACTNUM = double(NTG > 0);
end

% ------------------------- 读取相渗曲线 ---------------------------------
disp('读取Krw文件中')
krw_data = xlsread(krw_readpath);
fw_data = zeros(length(krw_data),2);
fw_data(:,1) = krw_data(:,1);
fw_data(:,2) = krw_data(:,2)/miuw./(krw_data(:,2)/miuw+krw_data(:,3)/miuo);

% =========================================================================
% 第二部分：读取含水率时间序列（wcut，渗透率反演用）
% =========================================================================
% wcut 文件布局由配置块中的 wcut_fixed_cols 给出（见文件头说明）
disp('读取含水率时间序列数据矩阵')
mislist_wc = readtxtfile(wcut_readpath);

w_c_l = wcut_fixed_cols(1);  d_c_s = wcut_fixed_cols(2);  d_c_e = wcut_fixed_cols(3);
w_o_l = wcut_fixed_cols(4);  d_o_s = wcut_fixed_cols(5);  d_o_e = wcut_fixed_cols(6);

raw_w_c = split(strtrim(mislist_wc{w_c_l}))';
raw_w_c = raw_w_c(3:end);
raw_w_o = split(strtrim(mislist_wc{w_o_l}))';
raw_w_o = raw_w_o(3:end);

mis_datetime_wc = {};
data_case = zeros(0,numel(raw_w_c));      % 模拟含水率 f_w^sim
valid_case = false(0,numel(raw_w_c));     % 有效标记（undef = 缺测，internal 失配不计入）
for i = d_c_s:d_c_e
    tempt = split(strtrim(mislist_wc{i}));
    vm = ~strcmp(tempt,'undef');                          % 该行各列是否缺测
    tempt(~vm) = {'0'};
    mis_datetime_wc{end+1} = datetime(tempt{1});
    data_case(end+1,:) = str2double(tempt(4:end));
    valid_case(end+1,:) = vm(4:end);
end
mis_datetime_wc = [mis_datetime_wc{:}];
data_case(data_case==-1) = 0;

mis_datetime_wo = {};
data_observed = zeros(0,numel(raw_w_o));  % 实测含水率 f_w^obs
valid_observed = false(0,numel(raw_w_o));
for i = d_o_s:d_o_e
    tempt = split(strtrim(mislist_wc{i}));
    vm = ~strcmp(tempt,'undef');
    tempt(~vm) = {'0'};
    mis_datetime_wo{end+1} = datetime(tempt{1});
    data_observed(end+1,:) = str2double(tempt(4:end));
    valid_observed(end+1,:) = vm(4:end);
end
mis_datetime_wo = [mis_datetime_wo{:}];
data_observed(data_observed==-1) = 0;

% ----------- 平滑曲线、导数、见水时刻识别（Eq.27 与 Eq.35 的判据） --------
nTime = size(data_case,1);

break_time_case      = cell(1,size(data_case,2));
start_time_case      = zeros(1,size(data_case,2));
break_time_observed  = cell(1,size(data_observed,2));
start_time_observed  = zeros(1,size(data_observed,2));
df_case      = zeros(size(data_case));       % 模拟含水率导数
df_observed  = zeros(size(data_observed));   % 实测含水率导数
ds_case      = zeros(size(data_case));       % 平滑后的模拟含水率
ds_observed  = zeros(size(data_observed));   % 平滑后的实测含水率
df_case_s    = zeros(size(data_case));       % 高斯平滑导数（阶段判据用）
df_observed_s= zeros(size(data_observed));

for i = 1:size(data_case,2)
    d = data_case(:,i);
    d(d==0) = nan;
    ds_case(:,i) = smoothdata(d,'movmedian',12);
    d = ds_case(:,i);
    nanmask = isnan(d);
    idx = find(~nanmask);
    d_nonan = d(~nanmask);
    df = [0;diff(d_nonan,1)];
    df(1:min(24,length(df))) = 0;
    df_case(~nanmask,i) = df;
    df_case_s(:,i) = smoothdata(df_case(:,i),'gaussian',24);
    d_mask = df > eps_df;
    fi_f = idx(d_mask);
    if numel(fi_f) > 0
        f_list = 1;
        for j = 2:numel(fi_f)
            if fi_f(j) - fi_f(j-1) > 12
                f_list = [f_list, j];
            end
        end
        break_time_case{i} = fi_f(f_list);
    else
        break_time_case{i} = nan;
    end
    fi_s = find(data_case(:,i)>0,1);
    if numel(fi_s) > 0, start_time_case(i) = fi_s; else, start_time_case(i) = nan; end
end

for i = 1:size(data_observed,2)
    d = data_observed(:,i);
    d(d==0) = nan;
    d = smoothdata(d,"movmedian",72);
    ds_observed(:,i) = d;
    nanmask = isnan(d);
    idx = find(~nanmask);
    d_nonan = d(~nanmask);
    df = [0;diff(d_nonan,1)];
    df(1:min(24,length(df))) = 0;
    df_observed(~nanmask,i) = df;
    d_mask = df > eps_df;
    d_mask(1:24) = 0;
    fi_f = idx(d_mask);
    if numel(fi_f) > 0
        f_list = 1;
        for j = 2:numel(fi_f)
            if fi_f(j) - fi_f(j-1) > 12
                f_list = [f_list, j];
            end
        end
        break_time_observed{i} = fi_f(f_list);
    else
        break_time_observed{i} = nan;
    end
    df_observed_s(:,i) = smoothdata(df_observed(:,i),'gaussian',24);
    fi_s = find(data_observed(:,i)>0,1);
    if numel(fi_s) > 0, start_time_observed(i) = fi_s; else, start_time_observed(i) = nan; end
end

% ---- [修复③] 见水识别加固 -------------------------------------------------
% 原判据只用"平滑后月度导数 > eps_df，且前 24 个非零月导数强制清零"，导致两类井
% 两侧都识别不到见水而被整井丢弃：①含水已高、曲线平缓的老井；②投产 2 年内即见水
% （落在被清零窗口内）的井。回退：改取"首个含水率超过 wct_break_thr 的时刻"。
% 仅当导数法结果为 NaN 时启用，不改变原判据已能识别的井。
if fix_break_fallback
    for i = 1:numel(break_time_case)
        if isnan(break_time_case{i}(1))
            kk = find(data_case(:,i) > wct_break_thr, 1);
            if ~isempty(kk), break_time_case{i} = kk; end
        end
    end
    for i = 1:numel(break_time_observed)
        if isnan(break_time_observed{i}(1))
            kk = find(data_observed(:,i) > wct_break_thr, 1);
            if ~isempty(kk), break_time_observed{i} = kk; end
        end
    end
end

% 实测井 -> 模拟井 的映射
obswid2casewid = -ones(size(raw_w_o));
for i = 1:numel(obswid2casewid)
   wn = raw_w_o{i};
   wi = find(string(raw_w_c) == wn, 1);
   if ~isempty(wi), obswid2casewid(i) = wi; end
end

% ---- 井级含水率平均相对误差（用于冻结已达标井，与 65.84% 指标同口径）----
% err_i = mean_t |f_sim - f_obs| / mean_t f_obs（仅统计实测含水率 > 0 的时刻）
% v2 同时记录带符号误差：E_wc_raw > 0 表示模拟含水率整体偏高（需降渗）
wc_err        = nan(1,size(data_observed,2));
wc_err_signed = nan(1,size(data_observed,2));
for i = 1:size(data_observed,2)
    ci = obswid2casewid(i);
    if ci <= 0, continue; end
    o = data_observed(:,i);
    s = data_case(:,ci);
    v = o > 0;
    if nnz(v) > 0
        wc_err(i)        = mean(abs(s(v) - o(v))) / max(mean(o(v)), eps);
        wc_err_signed(i) = mean(s(v) - o(v)) / max(mean(o(v)), eps);
    end
end

% =========================================================================
% 第三部分：含水率失配时间序列（由 wcut 两块内部生成，饱和度反演用）
%   Δf_w(k,j) = f_w^sim(k,j) - f_w^obs(k,j)
%   即同一口井、同一报告日期的模拟含水率减实测含水率；正值表示模型见水偏早，
%   饱和度修正方向相应为调低。两块任一时刻缺测（undef）则不计入该格（记 0，
%   下游按"0 = 不参与"处理）。
% 井的对应：以模拟块井序为主，按井名在实测块中查找；两块井集与井序都可能不同，
%   故必须回查原始列号（cidx），不能直接用压缩后的下标。
% 时间轴：末端的"整块无实测数据"时刻（全部 undef 或全部为 0）说明该时刻实测
%   尚未录入，直接作差会把 Δf = f^sim 当成失配，故自末尾向前剔除。
% =========================================================================
disp('由 wcut 模拟块与实测块构造含水率失配')

% ---- 井名对应：模拟块为主序，仅保留实测块中同时存在的井 ----
miswid_obs = zeros(1, numel(raw_w_c));
for i = 1:numel(raw_w_c)
    wi = find(strcmp(raw_w_o, raw_w_c{i}), 1);
    if ~isempty(wi), miswid_obs(i) = wi; end
end
keep  = miswid_obs > 0;
cidx  = find(keep);               % 保留井在模拟块中的原始列号
mis_wellnames = raw_w_c(cidx);
miswid_obs    = miswid_obs(cidx);

% ---- 时间轴：两块长度取交集，剔除末端无实测数据的时刻 ----
nChk = min(numel(mis_datetime_wc), numel(mis_datetime_wo));
if nChk > 0 && any(mis_datetime_wc(1:nChk) ~= mis_datetime_wo(1:nChk))
    warning('wcut 模拟块与实测块的时间轴不一致，按行号对齐可能错位');
end
nMisT  = max(min(size(data_case,1), size(data_observed,1)), 1);
obs_has_data = any(valid_observed & data_observed ~= 0, 2);
while nMisT > 1 && ~obs_has_data(nMisT)
    nMisT = nMisT - 1;
end
% 下游按元胞逐元素访问（mis_datetime{j} 取单个时刻），故此处转成元胞
mis_datetime = num2cell(mis_datetime_wc(1:nMisT));

% ---- 逐井逐时刻作差 ----
mis_data = zeros(nMisT, numel(mis_wellnames));
for j = 1:numel(mis_wellnames)
    jc = cidx(j);
    io = miswid_obs(j);
    for k = 1:nMisT
        if valid_case(k,jc) && valid_observed(k,io)
            mis_data(k,j) = data_case(k,jc) - data_observed(k,io);
        end
    end
end
mis_data(~isfinite(mis_data)) = 0;
fprintf('含水率失配：%d 口井（模拟 %d ∩ 实测 %d，丢弃 %d 口无实测井），%d 个时刻\n', ...
    numel(mis_wellnames), numel(raw_w_c), numel(raw_w_o), ...
    numel(raw_w_c) - numel(mis_wellnames), nMisT);

% =========================================================================
% 第四部分：读取流线（只读一次，两套反演共用）
%   同时为饱和度反演准备 END_CELL / SW_TOF / endcell_wellid / sln_mask
% =========================================================================
SLNN = 0;
filelist_sln = dir(SLN_headpath);
for i = 1:length(filelist_sln)
    if ~filelist_sln(i).isdir
        if regexp(filelist_sln(i).name,'.*\.SLN\d{4}$','once')
            SLNN = SLNN + 1;
        end
    end
end

case_name = split(SLN_headpath,filesep);
case_name = case_name{end};

spec = readEclipseOutputFileUnFmt(fullfile(SLN_headpath, sprintf("%s.SLNSPEC",case_name)));
wellnames = arrayfun(@(x)string(x{1}),spec.NAMES.values);

disp('开始读取流线（合并版只读一次）')
sln_list      = cell(SLNN,1);
sln_datetime  = cell(SLNN,1);
sln_endlist   = cell(SLNN,1);

endcell_wellid = -ones(gridnum,1);        % 饱和度反演用：井端网格 -> 井号
sln_mask       = zeros(gridnum,1);        % 饱和度反演用：流线经过次数

wbar = waitbar(0, '读取流线中...');
for k = 1:SLNN
    sln = readEclipseOutputFileUnFmt(fullfile(SLN_headpath, sprintf("%s.SLN%04d",case_name,k)));
    m_sln = file2Streamline(sln,'SLN');
    for i = 1:size(m_sln,1)
       m_sln(i,1).GLO_CELL = m_sln(i,1).CELL;
       for j = 1:size(m_sln(i,1).GLO_CELL,1)
           if m_sln(i,1).GLO_CELL(j,1) > gridnum
               [~,~,~,glo_c] = lgrcell2glocell(m_sln(i,1).GLO_CELL(j,1), lgr_binsta, lgr_binend, lgr_glo, lgr_sum, xdim, ydim, zdim);
               m_sln(i,1).GLO_CELL(j,1) = glo_c;
           end
       end
       % 饱和度反演附加字段
       m_sln(i,1).END_CELL = m_sln(i,1).GLO_CELL(end);
       m_sln(i,1).SW_TOF   = m_sln(i,1).TOF * TOF_times;
       endcell_wellid(m_sln(i,1).END_CELL) = m_sln(i,1).END;
       sln_mask(m_sln(i,1).GLO_CELL) = sln_mask(m_sln(i,1).GLO_CELL) + 1;
    end
    sln_list{k} = m_sln;
    tv = sln.INTEHEAD.values;
    sln_endlist{k} = arrayfun(@(x)x.END,m_sln);
    sln_datetime{k} = datetime(tv(7),tv(6),tv(5));
    waitbar(k/SLNN,wbar)
    clear m_sln
end
close(wbar)
sln_datetime = arrayfun(@(x)x{1},sln_datetime);

% 实测井 -> 流线井 的映射（渗透率反演用）
obswid2slnwid = -ones(size(raw_w_o));
for i = 1:numel(obswid2slnwid)
   wn = raw_w_o{i};
   wi = find(wellnames == wn, 1);
   if ~isempty(wi), obswid2slnwid(i) = wi; end
end

% 流线井 <-> 失配井 的映射（饱和度反演用）
slnwid2miswid = -ones(size(wellnames));
miswid2slnwid = -ones(size(mis_wellnames));
for i = 1:numel(slnwid2miswid)
   wn = wellnames(i);
   wi = find(string(mis_wellnames) == wn, 1);
   if ~isempty(wi)
      slnwid2miswid(i) = wi;
   end
end
for i = 1:numel(miswid2slnwid)
   wn = mis_wellnames{i};
   wi = find(wellnames == wn, 1);
   if ~isempty(wi)
      miswid2slnwid(i) = wi;
   end
end

% =========================================================================
% 第五部分：渗透率修正（SPE_0905 论文方法 + v2 组合驱动与临界井加权）
% =========================================================================
disp('开始渗透率修正计算')
gamma_eff = max(gamma_relax * gamma_decay^(iter_index-1), gamma_min);   % 逐轮衰减的松弛因子（含下限）
fprintf('当前轮次 iter_index=%d，gamma_eff=%.4f\n', iter_index, gamma_eff);
dlnK_num = zeros(gridnum,1);   % Eq.(40) 分子：sum( omega * ln(chi) )
dlnK_den = zeros(gridnum,1);   % Eq.(40) 分母：sum( omega )

% 汇总日志表
log_well   = {};
log_tbs    = []; log_tbo = []; log_Ebt = [];
log_Ncand  = []; log_Mstar = [];
log_dfline = []; log_dfobs = []; log_Lam = [];
log_wcerr  = []; log_Ewc = []; log_Etot = [];

wbar = waitbar(0, '渗透率修正中...');
for i = 1:size(data_observed,2)
    ci = obswid2casewid(i);
    wi = obswid2slnwid(i);
    if ci <= 0 || wi <= 0
        waitbar(i/size(data_observed,2),wbar); continue;
    end
    % ---- 井级冻结：含水率误差已达标的井本轮不再修正 ----
    if ~isnan(wc_err(i)) && wc_err(i) < fit_tol
        fprintf('井 %s 已达标（误差 %.2f%% < %.0f%%），本轮冻结\n', ...
            raw_w_o{i}, 100*wc_err(i), 100*fit_tol);
        waitbar(i/size(data_observed,2),wbar); continue;
    end

    bo1 = break_time_observed{i}(1);
    bc1 = break_time_case{ci}(1);
    if isnan(bo1) && isnan(bc1)
        waitbar(i/size(data_observed,2),wbar); continue;   % 两侧均未见水
    end
    if isnan(bc1), bc1 = nTime; end
    if isnan(bo1), bo1 = nTime; end

    st_obs  = start_time_observed(i);
    st_case = start_time_case(ci);
    if isnan(st_obs),  st_obs  = 1; end
    if isnan(st_case), st_case = 1; end

    % ---- Eq.(27) 归一化见水时间失配（时间自各自投产时刻起算） ----
    % tanh 软限幅：E_bt 经压缩后天然有界 (-1,1)，避免小 t_obs 井
    % （实测见水极早的井原始 E_bt 可达 9~15）每轮触发满幅修正。
    t_sim = bc1 - st_case;
    t_obs = bo1 - st_obs;
    E_bt_raw = (t_sim - t_obs) / max(t_obs,1);
    E_bt     = tanh(E_bt_raw);

    % ---- v2 含水率水平失配驱动（带符号，tanh 有界）----
    % E_wc_raw > 0：模拟含水率整体偏高 → 需降低供水流线渗透率；
    % E_wc_raw < 0：模拟含水率整体偏低 → 需提高供水流线渗透率。
    E_wc_raw = wc_err_signed(i);
    if isnan(E_wc_raw), E_wc_raw = 0; end

    % 组合驱动：见水时间与含水率水平两信号加权；相互矛盾时自动抵消。
    % 死区：两信号均在各自死区内（或抵消后很小）时不做修正。
    % [修复②] 原式把两信号各自 tanh 到 (-1,1) 再相减：当两项对 K 的作用方向相反
    % （即输入同号）且都较大时，E_bt 与 tanh(E_wc) 双双饱和到 ±1，相减恒趋近 0
    % ⇒ 失配越极端，越必然被下面的"信号抵消"判据跳过（与设计意图相反）。
    % 修复：先加权求和再统一 tanh，只在两信号量级真正相当时才抵消；符号约定一致。
    if fix_etot_combine
        E_tot = tanh(w_bt * E_bt_raw - (1 - w_bt) * E_wc_raw);
    else
        E_tot = w_bt * E_bt - (1 - w_bt) * tanh(E_wc_raw);
    end
    if abs(E_bt_raw) < e_bt_tol && abs(E_wc_raw) < e_wc_tol
        waitbar(i/size(data_observed,2),wbar); continue;
    end
    if abs(E_tot) < 0.05
        waitbar(i/size(data_observed,2),wbar); continue;   % 信号抵消，本轮不动
    end

    % ---- Eq.(28) 参考时刻 t_cur = min(t_sim_date, t_obs_date) ----
    t_cur_idx = min(bc1, bo1);
    t_misdate = mis_datetime_wc(t_cur_idx);
    ss_i = find(sln_datetime <= t_misdate, 1, 'last');   % 冻结单一快照
    if isempty(ss_i), ss_i = 1; end

    % ---- Eq.(29) 候选流线集：该快照中终止于生产井 wi 的流线 ----
    sln_t   = sln_list{ss_i};
    sln_END = sln_endlist{ss_i};
    linked_sln = sln_t(sln_END == wi);
    N_cand = numel(linked_sln);

    % [修复①] 冻结快照内无候选流线时，在时间窗内扩展快照（前后各 sln_expand_nb 个）。
    % 原实现只查 1 个快照，而早期快照"有流线的井"极少（WLW 1997-04 仅 17 口、
    % 2000-04 已 321 口），大量井因"该快照内没有以它为终点的流线"被静默跳过 ——
    % 并非"不需修正"，而是"没找到可改的对象"。扩展后仍为空才跳过。
    if N_cand == 0 && sln_expand_nb > 0
        ss_win = max(1, ss_i - sln_expand_nb) : min(SLNN, ss_i + sln_expand_nb);
        sln_t   = vertcat(sln_list{ss_win});
        sln_END = vertcat(sln_endlist{ss_win});
        linked_sln = sln_t(sln_END == wi);
        N_cand = numel(linked_sln);
    end
    if N_cand == 0
        waitbar(i/size(data_observed,2),wbar); continue;
    end

    % ---- Eq.(30) 单条流线假想突破含水率增量 & Eq.(29) 总 TOF ----
    T_tot   = zeros(N_cand,1);
    q_m     = zeros(N_cand,1);
    for m = 1:N_cand
        T_tot(m) = max(linked_sln(m).TotalTOF, eps_tau);
        % 流线携液量取井筒端（末节点）总流量 FLORES
        if isfield(linked_sln,'FR') && ~isempty(linked_sln(m).FR)
            q_m(m) = max(linked_sln(m).FR(end), 0);
        else
            q_m(m) = 0;
        end
    end
    if sum(q_m) > 0
        a_m = q_m / sum(q_m);            % Eq.(29) 流量份额 a_{m,p}
    else
        a_m = ones(N_cand,1) / N_cand;   % 流量缺失时退化为均分
    end

    df_line = zeros(N_cand,1);
    for m = 1:N_cand
        SW = linked_sln(m).SW;
        if isfield(linked_sln,'FW') && ~isempty(linked_sln(m).FW) ...
                && sum(linked_sln(m).FR) > 0
            fw = linked_sln(m).FW ./ max(linked_sln(m).FR, eps);  % 沿流线含水率 f_w(s)
        else
            fw = SW;                       % 无流量场时用 SW 代替 f_w
        end
        if numel(SW) < 3
            continue;
        end
        % 水线前缘位置：SW 梯度最大处；上游(靠注水井)为波及侧，下游为未波及侧
        dSW = diff(SW);
        [maxdSW, fidx] = max(dSW);
        if maxdSW < sw_front_min
            continue;                      % 无明显前缘（已突破或未启动），增量取 0
        end
        idx_behind = fidx;                 % 前缘后方（波及侧）-> 假想推进到井筒后的井端状态
        idx_ahead  = fidx + 1;             % 前缘前方（未波及侧）-> 当前井端背景状态
        % Eq.(30)：a_m 经调和指数 kappa_w 折减（kappa=1 为严格流量加权；
        % kappa=0.5 由表 5 标定，保留流量排序同时避免增量被份额过度摊薄）
        df_line(m) = a_m(m)^kappa_w * max(0, fw(idx_behind) - fw(idx_ahead));
    end

    % ---- Eq.(31-33) 归一化贡献与组合贡献 ----
    invT  = 1 ./ (T_tot + eps_tau);
    R_T   = invT / sum(invT);                                   % Eq.(31)
    s_tmp = df_line ./ (T_tot + eps_tau);
    if sum(s_tmp) > 0
        R_S = s_tmp / sum(s_tmp);                               % Eq.(32)
    else
        R_S = zeros(N_cand,1);
    end
    C_m = beta_weight * R_T + (1 - beta_weight) * R_S;          % Eq.(33)

    % ---- Eq.(34) 预测突破后含水率增量（流线法求和） ----
    df_line_p = sum(df_line);

    % ---- Eq.(35) 实际突破后含水率增量 ----
    % two_sample（默认）：与 Eq.(30) 的假想场景（单条流线前缘抵达井筒引起的含水率跳变）
    %   物理对齐，取平滑实测曲线在见水时刻前后各一个采样点的差值，
    %   避免导数阈值阶段定义把后续多流线陆续突破的累计上升也计入。
    % stage：[t_b, t_e]，t_e 为突破后实测含水率导数首次低于 eps_df 的时刻（表 5 标定口径之一）。
    if strcmpi(df_obs_mode, 'stage')
        t0  = bo1;
        seg = min(bo1 + 1, nTime):nTime;
        k_e = find(df_observed_s(seg,i) < eps_df, 1, 'first');
        if isempty(k_e), t1 = nTime; else, t1 = seg(k_e); end
    else
        t0 = max(bo1 - jump_back, 1);
        t1 = min(bo1 + jump_fwd,  nTime);
    end
    df_obs_p = max(ds_observed(t1,i) - ds_observed(t0,i), 0);

    % ---- Eq.(36) 有界因子 Lambda_f ----
    Lam_f = min(1, abs(df_line_p - df_obs_p) / (abs(df_obs_p) + eps_f));

    % ---- Eq.(37) 最小流线子集：按 C 降序累加 df_line 至 >= df_obs ----
    [~, order] = sort(C_m, 'descend');
    cum_df = cumsum(df_line(order));
    M_star = find(cum_df >= df_obs_p, 1, 'first');
    if isempty(M_star), M_star = N_cand; end
    sel = order(1:M_star);

    % ---- Eq.(38-39) 流线乘子 chi = exp(gamma*E_tot*Lambda_f*C_bar) ----
    % v2 临界井加权：误差在 [fit_tol, swing_hi] 的井最接近 20% 达标线，
    % 放大步长 swing_boost 倍，优先把它们推过阈值。
    gamma_w = gamma_eff;
    if ~isnan(wc_err(i)) && wc_err(i) >= fit_tol && wc_err(i) < swing_hi
        gamma_w = gamma_eff * swing_boost;
    end
    C_bar = C_m(sel) / max(C_m(sel));                           % Eq.(38)
    ln_chi = gamma_w * E_tot * Lam_f * C_bar;                   % Eq.(39)，组合驱动 E_tot
    ln_chi = min(max(ln_chi, log(chi_min)), log(chi_max));

    % ---- Eq.(40) 按 TOF 权重投影到网格 ----
    for r = 1:M_star
        m = sel(r);
        sln_k = linked_sln(m);
        cells = sln_k.GLO_CELL;
        tof   = sln_k.TOF;
        if numel(tof) < 2 || sln_k.TotalTOF <= 0
            continue;
        end
        dtof = diff(tof);
        dtof(dtof < 0) = 0;
        % CELL/SW/FLORES 为段数据（每流线 n_node-1 个），与 diff(TOF) 等长对齐
        c_cells = cells;
        valid = c_cells >= 1 & c_cells <= gridnum & isfinite(dtof);
        c_cells = c_cells(valid);
        dtof = dtof(valid);
        if isempty(c_cells)
            continue;
        end
        w_cell = accumarray(c_cells, dtof, [gridnum,1]);
        omega  = w_cell / sln_k.TotalTOF;      % TOF 分数权重 omega_{m,p,k}
        touched = omega > 0;
        dlnK_num(touched) = dlnK_num(touched) + omega(touched) * ln_chi(r);
        dlnK_den(touched) = dlnK_den(touched) + omega(touched);
    end

    % ---- 汇总日志 ----
    log_well{end+1,1} = raw_w_o{i};
    log_tbs(end+1,1)  = t_sim;   log_tbo(end+1,1)  = t_obs;
    log_Ebt(end+1,1)  = E_bt_raw;
    log_Ncand(end+1,1)= N_cand;  log_Mstar(end+1,1)= M_star;
    log_dfline(end+1,1)= df_line_p; log_dfobs(end+1,1)= df_obs_p;
    log_Lam(end+1,1)  = Lam_f;
    log_wcerr(end+1,1)= wc_err(i);
    log_Ewc(end+1,1)  = E_wc_raw;
    log_Etot(end+1,1) = E_tot;

    waitbar(i/size(data_observed,2),wbar)
end
close(wbar)

% ---- Eq.(40-41) 网格修正量与渗透率更新 ----
dlnK = zeros(gridnum,1);
mask = dlnK_den > 0;
dlnK(mask) = dlnK_num(mask) ./ dlnK_den(mask);

nExtra = numel(PERMXnumarray) - gridnum;      % LGR 网格不修正
if nExtra > 0
    dlnK_full = [dlnK; zeros(nExtra,1)];
else
    dlnK_full = dlnK;
end

PERMXarraynew = PERMXnumarray .* exp(dlnK_full);
PERMXarraynew = min(PERMXarraynew, PERM_max);
PERMXarraynew = max(PERMXarraynew, PERM_min);
PERMYarraynew = PERMYnumarray .* exp(dlnK_full);
PERMYarraynew = min(PERMYarraynew, PERM_max);
PERMYarraynew = max(PERMYarraynew, PERM_min);

grdecl_perm.PERMX = PERMXarraynew(:);
grdecl_perm.PERMY = PERMYarraynew(:);
if has_PERMZ
    PERMZarraynew = PERMZnumarray .* exp(dlnK_full);
    PERMZarraynew = min(PERMZarraynew, PERM_max);
    PERMZarraynew = max(PERMZarraynew, PERM_min);
    grdecl_perm.PERMZ = PERMZarraynew(:);
end

% 输出前备份输入文件（若输出路径与输入相同）
if PERM_path == PERM_outpath
    bak = PERM_path + ".bak_" + string(datetime('now','Format','yyyyMMdd_HHmmss'));
    copyfile(PERM_path, bak);
    disp("已备份原渗透率文件到 " + bak);
end
writeGRDECL(grdecl_perm, PERM_outpath);
disp("更新后的渗透率场已写出: " + PERM_outpath);

% ------------------------- 写出渗透率汇总日志 ----------------------------
logpath = fullfile(fileparts(PERM_outpath), 'perm_inversion_summary.txt');
fid = fopen(logpath,'w');
fprintf(fid,'well\tt_sim\tt_obs\tE_bt\tE_bt_soft\tE_wc\tE_tot\tN_cand\tM_star\tdf_line\tdf_obs\tLambda_f\twc_err\n');
for i = 1:numel(log_well)
    fprintf(fid,'%s\t%.1f\t%.1f\t%.4f\t%.4f\t%.4f\t%.4f\t%d\t%d\t%.4f\t%.4f\t%.4f\t%.4f\n', ...
        log_well{i}, log_tbs(i), log_tbo(i), log_Ebt(i), tanh(log_Ebt(i)), log_Ewc(i), log_Etot(i), ...
        log_Ncand(i), log_Mstar(i), log_dfline(i), log_dfobs(i), log_Lam(i), log_wcerr(i));
end
fclose(fid);
disp("渗透率汇总日志已写出: " + logpath);

fprintf('渗透率反演：共处理 %d 口井，修正网格 %d 个（占 %.2f%%）\n', ...
    numel(log_well), nnz(mask), 100*nnz(mask)/gridnum);

% ------------------------- 可选诊断图 ------------------------------------
if make_plots
    for i = 1:min(5,size(data_observed,2))
        ci = obswid2casewid(i);
        if ci <= 0, continue; end
        figure
        scatter(mis_datetime_wc,data_observed(:,i)); hold on
        plot(mis_datetime_wc,data_case(:,ci))
        plot(mis_datetime_wc,df_case(:,ci))
        if ~isnan(break_time_observed{i})
            scatter(mis_datetime_wc(break_time_observed{i}),data_observed(break_time_observed{i},i),'r*')
        end
        if ~isnan(break_time_case{ci})
            scatter(mis_datetime_wc(break_time_case{ci}),data_case(break_time_case{ci},ci),'b*')
        end
        title(raw_w_o{i})
    end
end

% =========================================================================
% 第六部分：含水饱和度修正（v2：热点抑制 + tanh 软截断）
% =========================================================================
disp('开始含水饱和度修正计算')

first_mis_list = zeros(size(mis_wellnames));
for i = 1:size(mis_data,2)
   first_mis_list(i) = mean(mis_data(find(mis_data(:,i),3),i));
end

firstmis_grid = zeros(gridnum,1);
for sln = sln_list'
    sln = sln{1};
    end_cell = arrayfun(@(x)x.END_CELL,sln);
    p_id = arrayfun(@(x)x.END,sln);
    for i = 1:numel(p_id)
        wid = slnwid2miswid(p_id(i));
        if wid>0
            firstmis_grid(end_cell(i)) = -first_mis_list(wid);
        end
    end
end

time_w = 1:(endtime_weight-1)/size(mis_data,1):endtime_weight;   %#ok<NASGU> 保留与原代码一致

SWAT_vary = zeros(gridnum,1);
SWAT_cnt  = zeros(gridnum,1);   % v2 每网格修正计入次数（热点抑制用）
used_seg  = false(gridnum,1);   % [修复A] 分段写入的逐井去重标记（sw_dedup_seg=true 时启用）

wbar = waitbar(0, '饱和度修正中...');
mis_data_new = mis_data;
for i = 1:size(mis_data,2)
    % ---- 井级冻结：平均饱和度失配已很小的井本轮不再修正 ----
    % 仅统计失配非零的时间点，避免未生产时段的零值稀释均值
    mis_i = mis_data(mis_data(:,i) ~= 0, i);
    w_misfit = mean(abs(mis_i),'omitnan');
    if isnan(w_misfit) || w_misfit < mis_tol
        continue;
    end

    mis_w_nnz = max(sum(mis_data_new(:,i) ~= 0),1);
    m = max(sl_years*4/mis_w_nnz,1);

    col_temp_list = [];             % 单点模式去重表（逐井重置，与原代码一致）
    used_seg(:)   = false;          % [修复A] 分段模式去重表（逐井重置）
    jnz = find(mis_data_new(:,i)~=0,1);
    for j = 1:size(mis_data_new,1)
        t_misdate = mis_datetime{j};

        if mis_data_new(j,i)~=0
            minimum_time = (mis_datetime{j} - mis_datetime{jnz})/decay_times;

            s_i = find(t_misdate >= sln_datetime & t_misdate < sln_datetime + years(sl_years));
            if ~isempty(s_i)
                wi = miswid2slnwid(i);
                m = m + 1/3;
                for ss_i=s_i'
                    sln_t = sln_list{ss_i};
                    sln_END = sln_endlist{ss_i};
                    linked_sln = sln_t(sln_END == wi);
                    if numel(linked_sln) > 0
                        elaps = t_misdate - sln_datetime(ss_i);
                        b_temp = arrayfun(@(x)x.BEGIN,linked_sln);
                        [~,~,e_temp] = unique(b_temp);
                        c_temp = accumarray(e_temp,1);
                        c_temp = c_temp(e_temp);

                        for k = 1:numel(linked_sln)
                            sln_k = linked_sln(k);
                            ncell = numel(sln_k.GLO_CELL);
                            backTOF = sln_k.SW_TOF(end) - sln_k.SW_TOF;
                            backTOF = backTOF(2:end);
                            TOF_sec = seconds(backTOF * 1);
                            k_i = find(elaps >= TOF_sec & (TOF_sec+(mis_datetime{end}-mis_datetime{end-1})) >= minimum_time,1);
                            m_time = max(sl_years * 4 / m, 1);
                            dvary  = -mis_data_new(j,i)*alpha*sln_k.PFRACRES/c_temp(k)*m_time;  % 该条流线的总修正量

                            if sw_write_mode == "single" || isempty(k_i)
                                % ---- 原行为：单点写入（k_i 为空 -> 静默跳过，与原代码一致）----
                                col_num = sln_k.GLO_CELL(k_i);
                                if ~isempty(col_num) && ~ismember(col_num,col_temp_list)
                                    if dedup_cells
                                        col_temp_list = [col_temp_list,col_num];
                                    end
                                    SWAT_vary(col_num) = SWAT_vary(col_num) + dvary;
                                    SWAT_cnt(col_num)  = SWAT_cnt(col_num) + 1;
                                end
                            else
                                % ---- [修复A] k_i -> 井端 分段写入，段内按权重分配（总量守恒）----
                                i_front = min(max(k_i,1), ncell);
                                i_end   = ncell;
                                if sw_seg_maxlen > 0 && (i_end - i_front + 1) > sw_seg_maxlen
                                    i_front = i_end - sw_seg_maxlen + 1;   % 超限时向井端收缩
                                end
                                seg_cells = sln_k.GLO_CELL(i_front:i_end);      % 段内网格
                                nseg      = numel(seg_cells);
                                w_seg     = ones(nseg,1)/nseg;                  % uniform
                                if sw_seg_weight == "end_boost"
                                    b_eff = min(sw_end_cells, nseg);
                                    w_seg = (1-sw_end_frac) * ones(nseg,1)/nseg;
                                    w_seg(nseg-b_eff+1:nseg) = w_seg(nseg-b_eff+1:nseg) + sw_end_frac/b_eff;
                                end
                                if sw_dedup_seg
                                    seg_keep  = ~used_seg(seg_cells);
                                    seg_cells = seg_cells(seg_keep);
                                    w_seg     = w_seg(seg_keep);
                                    used_seg(seg_cells) = true;
                                end
                                if numel(unique(seg_cells)) == numel(seg_cells)
                                    % 段内网格互不相同 -> 向量化累加
                                    SWAT_vary(seg_cells) = SWAT_vary(seg_cells) + dvary * w_seg;
                                    SWAT_cnt(seg_cells)  = SWAT_cnt(seg_cells) + 1;
                                else
                                    % 极端情形：同一流线重复经过同一网格 -> 逐格累加
                                    for q = 1:numel(seg_cells)
                                        SWAT_vary(seg_cells(q)) = SWAT_vary(seg_cells(q)) + dvary * w_seg(q);
                                        SWAT_cnt(seg_cells(q))  = SWAT_cnt(seg_cells(q)) + 1;
                                    end
                                end
                            end
                        end
                    end
                end

                clear sln_t sln_END linked_sln

            end
        end
    end
    waitbar(i/size(mis_data,2),wbar)

end
close(wbar)

% ---- 逐轮衰减的总增益：第 1 轮 gain=1，之后每轮按 sw_decay 衰减，
%      避免在最优点附近过冲振荡 ----
gain = sw_decay^(iter_index-1);
max_vary_eff = max_vary * gain;
SWAT_vary = gain * SWAT_vary;

% ---- v2 热点网格抑制：被反复计入修正的网格按 sqrt(次数) 归一化 ----
if normalize_cnt
    cnt_damp = sqrt(max(SWAT_cnt, 1));
    SWAT_vary = SWAT_vary ./ cnt_damp;
    fprintf('热点抑制：计入次数 max=%d，修正量 max|%.4f| -> max|%.4f|\n', ...
        max(SWAT_cnt), max(abs(SWAT_vary .* cnt_damp)), max(abs(SWAT_vary)));
end

% ---- v2 tanh 软截断：小修正近似线性，大修正平滑饱和，避免硬截断块状聚集 ----
if soft_clip
    SWAT_vary = max_vary_eff * tanh(SWAT_vary / max_vary_eff);
else
    SWAT_vary = max(SWAT_vary, -max_vary_eff);
    SWAT_vary = min(SWAT_vary, max_vary_eff);
end
fprintf('当前轮次 iter_index=%d，gain=%.4f，max_vary_eff=%.4f\n', iter_index, gain, max_vary_eff);

% ---- 方向自检：Δf_w = f_w^sim - f_w^obs > 0（模拟含水偏高）应降低 Sw，反之升高 ----
mis_nz = mis_data(mis_data ~= 0);
if ~isempty(mis_nz)
    mis_mean = mean(mis_nz);
    n_up = nnz(SWAT_vary > 0);
    n_dn = nnz(SWAT_vary < 0);
    fprintf('失配统计：均值 %+.4f，|均值| %.4f，正值占 %.1f%%；本轮回写 升高 %d 格 / 降低 %d 格\n', ...
        mis_mean, mean(abs(mis_nz)), 100*mean(mis_nz > 0), n_up, n_dn);
    if mis_mean > 0 && n_up > 10*max(n_dn,1)
        warning(['失配均值为正（模拟含水率偏高）但修正以升高 Sw 为主，方向可能相反：' ...
                 '请检查 wcut 模拟块/实测块是否被对调，或 SLN 方案与模拟块是否同一轮次']);
    elseif mis_mean < 0 && n_dn > 10*max(n_up,1)
        warning(['失配均值为负（模拟含水率偏低）但修正以降低 Sw 为主，方向可能相反：' ...
                 '请检查 wcut 模拟块/实测块是否被对调，或 SLN 方案与模拟块是否同一轮次']);
    end
end

% ---- 饱和度更新与输出 ----
nExtra_sw = numel(SWATnumarray) - gridnum;      % LGR 网格不修正
if nExtra_sw > 0
    SWAT_vary_full = [SWAT_vary; zeros(nExtra_sw,1)];
else
    SWAT_vary_full = SWAT_vary;
end

SWATarraynew = SWATnumarray + SWAT_vary_full;
SWATarraynew = min(SWATarraynew, SW_max);
SWATarraynew = max(SWATarraynew, SW_min);

X_new = SWATarraynew - SWATnumarray;
fprintf('饱和度计算完成, 最大改变量%.4f，最小改变量%.4f，平均改变量%.4f\n', ...
    max(X_new), min(X_new), mean(X_new(ACTNUM==1)))

grdecl_sw.SWAT = SWATarraynew(:);
if write_slnmask_to_poro
    grdecl_sw.PORO = sln_mask(:);   % 仅诊断用，默认不写，避免覆盖孔隙度
end
grdecl_sw.NTG  = NTG(:);

% 输出前备份输入文件（若输出路径与输入相同）
if SW_path == SW_writepath
    bak = SW_path + ".bak_" + string(datetime('now','Format','yyyyMMdd_HHmmss'));
    copyfile(SW_path, bak);
    disp("已备份原饱和度文件到 " + bak);
end
writeGRDECL(grdecl_sw, SW_writepath);
disp("更新后的饱和度场已写出: " + SW_writepath);

fprintf('合并反演完成：PERM -> %s，SWAT -> %s\n', PERM_outpath, SW_writepath);

end

% ============================ 子函数 =====================================
function [glo_i,glo_j,glo_k] = id2ijk(glo_c, xdim, ydim, zdim)   %#ok<DEFNU> 保留与原代码一致
glo_k = ceil(glo_c/(xdim*ydim));
glo_j = ceil((glo_c - (glo_k - 1)*(xdim*ydim))/xdim);
glo_i = glo_c - (glo_k-1)*xdim*ydim - (glo_j-1)*xdim;
end

function [glo_i,glo_j,glo_k,glo_c] = lgrcell2glocell(highn, lgr_binsta, lgr_binend, lgr_glo, lgr_sum, xdim, ydim, zdim)
lgr_p = find(highn<=lgr_binend);
lgr_p = lgr_p(1);
lgr_v = highn - lgr_binsta(lgr_p);
lgrk = ceil(lgr_v / (lgr_sum(lgr_p,1) * lgr_sum(lgr_p,2)));
lgrj = ceil((lgr_v - (lgrk - 1)*lgr_sum(lgr_p,1)* lgr_sum(lgr_p,2))/lgr_sum(lgr_p,1));
lgri = (lgr_v - (lgrk - 1)*lgr_sum(lgr_p,1)* lgr_sum(lgr_p,2)) - (lgrj-1) * lgr_sum(lgr_p,1);
xmulti = lgr_sum(lgr_p,1)/(lgr_glo(lgr_p,2) - lgr_glo(lgr_p,1)+1);
ymulti = lgr_sum(lgr_p,2)/(lgr_glo(lgr_p,4) - lgr_glo(lgr_p,3)+1);
zmulti = lgr_sum(lgr_p,3)/(lgr_glo(lgr_p,6) - lgr_glo(lgr_p,5)+1);
glo_i = lgr_glo(lgr_p,1) + ceil(lgri/xmulti)-1;
glo_j = lgr_glo(lgr_p,3) + ceil(lgrj/ymulti)-1;
glo_k = lgr_glo(lgr_p,5) + ceil(lgrk/zmulti)-1;
glo_c = (glo_k - 1) * xdim * ydim + (glo_j - 1) * xdim + glo_i;
end

function filelist = readtxtfile(path)
fidin = fopen(path);
filelist = {};
while ~feof(fidin)
   tline = fgetl(fidin);
   filelist{end+1} = tline;
end
fclose(fidin);
end
