function main_SL_inversion_WLW()
% =========================================================================
% Streamline-based alternating inversion of initial water saturation and
% permeability -- combined driver, second case
%
%   一次运行同时输出：
%     - 渗透率修正场          -> PERM_outpath
%     - 初始含水饱和度修正场  -> SW_writepath
%
% 本文件与另一案例的驱动 **除"配置块"外逐行一致**，便于与论文方法逐条对应。
% 两个案例的差异全部集中在下面的配置块：
%   1) caseRoot / caseName（工作目录与流线方案名，用于 wcut 分块匹配）；
%   2) wcut 文件布局（优先按 "SUMMARY OF RUN" 自动分块识别；识别不到时用
%      wcut_fixed_cols 指定行号）；
%   3) 超参数（饱和度失配分摊常数 d_time 等按各案例失配量纲标定）。
%
% 使用：第 1 轮 iter_index = 1，之后每轮 +1；输出路径与输入相同时自动备份输入文件。
% =========================================================================

%% ------------------------- 路径设置（EDIT THIS BLOCK）-------------------
caseRoot = "path/to/your/case";   % <<< 改成你的案例工作目录
caseName = "CASE1";               % <<< 本轮算例名（须与 wcut 文件中的模拟块同名）

PERM_path    = fullfile(caseRoot,"PERM_iter.GRDECL");   % 输入：当前渗透率场
PERM_outpath = fullfile(caseRoot,"PERM_iter.GRDECL");   % 输出：更新后渗透率场
SW_path      = fullfile(caseRoot,"SW_iter.GRDECL");     % 输入：当前饱和度场
SW_writepath = fullfile(caseRoot,"SW_iter.GRDECL");     % 输出：更新后饱和度场
SLN_headpath = fullfile(caseRoot,"model.sim",caseName); % 输入：本轮模拟结果（流线）
wcut_readpath= fullfile(caseRoot,"wcut");               % 输入：含水率文件（渗透率反演用）
mis_readpath = fullfile(caseRoot,"swat_mismatch");      % 输入：饱和度失配文件（饱和度反演用）

% 流线方案名（wcut 模拟块自动匹配用）
case_name = caseName;

% wcut 行号兜底：仅当文件内无 "SUMMARY OF RUN" 分块标记时使用
% [模拟井名行 模拟数据起 模拟数据止 实测井名行 实测数据起 实测数据止]
wcut_fixed_cols = [7 12 310 318 323 621];

% 调试开关：把"流线经过次数"写入输出 GRDECL 的 PORO 字段（默认 false，避免污染孔隙度）
write_slnmask_to_poro = false;

%% --------------------------- 共用轮次参数 -------------------------------
iter_index  = 1;      % 当前反演轮次（第 1 轮填 1，之后每轮 +1）

%% --------------------- 渗透率反演参数 ---------------------
gamma_relax = 5;      % Eq.(relax) 松弛因子 gamma
gamma_decay = 0.8;    % 逐轮衰减因子：gamma_eff = max(gamma_relax*gamma_decay^(n-1), gamma_min)
gamma_min   = 0.5;    % 步长下限
fit_tol     = 0.20;   % 井冻结门限：含水率平均相对误差 < fit_tol 的井本轮不修正
e_bt_tol    = 0.10;   % 见水时间失配死区
w_bt        = 0.5;    % 见水时间通道权重（含水率水平通道权重为 1-w_bt）
e_wc_tol    = 0.15;   % 含水率水平失配死区
swing_hi    = 0.40;   % 临界井上界：wc_err ∈ [fit_tol, swing_hi] 的井为临界井
swing_boost = 1.5;    % 临界井步长放大倍数
recent_frac = 0.25;   % 近期窗口长度（有效历史末段比例，w_recent=0 时未启用）
w_recent    = 0;      % 关闭：近期窗口加权（本案例未采用该加固措施）
obs_drop_tol= 1.0;    % 关闭：实测后期骤降冻结（峰值-尾部降幅不可能 >1.0）
osc_damp    = 1;      % 关闭：振荡阻尼（本案例未采用该加固措施）
beta_weight = 0.5;    % Eq.(contrib) 组合贡献权重 beta
kappa_w     = 0.5;    % Eq.(line_incr) 流量份额调和指数 kappa
eps_tau     = 1e-3;   % TOF 正则化常数
eps_f       = 1e-4;   % 含水率增量正则化常数
eps_df      = 0.01;   % 含水率导数阈值（见水识别）
jump_back   = 1;      % 瞬时跳变窗口：见水前采样点数
jump_fwd    = 1;      % 瞬时跳变窗口：见水后采样点数
chi_min     = 0.5;    % 流线乘子下限
chi_max     = 2.0;    % 流线乘子上限
PERM_min    = 0.01;   % 渗透率地质下限 (mD)
PERM_max    = 800;    % 渗透率地质上限 (mD)
sw_front_min= 0.05;   % 判定流线存在明显水线前缘的最小 SW 梯度
make_plots  = false;  % 是否绘制单井诊断图

