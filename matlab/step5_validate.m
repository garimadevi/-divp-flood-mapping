%% step7_validation_mndwi.m - validate the flood masks against Sentinel-2 MNDWI
% Reference : Sentinel-2 (25 Jun 2023) MNDWI = (Green - SWIR1) / (Green + SWIR1),
%             cloud-masked with the scene classification layer (SCL)
% Questions : (1) how good is each single method?          precision / recall / F1 / IoU
%             (2) how good is the final binary flood map?   confusion matrix
%             (3) does confidence mean accuracy?            precision of Low / Medium / High
%             (4) does the answer depend on the MNDWI threshold?
%
% Contract:
%   in  : matlab/out/masks.mat (step3_masks.m), raw Sentinel-2 Green, SWIR1 and SCL
%   out : matlab/out/s2_water_mndwi.tif, metrics_by_method.csv, metrics_by_class.csv,
%         metrics_flood_binary.csv, reliability_by_k.csv, reference_sensitivity.csv,
%         validation.mat, validation_map.png, validation_summary.png
%
% Writes ONLY to matlab/out. data/processed is Python-owned and read-only here.
if ~exist('P','var'), setup_paths; end

%% Section A - settings and inputs
f_green = fullfile(P.raw,'sentinel2','s2_post_b03_green.tif');    % <- edit the three names
if ~isfile(f_green), f_green = fullfile(P.raw,'sentinel2','s2_post_B03.tif'); end
if ~isfile(f_green), f_green = fullfile(P.raw,'sentinel2','s2_post_b03.tif'); end

f_swir  = fullfile(P.raw,'sentinel2','s2_post_b11_swir1.tif');
if ~isfile(f_swir), f_swir = fullfile(P.raw,'sentinel2','s2_post_B11.tif'); end
if ~isfile(f_swir), f_swir = fullfile(P.raw,'sentinel2','s2_post_b11.tif'); end

f_scl   = fullfile(P.raw,'sentinel2','s2_post_scl.tif');
if ~isfile(f_scl), f_scl = fullfile(P.raw,'sentinel2','s2_post_SCL.tif'); end
if ~isfile(f_scl), f_scl = fullfile(P.raw,'sentinel2','s2_post_scl.tif'); end

f_grid  = fullfile(P.processed,'s1_post_vv_db.tif');

MNDWI_THR    = 0.0;          % water if MNDWI > 0
S2_OFFSET_DN = -1000;        % L2A baseline >= 04.00: refl = (DN - 1000)/10000. Use 0 if already reflectance
S2_SCALE     = 1e-4;
CLEAR_SCL    = [2 4 5 6 7];      % vegetation, bare soil, water (no cloud, shadow, cirrus, snow)

MEMBERS = {'otsu_vv','otsu_vh','change_vv','gmm'};   % the final four-method ensemble
K_FLOOD = 2;                                         % binary flood map: k >= 2
PIX_KM2 = 1e-4;

need = {fullfile(P.out,'masks.mat'), f_green, f_swir, f_scl, f_grid};
for q = 1:numel(need)
    if ~isfile(need{q}), error('Missing input file: %s', need{q}); end
end

S      = load(need{1}, 'masks', 'domain', 'names');
masks  = S.masks;
domain = S.domain;                    % no permanent water, slope <= 10 deg
names  = S.names;
[nr, nc] = size(domain);

[~, R] = readgeoraster(f_grid);       % the S1 grid
tags   = geotiffinfo(f_grid).GeoTIFFTags.GeoKeyDirectoryTag;
missing = setdiff(MEMBERS, names);
if ~isempty(missing), error('Mask(s) not in masks.mat: %s', strjoin(missing, ', ')); end

%% Section B - lat/lon of every S1 pixel (used to sample the Sentinel-2 rasters)
[col, row] = meshgrid(1:nc, 1:nr);
if isa(R,'map.rasterref.GeographicCellsReference')
    [lat, lon] = intrinsicToGeographic(R, col, row);
else                                             % projected grid (UTM)
    [xw, yw] = intrinsicToWorld(R, col, row);
    [lat, lon] = projinv(R.ProjectedCRS, xw, yw);
end
clear col row xw yw

