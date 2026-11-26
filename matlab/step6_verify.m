%% step9_verify_project.m - the verification layer: an audit of steps 1 to 8
% Does not recompute the science. It checks that what the earlier steps SAVED is
% complete, consistent, reproducible and in line with the project report.
%
%   0 environment     toolboxes and MATLAB release
%   1 files           every expected output exists (required / optional)
%   2 grid            all rasters share one grid, S1 data is plausible
%   3 filter+thresholds   Otsu re-derived, thresholds vs Python (Lee filter optional)
%   4 masks           masks inside the domain, cleaned, domain re-derived from the rasters
%   5 confidence      votes / classes / flood map recomputed and compared with the GeoTIFFs
%   6 validation      confusion matrix recomputed from the GeoTIFFs, class ordering
%   7 bootstrap       configuration, intervals bracket the estimates, steps 7 and 8 agree
%   8 consistency     the same quantity is identical wherever it appears
%   9 report claims   every number of the project report: MATCH / DIFFERS / NOT RUN
%
% Status: PASS | FAIL (a real inconsistency) | WARN (differs from the report, or a
%         finding that is not a bug) | SKIP (optional step not run)
%
% Out: matlab/out/verification_report.csv, verification_ledger.csv, verification_manifest.csv
% Writes ONLY to matlab/out. data/processed is Python-owned and read-only here.
if ~exist('P','var'), setup_paths; end
chk('reset');  led('reset');

RUN_LEE_CHECK  = false;   % true: re-derive the Lee filter from the raw RTC image (slow, ~1 GB RAM)
WRITE_MANIFEST = true;    % SHA-256 of every file, for the project manifest

o  = @(n) fullfile(P.out, n);
pr = @(n) fullfile(P.processed, n);
tb = @(n) fullfile(P.tables, n);
f_perm = fullfile(P.processed, 'masks', 'permanent_water.tif');

%% Layer 0 - environment
chk('0 environment', ~verLessThan('matlab','9.9'), sprintf('MATLAB %s (R2020b or newer needed)', version('-release')));
chk('0 environment', license('test','map_toolbox'),   'Mapping Toolbox licensed');
chk('0 environment', license('test','image_toolbox'), 'Image Processing Toolbox licensed');

%% Layer 1 - files
F = { pr('s1_post_vv_db.tif'), 1;  pr('s1_post_vh_db.tif'), 1;  pr('s1_pre_vv_db.tif'), 1; ...
      pr('slope_deg.tif'), 1;      f_perm, 1; ...
      o('thresholds.csv'), 1;      o('masks.mat'), 1;          o('mask_areas.csv'), 1; ...
      o('confidence_class.tif'), 1; o('votes_k.tif'), 1;       o('flood_k2.tif'), 1; ...
      o('confidence_areas.csv'), 1; o('confidence.mat'), 1;    o('s2_water_mndwi.tif'), 1; ...
      o('metrics_by_method.csv'), 1; o('metrics_by_class.csv'), 1; o('metrics_flood_binary.csv'), 1; ...
      o('validation.mat'), 1;      o('bootstrap_ci.csv'), 0;   o('bootstrap_samples.mat'), 0; ...
      o('masks_overview_matlab.png'), 0; o('kappa_matrix.csv'), 0; o('kappa_summary.csv'), 0; ...
      o('kappa_vs_python.csv'), 0; o('alt_member_metrics.csv'), 0; o('alt_ensemble_metrics.csv'), 0; ...
      o('ablation_class_precision.csv'), 0; o('ablation_binary.csv'), 0; o('reliability_by_k.csv'), 0; ...
      o('reference_sensitivity.csv'), 0; o('bootstrap_block_sensitivity.csv'), 0; ...
      o('confidence_map.png'), 0;  o('validation_map.png'), 0; o('validation_summary.png'), 0; ...
      o('bootstrap_ci.png'), 0; ...
      tb('mask_stats.csv'), 0;     tb('candidate_members.csv'), 0; tb('mask_kappa.csv'), 0; tb('ensemble_area.csv'), 0 };