%% --------------------- 饱和度反演参数 ---------------------
sl_years = 6;         % 流线快照有效窗口（年）
d_time = 1;   % 失配分摊常数（按本案例失配量纲标定；两案例取值不同）
TOF_times = 20000;    % 流线 TOF 无量纲 -> 物理时间换算倍数
SW_min = 0.01;        % 饱和度下限
SW_max = 0.999883;    % 饱和度上限（与数模 deck 一致）
max_vary = 0.2;       % 单轮单网格饱和度最大改变量
decay_times = 3;      % 回溯时间下限除数
sw_decay    = 0.8;    % 逐轮衰减因子：gain = max(sw_decay^(n-1), gain_min)
gain_min    = 0.1;    % 饱和度增益下限
mis_tol     = 0.05;   % 井冻结门限：平均|饱和度失配| < mis_tol 的井本轮不修正
dedup_cells = true;   % 同一流线单元去重（防止同一网格被反复修正）
normalize_cnt = true; % 按 sqrt(计入次数) 归一化热点网格修正量
soft_clip     = true; % tanh 软截断（false 退回 max/min 硬截断）

% =========================================================================
% 第一部分：读取网格（渗透率场 + 饱和度场共用同一套网格与 LGR 信息）
% =========================================================================
disp('读取原始文件中')
filelist = readtxtfile(PERM_path);
disp('读取网格数据中')
grdecl_perm = readGRDECL(PERM_path,'keywords',{'PERMX','PERMY','NTG'});
disp('处理网格数据中')
G = processGRDECL(grdecl_perm);      % 构造 MRST 网格结构体（节点/面/单元拓扑）
G = computeGeometry(G);              % 计算单元体积、质心、面面积等几何量

[xdim,ydim,zdim] = deal(G.cartDims(1),G.cartDims(2),G.cartDims(3));
gridnum = xdim*ydim*zdim;            % 主网格总数

PERMXnumarray = grdecl_perm.PERMX;
PERMYnumarray = grdecl_perm.PERMY;
PERMXnumarray = min(PERMXnumarray, PERM_max);
PERMXnumarray = max(PERMXnumarray, PERM_min);
PERMYnumarray = min(PERMYnumarray, PERM_max);
PERMYnumarray = max(PERMYnumarray, PERM_min);

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
% 有效网格标记：优先用文件中的 ACTNUM，并要求 NTG>0；无 ACTNUM 时退化为 NTG>0
if isfield(grdecl_sw,'ACTNUM')
    ACTNUM = double(grdecl_sw.ACTNUM & NTG > 0);
else
    ACTNUM = double(NTG > 0);
end

% =========================================================================
% 第二部分：读取含水率时间序列（wcut，渗透率反演用）
% =========================================================================
disp('读取含水率时间序列数据矩阵')
mislist_wc = readtxtfile(wcut_readpath);

% ---------------- 定位模拟块与实测块 ----------------
% 优先按文件内 "SUMMARY OF RUN" 分块标记自动识别（多方案导出文件）；
% 文件不含该标记时（单方案 + 实测的简版导出），退回配置中的 wcut_fixed_cols 行号。
sum_lines = find(contains(mislist_wc, 'SUMMARY OF RUN'));
if numel(sum_lines) >= 2
    nblk = numel(sum_lines);
    blk_title  = cell(nblk,1);
    blk_names  = zeros(nblk,1);
    blk_dstart = zeros(nblk,1);
    blk_nsteps = zeros(nblk,1);
    for b = 1:nblk
        h = sum_lines(b);
        blk_title{b}  = strtrim(mislist_wc{h});
        blk_names(b)  = h + 6;
        blk_dstart(b) = h + 11;
        blk_nsteps(b) = str2double(regexp(mislist_wc{h+3}, '\d+', 'match', 'once'));
    end
    % 模拟块必须与流线方案同名：找不到直接报错，避免静默套用旧方案结果
    b_sim = find(contains(blk_title, case_name), 1);
    if isempty(b_sim)
        fprintf('wcut 文件中可用的分块标题：\n');
        for b = 1:nblk, fprintf('  [%d] %s\n', b, blk_title{b}); end
        error('wcut 中未找到与流线方案 "%s" 同名的模拟块，请检查 SLN_headpath 或 wcut 文件', case_name);
    end
    b_obs = find(contains(lower(blk_title), 'observed'), 1);
    if isempty(b_obs)
        warning('wcut 中未找到 Observed 块，回退使用最后 1 块');
        b_obs = nblk;
    end
    w_c_l = blk_names(b_sim);  d_c_s = blk_dstart(b_sim);  d_c_e = blk_dstart(b_sim) + blk_nsteps(b_sim) - 1;
    w_o_l = blk_names(b_obs);  d_o_s = blk_dstart(b_obs);  d_o_e = blk_dstart(b_obs) + blk_nsteps(b_obs) - 1;
    fprintf('wcut 分块（自动识别）：模拟=[%s] 井名行%d 数据%d:%d；实测=[%s] 井名行%d 数据%d:%d\n', ...
        blk_title{b_sim}, w_c_l, d_c_s, d_c_e, blk_title{b_obs}, w_o_l, d_o_s, d_o_e);