%% Section C - the MNDWI reference on the S1 grid
G  = s2_on_grid(f_green, S2_OFFSET_DN, S2_SCALE, lat, lon);   % 10 m band
SW = s2_on_grid(f_swir,  S2_OFFSET_DN, S2_SCALE, lat, lon);   % 20 m band, resampled to 10 m
[scl, Rs] = readgeoraster(f_scl, 'OutputType', 'double');
scl = sample_on_grid(scl, Rs, lat, lon, 'nearest');           % TRAP 1: classes -> nearest
clear lat lon

den   = G + SW;
mndwi = (G - SW) ./ den;
mndwi(~(den > 0)) = NaN;
clear G SW den

ref_valid = ismember(scl, CLEAR_SCL) & isfinite(mndwi);       % clear-sky pixels only
water     = false(nr, nc);
water(ref_valid) = mndwi(ref_valid) > MNDWI_THR;
clear scl

REFu8 = repmat(uint8(255), nr, nc);                           % 255 = cloud / no data
REFu8(ref_valid) = uint8(water(ref_valid));                   % 1 water, 0 land
geotiffwrite(fullfile(P.out,'s2_water_mndwi.tif'), REFu8, R, 'GeoKeyDirectoryTag', tags);
clear REFu8

%% Section D - the evaluation set
% TRAP 2: judge every method on the SAME pixels - analysis domain AND clear sky.
% Cloud in the reference is "unknown", not "dry"; counting it as dry would punish good masks.
ev     = domain & ref_valid;
n_eval = nnz(ev);
refv   = water(ev);
mndwi_ev = mndwi(ev);
clear mndwi

cf = 100*nnz(domain & ref_valid)/nnz(domain);
fprintf('clear sky      : %.1f %% of the analysis domain   (report 77.1 %%)\n', cf);
fprintf('evaluated      : %d px (%.3f km2)   (report 5,550,032 px)\n', n_eval, n_eval*PIX_KM2);
fprintf('reference water: %d px = %.1f %% of the evaluated pixels\n', nnz(refv), 100*nnz(refv)/n_eval);

%% Section E - every single method against the reference
nM = numel(names);
MM = cell(1, nM);
for i = 1:nM
    MM{i} = binmetrics(masks.(names{i})(ev), refv);
end

fprintf('\n%-12s %9s %9s %9s %9s %9s\n', 'method', 'precision', 'recall', 'F1', 'IoU', 'accuracy');
for i = 1:nM
    fprintf('%-12s %9.3f %9.3f %9.3f %9.3f %9.3f\n', names{i}, MM{i}.prec, MM{i}.rec, ...
            MM{i}.f1, MM{i}.iou, MM{i}.oa);
end

Tm = table(names(:), cellfun(@(s) s.tp, MM(:)), cellfun(@(s) s.fp, MM(:)), ...
           cellfun(@(s) s.fn, MM(:)), cellfun(@(s) s.tn, MM(:)), ...
           cellfun(@(s) s.prec, MM(:)), cellfun(@(s) s.rec, MM(:)), ...
           cellfun(@(s) s.f1, MM(:)), cellfun(@(s) s.iou, MM(:)), cellfun(@(s) s.oa, MM(:)), ...
    'VariableNames', {'method','tp','fp','fn','tn','precision','recall','f1','iou','overall_accuracy'});
writetable(Tm, fullfile(P.out,'metrics_by_method.csv'));

%% Section F - the final ensemble: vote count k, binary flood map, confusion matrix
N  = numel(MEMBERS);
kd = zeros(nr, nc, 'uint8');                         % votes on the whole domain (for the map)
for m = 1:N, kd = kd + uint8(masks.(MEMBERS{m}) & domain); end
k = kd(ev);                                          % votes on the evaluated pixels

BE = binmetrics(k >= K_FLOOD, refv);
flood_km2 = nnz((kd >= K_FLOOD) & domain) * PIX_KM2;

fprintf('\nfinal ensemble (%s), flood = k >= %d\n', strjoin(MEMBERS, ' + '), K_FLOOD);
fprintf('  precision %.4f | recall %.4f | F1 %.4f | IoU %.4f | accuracy %.4f | flood %.2f km2\n', ...
        BE.prec, BE.rec, BE.f1, BE.iou, BE.oa, flood_km2);
fprintf('  TP %d | FP %d | FN %d | TN %d\n', BE.tp, BE.fp, BE.fn, BE.tn);
fprintf('  (report: TP 769,405 | FP 161,621 | FN 190,390 | TN 4,428,616)\n');