core_ok = true;
for i = 1:size(F,1)
    [~, nm, ext] = fileparts(F{i,1});
    if F{i,2}
        chk('1 files', isfile(F{i,1}), ['required: ' nm ext]);
        core_ok = core_ok && isfile(F{i,1});
    else
        chk('1 files', isfile(F{i,1}), ['optional: ' nm ext], 'optional');
    end
end
if ~core_ok
    fprintf('\nRequired files are missing - run the earlier steps first.\n');
    finish_up(P.out);  return
end

%% Layer 2 - one grid, plausible data
G = { pr('s1_post_vv_db.tif'), pr('s1_post_vh_db.tif'), pr('s1_pre_vv_db.tif'), pr('slope_deg.tif'), f_perm, ...
      o('confidence_class.tif'), o('votes_k.tif'), o('flood_k2.tif'), o('s2_water_mndwi.tif') };
g0 = geotiffinfo(G{1});
for i = 2:numel(G)
    gi = geotiffinfo(G{i});
    same = gi.Height == g0.Height && gi.Width == g0.Width && ...
           max(abs(gi.RefMatrix(:) - g0.RefMatrix(:))) < 1e-6;
    [~, nm, ext] = fileparts(G{i});
    chk('2 grid', same, sprintf('%s%s is on the S1 grid (%d x %d)', nm, ext, g0.Height, g0.Width));
end

[VV, ~] = readgeoraster(G{1}, 'OutputType', 'double');   VV(VV == -9999) = NaN;   % TRAP 1: nodata first
vf   = mean(~isnan(VV(:)));
medv = median(VV(~isnan(VV)));
chk('2 grid', vf > 0.5, sprintf('S1 post VV valid fraction %.1f %%', 100*vf));
chk('2 grid', medv > -25 && medv < 0, sprintf('S1 post VV median %.2f dB is a plausible backscatter', medv), 'warn');

%% Layer 3 - Lee filter (optional), Otsu, thresholds vs Python
if RUN_LEE_CHECK
    f_raw = fullfile(P.raw, 'sentinel1', 's1_rtc_post_vv.tif');
    if isfile(f_raw)
        Lraw = readgeoraster(f_raw, 'OutputType', 'double');  Lraw(Lraw == -32768) = NaN;
        vraw = ~isnan(Lraw);  L0 = Lraw;  L0(~vraw) = 0;
        w = 7;  looks = 4;  kern = ones(w)/w^2;
        cnt = imfilter(double(vraw), kern, 'symmetric');
        mu  = imfilter(L0,    kern, 'symmetric') ./ max(cnt, 1e-6);
        mu2 = imfilter(L0.^2, kern, 'symmetric') ./ max(cnt, 1e-6);
        vr  = max(mu2 - mu.^2, 0);
        Lf  = mu + (vr ./ (vr + mu.^2/looks + 1e-6)) .* (L0 - mu);
        Idb = nan(size(Lf));  good = vraw & (Lf > 0);  Idb(good) = 10*log10(Lf(good));
        d = abs(Idb - VV);  d = d(isfinite(d));
        chk('3 filter+thresholds', max(d) < 1e-3, sprintf('Lee 7x7, 4 looks rebuilt from raw power: max |diff| %.6f dB', max(d)));
        clear Lraw vraw L0 cnt mu mu2 vr Lf Idb good d
    else
        chk('3 filter+thresholds', false, 'raw RTC image for the Lee check not found', 'optional');
    end
end

T  = readtable(o('thresholds.csv'), 'TextType', 'string');
th = @(n) T.threshold(strcmp(T.method, n));
chk('3 filter+thresholds', all(ismember(["otsu_vv","otsu_vh","change_vv","kittler","gmm"], T.method)), ...
    'thresholds.csv holds the five scalar thresholds');
chk('3 filter+thresholds', th('change_vv') == -3.0, 'change-detection threshold is the configured -3 dB');
chk('3 filter+thresholds', th('otsu_vh') < th('otsu_vv'), 'VH threshold is below the VV threshold (VH is darker)');
t_re = otsu_db(VV(~isnan(VV)));
chk('3 filter+thresholds', abs(t_re - th('otsu_vv')) < 1e-6, ...
    sprintf('Otsu VV re-derived from s1_post_vv_db.tif: %.4f dB = thresholds.csv %.4f dB', t_re, th('otsu_vv')));