else
    w_c_l = wcut_fixed_cols(1);  d_c_s = wcut_fixed_cols(2);  d_c_e = wcut_fixed_cols(3);
    w_o_l = wcut_fixed_cols(4);  d_o_s = wcut_fixed_cols(5);  d_o_e = wcut_fixed_cols(6);
    fprintf('wcut 分块（按配置行号）：模拟井名行%d 数据%d:%d；实测井名行%d 数据%d:%d\n', ...
        w_c_l, d_c_s, d_c_e, w_o_l, d_o_s, d_o_e);
end

raw_w_c = split(strtrim(mislist_wc{w_c_l}))';
raw_w_c = raw_w_c(3:end);
raw_w_o = split(strtrim(mislist_wc{w_o_l}))';
raw_w_o = raw_w_o(3:end);

mis_datetime_wc = {};
data_case = zeros(0,numel(raw_w_c));      % 模拟含水率 f_w^sim
for i = d_c_s:d_c_e
    tempt = split(strtrim(mislist_wc{i}));
    tempt(strcmp(tempt,'undef')) = {'0'};
    mis_datetime_wc{end+1} = parse_run_date(tempt{1});   % 第 1 列日期（中文格式）
    data_case(end+1,:) = str2double(tempt(4:end));       % 第 2/3 列为步数与累计天数，跳过
end
mis_datetime_wc = [mis_datetime_wc{:}];
data_case(data_case==-1) = 0;

data_observed = zeros(0,numel(raw_w_o));  % 实测含水率 f_w^obs
for i = d_o_s:d_o_e
    tempt = split(strtrim(mislist_wc{i}));
    tempt(strcmp(tempt,'undef')) = {'0'};
    data_observed(end+1,:) = str2double(tempt(4:end));
end
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
    d(d==0) = nan;                       % 含水率 0 视为未生产/未见水，不参与平滑
    ds_case(:,i) = smoothdata(d,'movmedian',12);   % 移动中值平滑（12 步 ≈ 1 年），去毛刺
    d = ds_case(:,i);
    nanmask = isnan(d);
    idx = find(~nanmask);
    d_nonan = d(~nanmask);
    df = [0;diff(d_nonan,1)];            % 一阶差分作为含水率上升速率
    df(1:min(24,length(df))) = 0;        % 前 24 步为导数盲区，避免投产初期瞬态误判
    df_case(~nanmask,i) = df;
    df_case_s(:,i) = smoothdata(df_case(:,i),'gaussian',24);
    d_mask = df > eps_df;                % 上升速率超过阈值 -> 判定发生见水（跳变）
    fi_f = idx(d_mask);
    if numel(fi_f) > 0
        f_list = 1;
        for j = 2:numel(fi_f)
            if fi_f(j) - fi_f(j-1) > 12  % 相邻跳变间隔 >12 步才计为新的见水事件
                f_list = [f_list, j];
            end
        end
        break_time_case{i} = fi_f(f_list);   % 首次（及后续）见水时刻；第 1 个元素为主见水点
    else
        break_time_case{i} = nan;            % 全程未见水
    end
    fi_s = find(data_case(:,i)>0,1);     % 含水率首次 >0 的时刻（见水时间起算点）
    if numel(fi_s) > 0, start_time_case(i) = fi_s; else, start_time_case(i) = nan; end
end

for i = 1:size(data_observed,2)
    d = data_observed(:,i);
    d(d==0) = nan;
    d = smoothdata(d,"movmedian",72);    % 实测噪声大，用 72 步（≈6 年）重平滑
    ds_observed(:,i) = d;
    nanmask = isnan(d);
    idx = find(~nanmask);
    d_nonan = d(~nanmask);
    df = [0;diff(d_nonan,1)];
    df(1:min(24,length(df))) = 0;        % 前 24 步导数盲区（同模拟侧）
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
        break_time_observed{i} = nan;        % 实测侧未识别到见水跳变
    end
    df_observed_s(:,i) = smoothdata(df_observed(:,i),'gaussian',24);
    fi_s = find(data_observed(:,i)>0,1);
    if numel(fi_s) > 0, start_time_observed(i) = fi_s; else, start_time_observed(i) = nan; end
end

% 实测井 -> 模拟井 的映射
obswid2casewid = -ones(size(raw_w_o));
for i = 1:numel(obswid2casewid)
   wn = raw_w_o{i};
   wi = find(string(raw_w_c) == wn, 1);
   if ~isempty(wi), obswid2casewid(i) = wi; end
end

% ---- 井级含水率平均相对误差（用于冻结已达标井，与达标指标同口径）----
% err_i = mean_t |f_sim - f_obs| / mean_t f_obs（仅统计实测含水率 > 0 的时刻）
% v3[新增8]：同时计算末段 recent_frac 窗口的带符号误差，水平信号取两者加权
wc_err              = nan(1,size(data_observed,2));
wc_err_signed       = nan(1,size(data_observed,2));
wc_err_recent_signed= nan(1,size(data_observed,2));
for i = 1:size(data_observed,2)
    ci = obswid2casewid(i);
    if ci <= 0, continue; end
    o = data_observed(:,i);
    s = data_case(:,ci);
    v = o > 0;
    if nnz(v) > 0
        wc_err(i)        = mean(abs(s(v) - o(v))) / max(mean(o(v)), eps);
        wc_err_signed(i) = mean(s(v) - o(v)) / max(mean(o(v)), eps);
        % 近期窗口：有效历史末段 recent_frac（至少 4 个点）
        idx_v = find(v);
        n_recent = max(ceil(recent_frac*numel(idx_v)), 4);
        idx_r = idx_v(max(1,end-n_recent+1):end);
        wc_err_recent_signed(i) = mean(s(idx_r) - o(idx_r)) / max(mean(o(idx_r)), eps);
    end