Tb = table({strjoin(MEMBERS,'+')}, BE.tp, BE.fp, BE.fn, BE.tn, BE.prec, BE.rec, BE.f1, BE.iou, BE.oa, flood_km2, ...
    'VariableNames', {'ensemble','tp','fp','fn','tn','precision','recall','f1','iou','overall_accuracy','flood_km2'});
writetable(Tb, fullfile(P.out,'metrics_flood_binary.csv'));

%% Section G - does confidence mean accuracy? precision of each confidence class
cls = conf_class(k, N, 2);                           % 1 Dry | 2 Low | 3 Medium | 4 High
cn  = {'Dry','Low','Medium','High'};
n_c = zeros(1,4);  w_c = zeros(1,4);  p_c = zeros(1,4);  s_c = zeros(1,4);
for c = 1:4
    in = (cls == c);
    n_c(c) = nnz(in);
    w_c(c) = nnz(in & refv);
    p_c(c) = w_c(c) / max(n_c(c), 1);                % observed precision of the class
    s_c(c) = w_c(c) / max(nnz(refv), 1);             % share of all reference water in the class
end
mono = p_c(4) > p_c(3) && p_c(3) > p_c(2);

fprintf('\nobserved precision per confidence class (share of class pixels that are reference water)\n');
fprintf('%-8s %10s %10s %11s %16s\n', 'class', 'pixels', 'water px', 'precision', '% of ref water');
for c = 1:4
    fprintf('%-8s %10d %10d %10.1f%% %15.1f%%\n', cn{c}, n_c(c), w_c(c), 100*p_c(c), 100*s_c(c));
end
if mono, fprintf('ordering: High > Medium > Low  (confidence tracks accuracy)\n');
else,    fprintf('ordering: NOT monotonic - agreement does not track accuracy here\n'); end

Tc = table(cn(:), n_c(:), w_c(:), 100*p_c(:), 100*s_c(:), ...
    'VariableNames', {'class','pixels','reference_water_px','precision_pct','share_of_reference_water_pct'});
writetable(Tc, fullfile(P.out,'metrics_by_class.csv'));

% the same question, one level finer: precision for each vote count k = 0..N
nk = zeros(1, N+1);  pk = zeros(1, N+1);
for kk = 0:N
    in = (k == kk);
    nk(kk+1) = nnz(in);
    pk(kk+1) = nnz(in & refv) / max(nnz(in), 1);