if isfile(tb('mask_stats.csv')) && isfile(tb('candidate_members.csv'))
    Mp = readtable(tb('mask_stats.csv'), 'TextType', 'string');
    Cp = readtable(tb('candidate_members.csv'), 'TextType', 'string');
    expv = @(tbl, n) tbl.threshold(strcmp(tbl.method, n));
    py = {'otsu_vv', expv(Mp,'otsu_vv'); 'otsu_vh', expv(Mp,'otsu_vh'); ...
          'kittler', expv(Cp,'kittler'); 'gmm', expv(Cp,'gmm')};
    for i = 1:size(py,1)
        chk('3 filter+thresholds', abs(th(py{i,1}) - py{i,2}) < 0.25, ...
            sprintf('%s %.4f dB vs Python %.4f dB (within 0.25 dB)', py{i,1}, th(py{i,1}), py{i,2}));
    end
else
    chk('3 filter+thresholds', false, 'Python threshold tables not found', 'optional');
end
led('T1', 'Otsu VV threshold (dB)',  -12.5534, th('otsu_vv'), 0.25);
led('T2', 'Otsu VH threshold (dB)',  -17.3090, th('otsu_vh'), 0.25);
led('T3', 'Kittler threshold (dB)',  -14.0180, th('kittler'), 0.25);
led('T4', 'GMM threshold (dB)',      -10.2654, th('gmm'),     0.25);

%% Layer 4 - masks
Sm = load(o('masks.mat'), 'masks', 'domain', 'names', 't_mat');
names = Sm.names;  domain = Sm.domain;
chk('4 masks', isequal(size(domain), size(VV)), 'analysis domain is on the S1 grid');

[slope, ~] = readgeoraster(G{4}, 'OutputType', 'double');  slope(slope == -9999) = NaN;
perm  = readgeoraster(f_perm);
dom2  = ~isnan(VV) & ~isnan(slope) & (perm == 0) & (slope <= 10);   % NaN slope -> false, as Python
chk('4 masks', isequal(dom2, domain), 'domain re-derived from slope_deg.tif and permanent_water.tif is identical');
chk('4 masks', abs(nnz(domain)*1e-4 - 727.355) < 0.5, sprintf('domain %.3f km2 (report 727.355 km2)', nnz(domain)*1e-4));
clear slope perm dom2

MIN_PX = 100;
Ar = readtable(o('mask_areas.csv'), 'TextType', 'string');
bad_out = {};  bad_empty = {};  bad_small = {};  bad_area = {};
for i = 1:numel(names)
    m = Sm.masks.(names{i});
    if nnz(m & ~domain) > 0, bad_out{end+1} = names{i}; end            %#ok<SAGROW>
    if nnz(m) == 0,          bad_empty{end+1} = names{i}; end          %#ok<SAGROW>
    szs = cellfun(@numel, bwconncomp(m, 4).PixelIdxList);
    if ~isempty(szs) && min(szs) < MIN_PX, bad_small{end+1} = names{i}; end %#ok<SAGROW>
    if Ar.flood_px(strcmp(Ar.method, names{i})) ~= nnz(m), bad_area{end+1} = names{i}; end %#ok<SAGROW>
end
chk('4 masks', isempty(bad_out),   ['no mask pixel outside the analysis domain' ft(bad_out)]);
chk('4 masks', isempty(bad_empty), ['no mask is empty' ft(bad_empty)]);
chk('4 masks', isempty(bad_small), ['no connected component below 100 px (4-connected)' ft(bad_small)]);
chk('4 masks', isempty(bad_area),  ['pixel counts equal mask_areas.csv' ft(bad_area)]);

bad_t = {};
for n = {'otsu_vv','otsu_vh','change_vv','kittler','gmm'}
    if abs(Sm.t_mat(strcmp(names, n{1})) - th(n{1})) > 1e-9, bad_t{end+1} = n{1}; end %#ok<SAGROW>