end
% v3：水平驱动信号 = 全局误差与近期误差加权（近期窗口瞄准当前失配）
E_wc_all = (1 - w_recent) * wc_err_signed + w_recent * wc_err_recent_signed;

% ---- v3[修复5]：实测含水率后期骤降井识别（措施/关井，物理上不可拟合）----
% 判据：平滑实测曲线历史峰值 - 末段中位数 > obs_drop_tol，且末段 < 峰值的一半
obs_decline = false(1,size(data_observed,2));
for i = 1:size(data_observed,2)
    d = ds_observed(:,i);
    idx_v = find(~isnan(d) & data_observed(:,i) > 0);
    if numel(idx_v) >= 12
        peak = max(d(idx_v));
        n_tail = min(12, numel(idx_v));
        tailmed = median(d(idx_v(end-n_tail+1:end)));
        if (peak - tailmed) > obs_drop_tol && tailmed < 0.5*peak
            obs_decline(i) = true;
        end
    end
end
fprintf('实测后期骤降井（措施/关井判据）：%d 口，渗透率侧整井冻结\n', nnz(obs_decline));

% =========================================================================
% 第三部分：读取饱和度失配时间序列（swat_mismatch，饱和度反演用）
% =========================================================================
disp('读取饱和度失配数据矩阵')
mislist_sw = readtxtfile(mis_readpath);

mis_wellnames = split(strtrim(mislist_sw{7}))';
mis_wellnames = mis_wellnames(3:end);
mis_nsteps = str2double(regexp(mislist_sw{4}, '\d+', 'match', 'once'));
if isnan(mis_nsteps) || mis_nsteps < 1 || mis_nsteps > numel(mislist_sw) - 12
    mis_nsteps = numel(mislist_sw) - 11;     % 文件头无步数标记时按总行数回退
end
ncol_sw = numel(mis_wellnames);
mis_datetime = {};
mis_data = zeros(0,ncol_sw);
i_sw_end = min(11 + mis_nsteps, numel(mislist_sw));   % 防御：循环不越界
for i = 12 : i_sw_end
    li = mislist_sw{i};
    if ~ischar(li), continue; end                     % readtxtfile 读到 EOF 会多出一个 -1 元素
    li = strtrim(li);
    if isempty(li), continue; end
    tempt = split(li);
    if numel(tempt) < 4, continue; end
    tempt(strcmp(tempt,'undef')) = {'0'};
    vals = str2double(tempt(4:end));
    if numel(vals) ~= ncol_sw
        warning('swat_mismatch 第 %d 行数据列数(%d)与井名行(%d)不符，已跳过', i, numel(vals), ncol_sw);
        continue;
    end
    mis_datetime{end+1} = parse_run_date(tempt{1});
    mis_data(end+1,:) = vals;
end
if isempty(mis_datetime)
    error('swat_mismatch 未解析到有效数据行（井名行第 7 行、数据自第 12 行起），请检查 mis_readpath');
end
mis_data(mis_data==-1) = 0;

% =========================================================================
% 第四部分：读取流线（只读一次，两套反演共用）
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
    m_sln = file2Streamline(sln,'SLN');   % 解析为流线结构体数组（CELL/TOF/SW/FR/FW/BEGIN/END 等字段）
    for i = 1:size(m_sln,1)
       m_sln(i,1).GLO_CELL = m_sln(i,1).CELL;
       for j = 1:size(m_sln(i,1).GLO_CELL,1)
           if m_sln(i,1).GLO_CELL(j,1) > gridnum
               % 编号超出主网格 -> LGR 加密网格，换算回父网格的全局编号
               [~,~,~,glo_c] = lgrcell2glocell(m_sln(i,1).GLO_CELL(j,1), lgr_binsta, lgr_binend, lgr_glo, lgr_sum, xdim, ydim, zdim);
               m_sln(i,1).GLO_CELL(j,1) = glo_c;
           end
       end
       % 饱和度反演附加字段
       m_sln(i,1).END_CELL = m_sln(i,1).GLO_CELL(end);   % 流线末端（生产井端）所在网格
       m_sln(i,1).SW_TOF   = m_sln(i,1).TOF * TOF_times; % TOF 换算为物理时间（近似天）
       endcell_wellid(m_sln(i,1).END_CELL) = m_sln(i,1).END;      % 井端网格 -> 井号
       sln_mask(m_sln(i,1).GLO_CELL) = sln_mask(m_sln(i,1).GLO_CELL) + 1;  % 网格被流线经过次数
    end
    sln_list{k} = m_sln;
    tv = sln.INTEHEAD.values;
    sln_endlist{k} = arrayfun(@(x)x.END,m_sln);         % 各流线末端井号（候选流线快速索引）
    sln_datetime{k} = datetime(tv(7),tv(6),tv(5));      % 快照日期取自 INTEHEAD 的 年/月/日
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