end
writetable(table((0:N)', nk(:), 100*pk(:), 'VariableNames', {'k','pixels','precision_pct'}), ...
           fullfile(P.out,'reliability_by_k.csv'));
fprintf('precision by k: '); fprintf('k=%d %.1f%% | ', [0:N; 100*pk]); fprintf('\n');

%% Section H - does the answer depend on the MNDWI threshold? (the reference is not ground truth)
thr_list = [-0.10 0.00 0.10 0.20];
pred = (k >= K_FLOOD);
sens = zeros(numel(thr_list), 5);                    % water %, precision, recall, F1, High-Medium gap
fprintf('\nreference sensitivity (final binary flood map)\n');
fprintf('%9s %10s %10s %9s %9s %12s\n', 'MNDWI >', 'water %', 'precision', 'recall', 'F1', 'High-Medium');
for q = 1:numel(thr_list)
    rt = mndwi_ev > thr_list(q);
    bm = binmetrics(pred, rt);
    pH = nnz(cls == 4 & rt) / max(nnz(cls == 4), 1);
    pM = nnz(cls == 3 & rt) / max(nnz(cls == 3), 1);
    sens(q,:) = [100*mean(rt), bm.prec, bm.rec, bm.f1, 100*(pH - pM)];
    fprintf('%9.2f %10.1f %10.3f %9.3f %9.3f %+10.1f pt\n', thr_list(q), sens(q,:));
end
writetable(array2table([thr_list(:), sens], 'VariableNames', ...
    {'mndwi_threshold','water_pct','precision','recall','f1','high_minus_medium_pt'}), ...
    fullfile(P.out,'reference_sensitivity.csv'));

%% Section I - save for the bootstrap step
save(fullfile(P.out,'validation.mat'), 'ev', 'water', 'kd', 'MEMBERS', 'K_FLOOD', 'n_eval', '-v7.3');

%% Section J - figure 1: where is the flood map right and wrong?
vm = zeros(nr, nc, 'uint8');                         % 0 not evaluated
pf = (kd >= K_FLOOD);
vm(ev &  water &  pf) = 1;                           % TP
vm(ev & ~water &  pf) = 2;                           % FP
vm(ev &  water & ~pf) = 3;                           % FN
vm(ev & ~water & ~pf) = 4;                           % TN
clear pf

[rw, cl] = find(domain);
r0 = max(1, min(rw)-1);  r1 = min(nr, max(rw)+1);
c0 = max(1, min(cl)-1);  c1 = min(nc, max(cl)+1);
ds = max(1, floor(max(r1-r0, c1-c0)/1100));
ri = r0:ds:r1;  ci = c0:ds:c1;

vcmap = [0.35 0.35 0.35;   % not evaluated (cloud, permanent water, steep terrain)
         0.10 0.35 0.85;   % true positive
         0.85 0.20 0.15;   % false positive
         0.95 0.65 0.10;   % false negative
         0.93 0.93 0.93];  % true negative
asp = numel(ci) / max(numel(ri), 1);
figure('Color','w','Position',[80 80 1000 round(1000/asp) + 80]);
imagesc(vm(ri,ci)); axis image off; colormap(vcmap); clim([-0.5 4.5]);
cb = colorbar; cb.Ticks = 0:4;
cb.TickLabels = {'not evaluated','true positive','false positive','false negative','true negative'};
title(sprintf('Final flood map vs Sentinel-2 MNDWI  (F1 %.3f, precision %.3f, recall %.3f)', ...
              BE.f1, BE.prec, BE.rec));
saveas(gcf, fullfile(P.out,'validation_map.png'));
clear vm

%% Section K - figure 2: confusion matrix, class precision, reliability
cc = [0.70 0.70 0.70; 0.65 0.80 0.95; 0.30 0.58 0.88; 0.05 0.20 0.55];   % Dry, Low, Medium, High
figure('Color','w','Position',[60 60 1250 400]);

subplot(1,3,1);
CM  = [BE.tn BE.fp; BE.fn BE.tp];                   % rows: reference, columns: predicted
CMn = CM ./ sum(CM, 2);
imagesc(CMn); axis image; clim([0 1]); colormap(gca, parula);
set(gca,'XTick',1:2,'XTickLabel',{'dry','flood'},'YTick',1:2,'YTickLabel',{'not water','water'});
xlabel('predicted'); ylabel('Sentinel-2 reference');
for a = 1:2
    for b = 1:2
        text(b, a, sprintf('%d\n(%.1f %%)', CM(a,b), 100*CMn(a,b)), 'HorizontalAlignment','center', ...
             'Color','w', 'FontWeight','bold');
    end
end
title('Confusion matrix (row-normalised)');

subplot(1,3,2);
bb = bar(100*p_c, 'FaceColor', 'flat');
bb.CData = cc;
set(gca, 'XTickLabel', cn); ylabel('observed precision (%)'); ylim([0 105]); grid on
for c = 1:4
    text(c, 100*p_c(c), sprintf('%.1f', 100*p_c(c)), 'HorizontalAlignment','center', ...
         'VerticalAlignment','bottom');
end
if mono, tg = 'High > Medium > Low'; else, tg = 'NOT monotonic'; end
title(sprintf('Precision by confidence class (%s)', tg));

subplot(1,3,3);
plot(0:N, 100*pk, 'o-', 'LineWidth', 1.5, 'MarkerFaceColor', [.05 .20 .55]);
xlabel('k = number of methods flagging flood'); ylabel('precision (%)'); grid on
set(gca, 'XTick', 0:N); ylim([0 105]);
title('Reliability curve');
saveas(gcf, fullfile(P.out,'validation_summary.png'));

%% Section L - self-check (numbers from the report)
near = @(a, b, tol) abs(a - b) <= tol;
fprintf('\n--- step7 verification ---\n');
report(BE.tp + BE.fp + BE.fn + BE.tn == n_eval, 'confusion matrix adds up to the evaluated pixels');
report(isequal(size(water), size(domain)) && ~any(water(~ref_valid)), ...
       'reference is on the S1 grid and has no water in cloudy pixels');
report(near(cf, 77.1, 8), sprintf('clear-sky fraction %.1f %% within 8 points of the report (77.1 %%)', cf));
report(abs(n_eval - 5550032)/5550032 < 0.02, ...
       sprintf('evaluated pixels %d within 2 %% of the report (5,550,032)', n_eval));
report(abs(nnz(refv) - 959795)/959795 < 0.15, ...
       sprintf('reference water %d px within 15 %% of the report (959,795)', nnz(refv)));
report(near(BE.prec, 0.826, 0.03) && near(BE.rec, 0.802, 0.03) && near(BE.f1, 0.8138, 0.03), ...
       sprintf('binary map precision %.3f / recall %.3f / F1 %.4f (report 0.826 / 0.802 / 0.8138)', ...
               BE.prec, BE.rec, BE.f1));
report(near(BE.iou, 0.686, 0.04), sprintf('IoU %.3f (report 0.686)', BE.iou));
report(mono, sprintf('High %.1f %% > Medium %.1f %% > Low %.1f %% (report 88.4 / 83.7 / 45.5)', ...
                     100*p_c(4), 100*p_c(3), 100*p_c(2)));
report(all(diff(pk(2:end)) > 0), 'precision rises with every extra vote (k = 1 -> N)');

fprintf('\n--- take-away ---\n');
fprintf('Final map: F1 %.3f, precision %.3f, recall %.3f against %d clear Sentinel-2 pixels.\n', ...
        BE.f1, BE.prec, BE.rec, n_eval);
fprintf('High %.1f %% | Medium %.1f %% | Low %.1f %% | Dry %.1f %% observed precision.\n', ...
        100*p_c(4), 100*p_c(3), 100*p_c(2), 100*p_c(1));
fprintf('Precision is the right yardstick for a class: Dry should be LOW (it is the share of water we missed there).\n');
fprintf('Next: spatial block bootstrap (500 m blocks, 1000 repeats, seed 42) for confidence intervals.\n');

%% ============================ local functions ============================

function B = s2_on_grid(f, offset_dn, scale, lat, lon)
% Read a Sentinel-2 L2A band, convert to reflectance, sample it at the S1 pixel lat/lon.
[A, RA] = readgeoraster(f, 'OutputType', 'double');
A(A == 0) = NaN;                                   % L2A nodata
nanmask = isnan(A);
A = max((A + offset_dn) * scale, 0);               % negative reflectance -> 0
A(nanmask) = NaN;                                  % TRAP 3: max(NaN, 0) returns 0, so restore NaN
B = sample_on_grid(A, RA, lat, lon, 'linear');
end

function B = sample_on_grid(A, RA, lat, lon, method)
% Sample raster A (referenced by RA) at the S1 pixel lat/lon.
% Works for lat/lon rasters and projected (UTM) rasters. NaN outside A.
if isa(RA, 'map.rasterref.GeographicCellsReference')
    [xi, yi] = geographicToIntrinsic(RA, lat, lon);
else
    [xq, yq] = projfwd(RA.ProjectedCRS, lat, lon);
    [xi, yi] = worldToIntrinsic(RA, xq, yq);
end
B = interp2(A, xi, yi, method);
end

function s = binmetrics(pred, ref)
% Confusion counts and scores for two logical vectors.
pred = pred(:);  ref = ref(:);
s.tp = nnz(pred & ref);    s.fp = nnz(pred & ~ref);
s.fn = nnz(~pred & ref);   s.tn = nnz(~pred & ~ref);
s.prec = s.tp / max(s.tp + s.fp, 1);
s.rec  = s.tp / max(s.tp + s.fn, 1);
s.f1   = 2*s.prec*s.rec / max(s.prec + s.rec, eps);
s.iou  = s.tp / max(s.tp + s.fp + s.fn, 1);
s.oa   = (s.tp + s.tn) / max(s.tp + s.fp + s.fn + s.tn, 1);
end

function cls = conf_class(k, N, low_min)
% Vote count -> class. 1 Dry | 2 Low | 3 Medium | 4 High  (same rule as step4 / step6a)
cls = ones(size(k), 'uint8');
cls(k >= low_min)            = 2;
cls(k == N-1 & k >= low_min) = 3;
cls(k == N   & k >= low_min) = 4;
end

function report(ok, msg)
if ok, tag = 'PASS'; else, tag = 'FAIL'; end
fprintf('%s  %s\n', tag, msg);
end