end
chk('4 masks', isempty(bad_t), ['masks were built with the thresholds saved in thresholds.csv' ft(bad_t)]);
led('D1', 'analysis domain (km2)', 727.355, nnz(domain)*1e-4, 0.5);

%% Layer 5 - confidence layers, recomputed from the masks
Cm = load(o('confidence.mat'), 'MEMBERS', 'K_FLOOD');
MEMBERS = Cm.MEMBERS;  N = numel(MEMBERS);
k2 = zeros(size(domain), 'uint8');
for m = 1:N, k2 = k2 + uint8(Sm.masks.(MEMBERS{m}) & domain); end
votes = readgeoraster(o('votes_k.tif'));
cls_r = readgeoraster(o('confidence_class.tif'));
fl_r  = readgeoraster(o('flood_k2.tif'));

chk('5 confidence', isequal(sort(MEMBERS), sort({'otsu_vv','otsu_vh','change_vv','gmm'})), ...
    'ensemble = Otsu VV + Otsu VH + VV change + GMM (ADR-23)', 'warn');
chk('5 confidence', isequal(uint8(votes), k2), 'votes_k.tif = sum of the cleaned masks recomputed from masks.mat');
cls2 = conf_class(k2, N, 2);  cls2(~domain) = 0;
chk('5 confidence', isequal(uint8(cls_r), cls2), 'confidence_class.tif = classes recomputed (4/4 High, 3/4 Medium, 2/4 Low, 0-1 Dry)');
chk('5 confidence', isequal(logical(fl_r), (k2 >= Cm.K_FLOOD) & domain), sprintf('flood_k2.tif = (k >= %d) inside the domain', Cm.K_FLOOD));
chk('5 confidence', max(votes(:)) <= N && all(ismember(unique(cls_r(:)), 0:4)), sprintf('k lies in 0..%d, classes in 0..4', N));

Ca = readtable(o('confidence_areas.csv'), 'TextType', 'string');
px = @(c) Ca.pixels(strcmp(Ca.class, c));
chk('5 confidence', px('Low') + px('Medium') + px('High') == nnz(fl_r), 'Low + Medium + High pixels = flood-map pixels');
chk('5 confidence', px('Dry') + px('Low') + px('Medium') + px('High') == nnz(domain), 'Dry + Low + Medium + High pixels = domain pixels');
if isfile(tb('ensemble_area.csv'))
    EA = readtable(tb('ensemble_area.csv'), 'TextType', 'string');
    pyk = EA.k_ge2_km2(strcmp(EA.ensemble, 'gmm_4th'));
    chk('5 confidence', ~isempty(pyk) && abs(nnz(fl_r)*1e-4 - pyk)/pyk < 0.01, ...
        sprintf('flood area %.2f km2 within 1 %% of Python gmm_4th %.2f km2', nnz(fl_r)*1e-4, pyk));
end

%% Layer 6 - validation recomputed from the GeoTIFFs
REF = readgeoraster(o('s2_water_mndwi.tif'));
ev2 = domain & ismember(REF, [0 1]);                      % TRAP 2: cloud (255) is unknown, not dry
w2  = (REF == 1);
pd  = (votes >= Cm.K_FLOOD);
tp = nnz(ev2 & w2 & pd);  fp = nnz(ev2 & ~w2 & pd);  fn = nnz(ev2 & w2 & ~pd);  tn = nnz(ev2 & ~w2 & ~pd);

Bm = readtable(o('metrics_flood_binary.csv'));
chk('6 validation', Bm.tp == tp && Bm.fp == fp && Bm.fn == fn && Bm.tn == tn, ...
    'confusion matrix recomputed from the GeoTIFFs equals metrics_flood_binary.csv');
pc = tp/(tp+fp);  rc = tp/(tp+fn);  f1 = 2*pc*rc/(pc+rc);  io = tp/(tp+fp+fn);  oa = (tp+tn)/(tp+fp+fn+tn);
chk('6 validation', max(abs([Bm.precision Bm.recall Bm.f1 Bm.iou Bm.overall_accuracy] - [pc rc f1 io oa])) < 1e-4, ...
    'precision, recall, F1, IoU and accuracy follow from the confusion matrix');