% ---- v3[新增7]：振荡阻尼状态文件（记录各井上一轮修正方向）----
state_path = fullfile(fileparts(PERM_outpath), 'well_update_state.mat');
if exist(state_path, 'file')
    S_state = load(state_path);
    prev_sign = S_state.prev_sign;
    fprintf('已加载上一轮修正方向状态：%d 口井\n', prev_sign.Count);
else
    prev_sign = containers.Map();
end

% =========================================================================
% 第五部分：渗透率修正（论文方法 + v3 双通道驱动）
% =========================================================================
disp('开始渗透率修正计算')
% v3[修复1]：步长衰减放缓 + 下限，保证多轮迭代全程有效
gamma_eff = max(gamma_relax * gamma_decay^(iter_index-1), gamma_min);
fprintf('当前轮次 iter_index=%d，gamma_eff=%.4f\n', iter_index, gamma_eff);
dlnK_num = zeros(gridnum,1);   % Eq.(40) 分子：sum( omega * ln(chi) )
dlnK_den = zeros(gridnum,1);   % Eq.(40) 分母：sum( omega )

% 汇总日志表
log_well   = {};
log_tbs    = []; log_tbo = []; log_Ebt = [];
log_Ncand  = []; log_Mstar = [];
log_dfline = []; log_dfobs = []; log_Lam = [];
log_wcerr  = []; log_Ewc = []; log_drive = [];
log_ss     = []; log_osc = [];

n_frozen_fit  = 0;   % 达标冻结井数
n_frozen_drop = 0;   % 骤降冻结井数
n_osc_damped  = 0;   % 振荡阻尼井数

wbar = waitbar(0, '渗透率修正中...');
for i = 1:size(data_observed,2)
    ci = obswid2casewid(i);
    wi = obswid2slnwid(i);
    if ci <= 0 || wi <= 0
        waitbar(i/size(data_observed,2),wbar); continue;
    end
    % ---- 井级冻结：含水率误差已达标的井本轮不再修正 ----
    if ~isnan(wc_err(i)) && wc_err(i) < fit_tol
        n_frozen_fit = n_frozen_fit + 1;
        waitbar(i/size(data_observed,2),wbar); continue;
    end
    % ---- v3[修复5]：实测后期骤降井整井冻结（措施/关井，不可拟合）----
    if obs_decline(i)
        fprintf('井 %s 实测含水率后期骤降（措施/关井），本轮渗透率侧冻结\n', raw_w_o{i});
        n_frozen_drop = n_frozen_drop + 1;
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

    % ---- Eq.(27) 归一化见水时间失配（时间自各自投产时刻起算，tanh 软限幅）----
    t_sim = bc1 - st_case;
    t_obs = bo1 - st_obs;
    E_bt_raw = (t_sim - t_obs) / max(t_obs,1);
    E_bt     = tanh(E_bt_raw);

    % ---- v3[新增8] 含水率水平失配（全局+近期窗口，带符号）----
    % E_wc_raw > 0：模拟含水率偏高 → 需降低供水流线渗透率；
    % E_wc_raw < 0：模拟含水率偏低 → 需提高供水流线渗透率。
    E_wc_raw = E_wc_all(i);
    if isnan(E_wc_raw), E_wc_raw = 0; end

    % ---- 死区：两信号均在各自死区内时不做修正 ----
    if abs(E_bt_raw) < e_bt_tol && abs(E_wc_raw) < e_wc_tol
        waitbar(i/size(data_observed,2),wbar); continue;
    end

    % ---- Eq.(36) 见水时间通道的有界因子 Lambda_f（增量匹配度）----
    % 注意：Lambda_f 只门控见水时间通道，不再门控水平通道 [修复3]
    t_cur_idx = min(bc1, bo1);
    t_misdate = mis_datetime_wc(t_cur_idx);
    ss_bt = find(sln_datetime <= t_misdate, 1, 'last');   % 见水时刻快照
    if isempty(ss_bt), ss_bt = 1; end

    % ---- v3[修复2/3] 双通道驱动 ----
    % drive_bt：见水时间通道（tanh 有界，Lambda_f 门控，权重 w_bt）
    % drive_wc：含水率水平通道（tanh 有界，独立斜坡门 Lam_wc，权重 1-w_bt）
    Lam_wc  = min(1, abs(E_wc_raw) / (2*e_wc_tol));   % 水平通道斜坡门：死区外线性升至 1
    drive_bt = w_bt * E_bt;                            % Lambda_f 在后面乘
    drive_wc = -(1 - w_bt) * tanh(E_wc_raw) * Lam_wc;
    % 符号冲突（见水偏晚但含水率偏高等）时以水平信号为准——
    % 验收指标 wc_err 是水平量，v2 在此场景下 E_tot≈0 直接漏修
    if drive_bt * drive_wc < 0
        drive_base = drive_wc;
    else
        drive_base = drive_bt + drive_wc;
    end
    if abs(drive_base) < 0.05 && abs(E_wc_raw) < e_wc_tol
        waitbar(i/size(data_observed,2),wbar); continue;   % 两通道均无有效信号
    end

    % ---- v3[修复4] 快照选择：水平驱动占优用最新快照，时间驱动占优用 t_cur 快照 ----
    if abs(drive_wc) >= abs(drive_bt)
        ss_i = SLNN;      % 最新快照：当前流场决定当前含水率水平
    else
        ss_i = ss_bt;     % t_cur 快照：见水时刻流场决定突破行为
    end

    % ---- Eq.(29) 候选流线集：所选快照中终止于生产井 wi 的流线 ----
    sln_t   = sln_list{ss_i};
    sln_END = sln_endlist{ss_i};
    linked_sln = sln_t(sln_END == wi);
    N_cand = numel(linked_sln);
    if N_cand == 0
        waitbar(i/size(data_observed,2),wbar); continue;
    end

    % ---- Eq.(30) 单条流线假想突破含水率增量 & Eq.(29) 总 TOF ----
    T_tot   = zeros(N_cand,1);
    q_m     = zeros(N_cand,1);
    for m = 1:N_cand
        T_tot(m) = max(linked_sln(m).TotalTOF, eps_tau);
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
            fw = linked_sln(m).FW ./ max(linked_sln(m).FR, eps);
        else
            fw = SW;
        end
        if numel(SW) < 3
            continue;
        end
        dSW = diff(SW);
        [maxdSW, fidx] = max(dSW);
        if maxdSW < sw_front_min
            continue;                      % 无明显前缘（已突破或未启动），增量取 0
        end
        idx_behind = fidx;                 % 前缘后方（波及侧）-> 假想推进到井筒后的井端状态
        idx_ahead  = fidx + 1;             % 前缘前方（未波及侧）-> 当前井端背景状态
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

    % ---- Eq.(34-36) Lambda_f（仅门控见水时间通道）----
    df_line_p = sum(df_line);
    t0 = max(bo1 - jump_back, 1);
    t1 = min(bo1 + jump_fwd,  nTime);
    df_obs_p = max(ds_observed(t1,i) - ds_observed(t0,i), 0);
    Lam_f = min(1, abs(df_line_p - df_obs_p) / (abs(df_obs_p) + eps_f));

    % ---- Eq.(37) 最小流线子集：按 C 降序累加 df_line 至 >= df_obs ----
    [~, order] = sort(C_m, 'descend');
    cum_df = cumsum(df_line(order));
    M_star = find(cum_df >= df_obs_p, 1, 'first');
    if isempty(M_star), M_star = N_cand; end
    sel = order(1:M_star);

    % ---- v3 合成驱动：drive = w_bt*E_bt*Lam_f + drive_wc（含冲突裁决）----
    if drive_bt * drive_wc < 0
        drive = drive_wc;                 % 冲突：水平信号单独驱动
    else
        drive = drive_bt * Lam_f + drive_wc;
    end

    % ---- Eq.(38-39) 流线乘子 chi = exp(gamma*drive*C_bar) ----
    gamma_w = gamma_eff;
    if ~isnan(wc_err(i)) && wc_err(i) >= fit_tol && wc_err(i) < swing_hi
        gamma_w = gamma_eff * swing_boost;   % 临界井放大步长，优先推过 20% 达标线
    end
    % ---- v3[新增7] 振荡阻尼：上一轮修正方向与本轮相反的井步长打折 ----
    osc_flag = 0;
    wkey = raw_w_o{i};
    if isKey(prev_sign, wkey)
        ps = prev_sign(wkey);
        if ps ~= 0 && sign(drive) ~= 0 && sign(drive) ~= ps
            gamma_w = gamma_w * osc_damp;
            osc_flag = 1;
            n_osc_damped = n_osc_damped + 1;
        end
    end
    prev_sign(wkey) = sign(drive);

    C_bar = C_m(sel) / max(C_m(sel));                           % Eq.(38)
    ln_chi = gamma_w * drive * C_bar;                           % Eq.(39)，v3 双通道驱动
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
    log_drive(end+1,1)= drive;
    log_ss(end+1,1)   = ss_i;
    log_osc(end+1,1)  = osc_flag;

    waitbar(i/size(data_observed,2),wbar)
end
close(wbar)

% 保存振荡阻尼状态（供下一轮使用）
save(state_path, 'prev_sign');

% ---- Eq.(40-41) 网格修正量与渗透率更新 ----
dlnK = zeros(gridnum,1);
mask = dlnK_den > 0;
dlnK(mask) = dlnK_num(mask) ./ dlnK_den(mask);   % 多井多流线覆盖同一网格时按 TOF 权重加权平均

nExtra = numel(PERMXnumarray) - gridnum;      % LGR 网格不修正
if nExtra > 0
    dlnK_full = [dlnK; zeros(nExtra,1)];
else
    dlnK_full = dlnK;
end

% 乘性更新 K_new = K_old * exp(dlnK)，PERMX/PERMY 同步修正（保持各向异性比不变）
PERMXarraynew = PERMXnumarray .* exp(dlnK_full);
PERMXarraynew = min(PERMXarraynew, PERM_max);
PERMXarraynew = max(PERMXarraynew, PERM_min);
PERMYarraynew = PERMYnumarray .* exp(dlnK_full);
PERMYarraynew = min(PERMYarraynew, PERM_max);
PERMYarraynew = max(PERMYarraynew, PERM_min);