Vl = load(o('validation.mat'), 'ev', 'MEMBERS', 'K_FLOOD', 'n_eval');
chk('6 validation', isequal(Vl.ev, ev2) && Vl.n_eval == tp+fp+fn+tn, 'validation.mat evaluation set = domain AND clear-sky reference');
frac_ev = nnz(ev2)/nnz(domain);
chk('6 validation', frac_ev > 0.5, sprintf('%.1f %% of the domain is evaluated (clear sky)', 100*frac_ev));

Mc = readtable(o('metrics_by_class.csv'), 'TextType', 'string');
clsn = {'Dry','Low','Medium','High'};
cls_ev = conf_class(votes(ev2), N, 2);  wv = w2(ev2);
pcl = zeros(1,4);  pcsv = zeros(1,4);
for c = 1:4
    pcl(c)  = nnz(cls_ev == c & wv) / max(nnz(cls_ev == c), 1);
    pcsv(c) = Mc.precision_pct(strcmp(Mc.class, clsn{c})) / 100;
end
chk('6 validation', max(abs(pcl - pcsv)) < 1e-4, 'class precisions recomputed from the GeoTIFFs equal metrics_by_class.csv');
chk('6 validation', pcl(4) > pcl(3) && pcl(3) > pcl(2), ...
    sprintf('High %.1f %% > Medium %.1f %% > Low %.1f %% (agreement tracks accuracy)', 100*pcl(4), 100*pcl(3), 100*pcl(2)), 'warn');
clear cls_ev wv REF w2 pd

%% Layer 7 - bootstrap
f_ci = o('bootstrap_ci.csv');
if ~isfile(f_ci) && isfile(tb('bootstrap_ci.csv'))
    f_ci = tb('bootstrap_ci.csv');
end
if isfile(f_ci)
    Ci = readtable(f_ci, 'TextType', 'string');
    ci = @(m, col) Ci.(col)(strcmp(Ci.metric, m));
    chk('7 bootstrap', ~any(Ci.estimate < Ci.ci_low | Ci.estimate > Ci.ci_high), 'every estimate lies inside its 95 % interval');
    chk('7 bootstrap', all(Ci.ci_width(~isnan(Ci.ci_width)) > 0), 'every interval has a positive width');
    chk('7 bootstrap', abs(ci('f1','estimate') - Bm.f1) < 1e-4 && abs(ci('precision','estimate') - Bm.precision) < 1e-4 && ...
        abs(ci('recall','estimate') - Bm.recall) < 1e-4, 'step 8 estimates equal the step 7 binary metrics');
    chk('7 bootstrap', max(abs([ci('prec_low','estimate') ci('prec_medium','estimate') ci('prec_high','estimate')] - pcl(2:4))) < 1e-4, ...
        'step 8 class-precision estimates equal the recomputed ones');
    chk('7 bootstrap', ci('prec_high','ci_low') > ci('prec_medium','ci_high'), ...
        sprintf('High and Medium intervals do not overlap (%.1f %% vs %.1f %%)', 100*ci('prec_high','ci_low'), 100*ci('prec_medium','ci_high')), 'warn');
else
    chk('7 bootstrap', false, 'bootstrap_ci.csv not found', 'optional');
end

if isfile(o('bootstrap_samples.mat'))
    Bs = load(o('bootstrap_samples.mat'), 'boot', 'mnames', 'BLOCK_M', 'NREP', 'SEED');
    chk('7 bootstrap', Bs.BLOCK_M == 500 && Bs.NREP == 1000 && Bs.SEED == 42, 'configuration is 500 m blocks, 1000 repeats, seed 42');
    chk('7 bootstrap', size(Bs.boot, 1) == 1000, 'bootstrap_samples.mat holds 1000 replicates');
    if isfile(f_ci)
        qf = find(strcmp(Bs.mnames, 'f1'));
        chk('7 bootstrap', abs(pctl(Bs.boot(:,qf), 2.5) - ci('f1','ci_low')) < 1e-4 && abs(pctl(Bs.boot(:,qf), 97.5) - ci('f1','ci_high')) < 1e-4, ...
            'F1 interval recomputed from the saved replicates equals bootstrap_ci.csv');
    end