grdecl_perm.PERMX = PERMXarraynew(:);
grdecl_perm.PERMY = PERMYarraynew(:);

% 输出前备份输入文件（若输出路径与输入相同）
if PERM_path == PERM_outpath
    bak = PERM_path + ".bak_" + string(datetime('now','Format','yyyyMMdd_HHmmss'));
    copyfile(PERM_path, bak);
    disp("已备份原渗透率文件到 " + bak);
end
writeGRDECL(grdecl_perm, PERM_outpath);
disp("更新后的渗透率场已写出: " + PERM_outpath);

% ------------------------- 写出渗透率汇总日志（按轮次命名）----------------
logpath = fullfile(fileparts(PERM_outpath), sprintf('perm_inversion_summary_iter%02d.txt', iter_index));
fid = fopen(logpath,'w');
fprintf(fid,'well\tt_sim\tt_obs\tE_bt\tE_bt_soft\tE_wc\tdrive\tN_cand\tM_star\tdf_line\tdf_obs\tLambda_f\twc_err\tsnapshot\tosc_damped\n');
for i = 1:numel(log_well)
    fprintf(fid,'%s\t%.1f\t%.1f\t%.4f\t%.4f\t%.4f\t%.4f\t%d\t%d\t%.4f\t%.4f\t%.4f\t%.4f\t%d\t%d\n', ...
        log_well{i}, log_tbs(i), log_tbo(i), log_Ebt(i), tanh(log_Ebt(i)), log_Ewc(i), log_drive(i), ...
        log_Ncand(i), log_Mstar(i), log_dfline(i), log_dfobs(i), log_Lam(i), log_wcerr(i), ...
        log_ss(i), log_osc(i));
end
fclose(fid);
disp("渗透率汇总日志已写出: " + logpath);

% ---- v3[新增9] 达标统计与失配最重井清单 ----
n_valid = nnz(~isnan(wc_err));
n_fit   = nnz(~isnan(wc_err) & wc_err < fit_tol);
fprintf('渗透率反演：共处理 %d 口井，修正网格 %d 个（占 %.2f%%）\n', ...
    numel(log_well), nnz(mask), 100*nnz(mask)/gridnum);
fprintf('冻结统计：达标冻结 %d 口，骤降冻结 %d 口，振荡阻尼 %d 口\n', ...
    n_frozen_fit, n_frozen_drop, n_osc_damped);
fprintf('含水率达标井（wc_err < %.0f%%）：%d/%d = %.1f%%\n', ...
    100*fit_tol, n_fit, n_valid, 100*n_fit/max(n_valid,1));
[sorted_err, worst_idx] = sort(wc_err(~isnan(wc_err)), 'descend');
worst_names = raw_w_o(~isnan(wc_err));
fprintf('失配最重的 10 口井：\n');
for k = 1:min(10,numel(sorted_err))
    fprintf('  %s\t%.2f%%\n', worst_names{worst_idx(k)}, 100*sorted_err(k));
end

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
% 第六部分：含水饱和度修正（v3：热点抑制 + tanh 软截断 + 增益下限）
% =========================================================================
disp('开始含水饱和度修正计算')

% 各井历史首次失配强度：前 3 个非零失配时刻的均值
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



SWAT_vary = zeros(gridnum,1);
SWAT_cnt  = zeros(gridnum,1);   % 每网格修正计入次数（热点抑制用）

wbar = waitbar(0, '饱和度修正中...');
mis_data_new = mis_data;
for i = 1:size(mis_data,2)
    % ---- 井级冻结：平均饱和度失配已很小的井本轮不再修正 ----
    mis_i = mis_data(mis_data(:,i) ~= 0, i);
    w_misfit = mean(abs(mis_i),'omitnan');
    if isnan(w_misfit) || w_misfit < mis_tol
        continue;
    end

    mis_w_nnz = max(sum(mis_data_new(:,i) ~= 0),1);   % 该井失配非零的时间点数
    m = max(sl_years*4/mis_w_nnz,1);                  % 时间权重基数：失配点越稀疏权重越大

    col_temp_list = [];                               % 本井已修正网格清单（去重用）
    jnz = find(mis_data_new(:,i)~=0,1);               % 首次失配时刻（回溯时间起算点）
    for j = 1:size(mis_data_new,1)
        t_misdate = mis_datetime{j};

        if mis_data_new(j,i)~=0
            minimum_time = (mis_datetime{j} - mis_datetime{jnz})/decay_times;

            % 选取失配时刻之前 sl_years 年内的流线快照
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
                        c_temp = c_temp(e_temp);       % c_temp(k)：与第 k 条流线同注水井的流线条数

                        for k = 1:numel(linked_sln)
                            sln_k = linked_sln(k);
                            backTOF = sln_k.SW_TOF(end) - sln_k.SW_TOF;
                            backTOF = backTOF(2:end);  % 自井端沿流线逆流而上的回溯飞行时间
                            TOF_sec = seconds(backTOF * 1);
                            k_i = find(elaps >= TOF_sec & (TOF_sec+(mis_datetime{end}-mis_datetime{end-1})) >= minimum_time,1);
                            if isempty(k_i)
                                continue;              % v3：未找到归因节点时跳过（v2 会误用空索引）
                            end
                            m_time = max(sl_years * 4 / m, 1);
                            col_num = sln_k.GLO_CELL(k_i);
                            if ~ismember(col_num,col_temp_list)
                                if dedup_cells
                                    col_temp_list = [col_temp_list,col_num];
                                end
                                SWAT_vary(sln_k.GLO_CELL(k_i)) = SWAT_vary(sln_k.GLO_CELL(k_i))-mis_data_new(j,i)/d_time*sln_k.PFRACRES/c_temp(k)*m_time;
                                SWAT_cnt(sln_k.GLO_CELL(k_i)) = SWAT_cnt(sln_k.GLO_CELL(k_i)) + 1;
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