else
    chk('7 bootstrap', true, 'bootstrap_samples.mat optional check skipped (cache not present)', 'optional');
end

%% Layer 8 - the same quantity must be identical wherever it appears
chk('8 consistency', isequal(Vl.MEMBERS, MEMBERS) && Vl.K_FLOOD == Cm.K_FLOOD, 'step 4 and step 7 use the same ensemble and the same k rule');
fl_row = strcmp(Ca.class, sprintf('flood_k_ge_%d', Cm.K_FLOOD));
chk('8 consistency', abs(Ca.km2(fl_row) - Bm.flood_km2) < 1e-3 && abs(nnz(fl_r)*1e-4 - Bm.flood_km2) < 1e-3, ...
    sprintf('flood area %.3f km2 identical in step 4, step 7 and the flood raster', Bm.flood_km2));
chk('8 consistency', Vl.n_eval <= nnz(domain), 'evaluated pixels never exceed the domain');
chk('8 consistency', Bm.tp + Bm.fp + Bm.fn + Bm.tn == Vl.n_eval, 'confusion matrix adds up to the evaluated pixels');

%% Layer 9 - report claims (the ledger)
tol3 = 0.03;
led('F1', 'final binary precision',           0.8266, Bm.precision, tol3);
led('F2', 'final binary recall',              0.8021, Bm.recall,    tol3);
led('F3', 'final binary F1',                  0.8139, Bm.f1,        tol3);
led('F4', 'final binary IoU',                 0.686,  Bm.iou,       0.04);
led('F5', 'true positives',                   769405, Bm.tp,        0.05*769405);
led('F6', 'false positives',                  161621, Bm.fp,        0.10*161621);
led('F7', 'false negatives',                  190390, Bm.fn,        0.10*190390);
led('F8', 'evaluated pixels',                 5550032, tp+fp+fn+tn, 0.02*5550032);
led('C1', 'class precision Low (%)',          45.5, 100*pcl(2), 3);
led('C2', 'class precision Medium (%)',       83.7, 100*pcl(3), 3);
led('C3', 'class precision High (%)',         88.4, 100*pcl(4), 3);
if isfile(f_ci)
    led('B1', 'bootstrap F1 CI lower',            0.801, ci('f1','ci_low'),  tol3);
    led('B2', 'bootstrap F1 CI upper',            0.826, ci('f1','ci_high'), tol3);
    led('B3', 'bootstrap precision CI lower (%)', 81.10, 100*ci('precision','ci_low'),  3);
    led('B4', 'bootstrap precision CI upper (%)', 84.11, 100*ci('precision','ci_high'), 3);
    led('B5', 'bootstrap recall CI lower (%)',    78.54, 100*ci('recall','ci_low'),     3);
    led('B6', 'bootstrap recall CI upper (%)',    81.62, 100*ci('recall','ci_high'),    3);
else
    led('B1', 'bootstrap F1 CI lower', 0.801, NaN, tol3);
end

if isfile(o('kappa_matrix.csv'))
    Kt = readtable(o('kappa_matrix.csv'), 'TextType', 'string');
    rn = string(Kt{:,1});  vn = string(Kt.Properties.VariableNames(2:end));
    kg = @(a, b) Kt{rn == a, 1 + find(vn == b)};
    led('K1', 'kappa Otsu VV vs Otsu VH',                0.849, kg('otsu_vv','otsu_vh'), 0.03);
    led('K2', 'kappa Otsu VV vs change (report 0.76-0.79)', 0.775, kg('otsu_vv','change_vv'), 0.045);
    led('K3', 'kappa Otsu VH vs change (report 0.76-0.79)', 0.775, kg('otsu_vh','change_vv'), 0.045);
    led('K4', 'mean kappa adaptive vs the base three (report 0.06-0.08)', 0.07, ...
        mean([kg('adaptive_vv','otsu_vv') kg('adaptive_vv','otsu_vh') kg('adaptive_vv','change_vv')]), 0.05);
else
    led('K1', 'kappa Otsu VV vs Otsu VH', 0.849, NaN, 0.03);
end

if isfile(o('alt_member_metrics.csv'))
    AM = readtable(o('alt_member_metrics.csv'), 'TextType', 'string');
    am = @(m, col) AM.(col)(strcmp(AM.method, m));
    led('A1', 'Kittler precision', 0.925, am('kittler','precision'), 0.02);
    led('A2', 'Kittler recall',    0.667, am('kittler','recall'),    0.02);
    led('A3', 'GMM precision',     0.788, am('gmm','precision'),     0.02);
    led('A4', 'GMM recall',        0.815, am('gmm','recall'),        0.02);
else
    led('A1', 'Kittler precision', 0.925, NaN, 0.02);
end

if isfile(o('ablation_class_precision.csv'))
    Ab = readtable(o('ablation_class_precision.csv'), 'TextType', 'string');
    ab = @(c, col) Ab.(col)(strcmp(Ab.class, c));
    led('R1', 'with adaptive: High precision (%)',    77.1, ab('High','precision_pct_with_adaptive'),     2);
    led('R2', 'with adaptive: Medium precision (%)',  88.6, ab('Medium','precision_pct_with_adaptive'),   2);
    led('R3', 'without adaptive: High precision (%)', 88.4, ab('High','precision_pct_without_adaptive'),  2);
    led('R4', 'without adaptive: Medium precision (%)', 82.6, ab('Medium','precision_pct_without_adaptive'), 2);
    led('R5', 'without adaptive: Low precision (%)',  43.2, ab('Low','precision_pct_without_adaptive'),   3);
else
    led('R1', 'with adaptive: High precision (%)', 77.1, NaN, 2);
end

Lt = led('table');
n_diff = nnz(strcmp(Lt(:,6), 'DIFFERS'));  n_match = nnz(strcmp(Lt(:,6), 'MATCH'));  n_nr = nnz(strcmp(Lt(:,6), 'NOT RUN'));
chk('9 report claims', n_diff == 0, sprintf('%d of %d report numbers reproduced (%d differ, %d not run)', ...
    n_match, size(Lt,1), n_diff, n_nr), 'warn');

%% Manifest - SHA-256 of every file that exists
if WRITE_MANIFEST
    mf = cell(0, 4);
    for i = 1:size(F,1)
        if isfile(F{i,1})
            d = dir(F{i,1});
            try, h = sha256_file(F{i,1}); catch, h = 'unavailable'; end %#ok<NOCOM>
            mf(end+1,:) = {F{i,1}, d.bytes, h, datestr(d.datenum, 'yyyy-mm-dd HH:MM:SS')}; %#ok<SAGROW>
        end
    end
    writetable(table(string(mf(:,1)), cell2mat(mf(:,2)), string(mf(:,3)), string(mf(:,4)), ...
        'VariableNames', {'file','bytes','sha256','modified'}), o('verification_manifest.csv'));
    fprintf('\nmanifest: %d files hashed -> verification_manifest.csv\n', size(mf,1));
end

finish_up(P.out);

%% ============================ local functions ============================

function out = chk(layer, ok, msg, kind)
% chk('reset') | chk('table') | chk(layer, ok, msg [, 'warn' | 'optional'])
persistent L
if isempty(L), L = cell(0,3); end
out = [];
if nargin == 1
    if strcmp(layer, 'reset'), L = cell(0,3); else, out = L; end
    return
end
if nargin < 4, kind = 'fail'; end
if isempty(ok), ok = false; end
ok = all(ok(:));
if ok,                       st = 'PASS';
elseif strcmp(kind,'warn'),  st = 'WARN';
elseif strcmp(kind,'optional'), st = 'SKIP';
else,                        st = 'FAIL'; end
L(end+1,:) = {layer, st, msg};
fprintf('%-4s [%s] %s\n', st, layer, msg);
end

function out = led(id, claim, rep, meas, tol)
% led('reset') | led('table') | led(id, claim, report_value, measured, tolerance)
persistent T
if isempty(T), T = cell(0,6); end
out = [];
if nargin == 1
    if strcmp(id, 'reset'), T = cell(0,6); else, out = T; end
    return