% ---- v3[修复1] 逐轮衰减的总增益：放缓衰减 + 增益下限 ----
gain = max(sw_decay^(iter_index-1), gain_min);
max_vary_eff = max_vary * gain;
SWAT_vary = gain * SWAT_vary;

% ---- 热点网格抑制：被反复计入修正的网格按 sqrt(次数) 归一化 ----
if normalize_cnt
    cnt_damp = sqrt(max(SWAT_cnt, 1));
    SWAT_vary = SWAT_vary ./ cnt_damp;
    fprintf('热点抑制：计入次数 max=%d，修正量 max|%.4f| -> max|%.4f|\n', ...
        max(SWAT_cnt), max(abs(SWAT_vary .* cnt_damp)), max(abs(SWAT_vary)));
end

% ---- tanh 软截断：小修正近似线性，大修正平滑饱和 ----
if soft_clip
    SWAT_vary = max_vary_eff * tanh(SWAT_vary / max_vary_eff);
else
    SWAT_vary = max(SWAT_vary, -max_vary_eff);
    SWAT_vary = min(SWAT_vary, max_vary_eff);
end
fprintf('当前轮次 iter_index=%d，gain=%.4f，max_vary_eff=%.4f\n', iter_index, gain, max_vary_eff);

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
grdecl_sw.NTG  = NTG(:);
if write_slnmask_to_poro
    % 调试用：把"流线经过次数"写入 PORO 字段。
    % 默认关闭——若后续流程会从本文件读取 PORO（孔隙度），该字段会被污染。
    grdecl_sw.PORO = sln_mask(:);
end
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
function [glo_i,glo_j,glo_k,glo_c] = lgrcell2glocell(highn, lgr_binsta, lgr_binend, lgr_glo, lgr_sum, xdim, ydim, zdim)
% LGR 加密网格编号 -> 其所属父网格在主网格中的 (i,j,k) 与全局编号
lgr_p = find(highn<=lgr_binend);
lgr_p = lgr_p(1);                          % 所属 LGR 序号
lgr_v = highn - lgr_binsta(lgr_p);         % 在该 LGR 内的局部编号
lgrk = ceil(lgr_v / (lgr_sum(lgr_p,1) * lgr_sum(lgr_p,2)));
lgrj = ceil((lgr_v - (lgrk - 1)*lgr_sum(lgr_p,1)* lgr_sum(lgr_p,2))/lgr_sum(lgr_p,1));
lgri = (lgr_v - (lgrk - 1)*lgr_sum(lgr_p,1)* lgr_sum(lgr_p,2)) - (lgrj-1) * lgr_sum(lgr_p,1);
xmulti = lgr_sum(lgr_p,1)/(lgr_glo(lgr_p,2) - lgr_glo(lgr_p,1)+1);   % 每父网格 x 向加密倍数
ymulti = lgr_sum(lgr_p,2)/(lgr_glo(lgr_p,4) - lgr_glo(lgr_p,3)+1);
zmulti = lgr_sum(lgr_p,3)/(lgr_glo(lgr_p,6) - lgr_glo(lgr_p,5)+1);
glo_i = lgr_glo(lgr_p,1) + ceil(lgri/xmulti)-1;
glo_j = lgr_glo(lgr_p,3) + ceil(lgrj/ymulti)-1;
glo_k = lgr_glo(lgr_p,5) + ceil(lgrk/zmulti)-1;
glo_c = (glo_k - 1) * xdim * ydim + (glo_j - 1) * xdim + glo_i;
end

function filelist = readtxtfile(path)
% 按行读取文本文件，返回 cell 数组（每行一个元素，保留原始字符串）
fidin = fopen(path);
filelist = {};
while ~feof(fidin)
   tline = fgetl(fidin);
   filelist{end+1} = tline;
end
fclose(fidin);
end

function dt = parse_run_date(s)
% 导出文件日期可能为中文格式（如 01-1月-1995），datetime 默认解析会失败，
% 需显式指定 InputFormat 与中文 Locale；首次调用自动检测，失败则回退默认解析。
persistent zh_ok
if isempty(zh_ok)
    try
        datetime(s, 'InputFormat','dd-MMM-yyyy', 'Locale','zh_CN');
        zh_ok = true;
    catch
        zh_ok = false;
    end
end
if zh_ok
    dt = datetime(s, 'InputFormat','dd-MMM-yyyy', 'Locale','zh_CN');
else
    dt = datetime(s);
end
end