end
if isempty(meas) || isnan(meas),  st = 'NOT RUN';
elseif abs(meas - rep) <= tol,    st = 'MATCH';
else,                             st = 'DIFFERS'; end
if isempty(meas), meas = NaN; end
T(end+1,:) = {id, claim, rep, meas, tol, st};
end

function finish_up(outdir)
L = chk('table');
if isempty(L), return; end
writetable(table(string(L(:,1)), string(L(:,2)), string(L(:,3)), ...
    'VariableNames', {'layer','status','check'}), fullfile(outdir, 'verification_report.csv'));
Lt = led('table');
if ~isempty(Lt)
    writetable(table(string(Lt(:,1)), string(Lt(:,2)), cell2mat(Lt(:,3)), cell2mat(Lt(:,4)), ...
        cell2mat(Lt(:,5)), string(Lt(:,6)), 'VariableNames', ...
        {'id','claim','report_value','measured','tolerance','status'}), fullfile(outdir, 'verification_ledger.csv'));
end

st = string(L(:,2));  ly = string(L(:,1));
fprintf('\n=========== verification summary ===========\n');
fprintf('%-22s %6s %6s %6s %6s\n', 'layer', 'PASS', 'WARN', 'SKIP', 'FAIL');
for u = unique(ly)'
    fprintf('%-22s %6d %6d %6d %6d\n', u, nnz(ly==u & st=="PASS"), nnz(ly==u & st=="WARN"), ...
            nnz(ly==u & st=="SKIP"), nnz(ly==u & st=="FAIL"));
end

for i = find(st == "FAIL")', fprintf('FAIL  [%s] %s\n', L{i,1}, L{i,3}); end
for i = find(st == "WARN")', fprintf('WARN  [%s] %s\n', L{i,1}, L{i,3}); end
if ~isempty(Lt)
    for i = find(strcmp(Lt(:,6), 'DIFFERS'))'
        fprintf('DIFFERS  %s: report %g, measured %g (tolerance %g)\n', Lt{i,2}, Lt{i,3}, Lt{i,4}, Lt{i,5});
    end
end

nf = nnz(st == "FAIL");  nw = nnz(st == "WARN");
if nf == 0 && nw == 0
    verdict = 'VERIFIED: every check passed';
elseif nf == 0
    verdict = sprintf('VERIFIED WITH WARNINGS: %d warning(s), no failure', nw);
else
    verdict = sprintf('NOT VERIFIED: %d check(s) failed', nf);
end
fprintf('\n%s\n', verdict);
fprintf('Wrote verification_report.csv and verification_ledger.csv in %s\n', outdir);
end

function s = ft(c)
% " (name, name)" for a failure list, nothing when it is empty
if isempty(c), s = ''; else, s = [' (' strjoin(c, ', ') ')']; end
end

function h = sha256_file(f)
fid = fopen(f, 'r');  data = fread(fid, Inf, '*uint8');  fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(typecast(data, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest, 'uint8'))', 1, []));
end

function t = otsu_db(v)
% Otsu threshold in dB. graythresh needs [0,1], so rescale in and back out.
v = v(isfinite(v));  lo = min(v);  hi = max(v);
if hi <= lo, t = lo; return; end
t = lo + graythresh((v - lo)/(hi - lo))*(hi - lo);
end

function q = pctl(x, p)
% Percentile with linear interpolation (no toolbox needed); NaNs are ignored.
x = sort(x(~isnan(x)));  n = numel(x);
if n == 0, q = NaN; return; end
pos = (n - 1)*p/100 + 1;  a = floor(pos);  b = ceil(pos);
q = x(a) + (pos - a)*(x(b) - x(a));
end

function cls = conf_class(k, N, low_min)
% Vote count -> class. 1 Dry | 2 Low | 3 Medium | 4 High  (same rule as steps 4, 6a, 7, 8)
cls = ones(size(k), 'uint8');
cls(k >= low_min)            = 2;
cls(k == N-1 & k >= low_min) = 3;
cls(k == N   & k >= low_min) = 4;
end