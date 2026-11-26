%% step6a_remove_adaptive.m - does the adaptive member break the confidence ordering?
% Mirrors Step 6A of the report (sensitivity analysis):
%   original ensemble : Otsu VV + Otsu VH + VV change + adaptive   (4 methods)
%   ablated ensemble  : Otsu VV + Otsu VH + VV change              (3 methods)
% For each, the observed precision of every confidence class is measured
% against Sentinel-2 MNDWI, and we ask: is High > Medium > Low?
%
% Contract:
%   in  : matlab/out/masks.mat (step3_masks.m), the S2 MNDWI water reference
%   out : matlab/out/ablation_class_precision.csv, ablation_binary.csv,
%         ablation_adaptive.mat, ablation_adaptive.png
%
% Writes ONLY to matlab/out. data/processed is Python-owned and read-only here.
if ~exist('P','var'), setup_paths; end

%% Section A - inputs and the evaluation set (same as step6b)
f_ref = fullfile(P.processed,'reference','s2_water_mndwi.tif');   % <- edit: 1 water, 0 land
need = {fullfile(P.out,'masks.mat'), f_ref};
for q = 1:numel(need)
    if ~isfile(need{q}), error('Missing input file: %s', need{q}); end
end

S      = load(need{1}, 'masks', 'domain', 'base', 'names');
masks  = S.masks;
domain = S.domain;
base   = S.base;                              % kappa is computed on `base`, as run_masks.py does

[REF, ~] = readgeoraster(need{2}, 'OutputType', 'double');
if ~isequal(size(REF), size(domain))
    error('Reference is %dx%d but the S1 grid is %dx%d - resample it to the S1 grid first.', ...
          size(REF,1), size(REF,2), size(domain,1), size(domain,2));
end

% TRAP 1: cloud / nodata in the reference must not count as "land"
clear_px = ismember(REF, [0 1]);
water    = (REF == 1);
ev       = domain & clear_px;                 % evaluation set: analysis domain AND clear sky
n_eval   = nnz(ev);
refv     = water(ev);
fprintf('evaluated : %d px (%.1f %% of the domain is clear in the reference)\n', ...
        n_eval, 100*n_eval/nnz(domain));

BASE3   = {'otsu_vv','otsu_vh','change_vv'};
ADAPT   = 'adaptive_vv';
K_FLOOD = 2;                                  % binary flood map: k >= 2
PIX_KM2 = 1e-4;

allnames = [BASE3, {ADAPT}];
missing  = setdiff(allnames, S.names);
if ~isempty(missing), error('Mask(s) not in masks.mat: %s', strjoin(missing, ', ')); end

V = struct();
for q = 1:numel(allnames)
    V.(allnames{q}) = masks.(allnames{q})(ev);          % evaluated pixels only
end

%% Section B - the adaptive method on its own: why is it suspect?
MA = binmetrics(V.(ADAPT), refv);
ka = zeros(1, numel(BASE3));
for b = 1:numel(BASE3)
    ka(b) = cohen_kappa(masks.(ADAPT)(base), masks.(BASE3{b})(base));
end
fprintf('\nadaptive alone : precision %.3f | recall %.3f | F1 %.3f\n', MA.prec, MA.rec, MA.f1);
fprintf('adaptive kappa vs base three: %.3f / %.3f / %.3f  (mean %.3f)\n', ka, mean(ka));

%% Section C - the two ensembles
ENS   = {'with_adaptive', 'without_adaptive'};
MEMB  = {[BASE3, {ADAPT}], BASE3};
LOWK  = [2, 1];       % TRAP 2: with 3 methods "Low" is k = 1 (k >= 2 would leave Low empty)
nE = numel(ENS);
cn = {'Dry','Low','Medium','High'};

p_cls = zeros(nE, 4);  n_cls = zeros(nE, 4);
mono  = false(1, nE);
BM    = cell(1, nE);   area = zeros(1, nE);
for e = 1:nE
    members = MEMB{e};  N = numel(members);

    k = zeros(size(refv), 'uint8');                      % votes on the evaluated pixels
    for m = 1:N, k = k + uint8(V.(members{m})); end
    cls = conf_class(k, N, LOWK(e));                     % 1 Dry | 2 Low | 3 Medium | 4 High
    for c = 1:4
        in = (cls == c);
        n_cls(e,c) = nnz(in);
        p_cls(e,c) = nnz(in & refv) / max(nnz(in), 1);   % observed precision of the class
    end
    mono(e) = p_cls(e,4) > p_cls(e,3) && p_cls(e,3) > p_cls(e,2);   % High > Medium > Low
    BM{e}   = binmetrics(k >= K_FLOOD, refv);

    kf = zeros(size(domain), 'uint8');                   % flood area on the whole domain
    for m = 1:N, kf = kf + uint8(masks.(members{m}) & domain); end
    area(e) = nnz(kf >= K_FLOOD) * PIX_KM2;
    clear kf
end

% informational: the 3-method map is also usable as "any vote" (k >= 1)
k3 = zeros(size(refv), 'uint8');
for m = 1:numel(BASE3), k3 = k3 + uint8(V.(BASE3{m})); end
BM3any = binmetrics(k3 >= 1, refv);
clear k3

%% Section D - results
fprintf('\nobserved precision per confidence class (share of class pixels that are reference water)\n');
fprintf('%-17s %8s %8s %8s %8s   %s\n', 'ensemble', cn{:}, 'ordering');
for e = 1:nE
    if mono(e), tag = 'High > Medium > Low'; else, tag = 'NOT monotonic'; end
    fprintf('%-17s %7.1f%% %7.1f%% %7.1f%% %7.1f%%   %s\n', ENS{e}, 100*p_cls(e,:), tag);
end

fprintf('\npixels per class\n');
fprintf('%-17s %9s %9s %9s %9s\n', 'ensemble', cn{:});
for e = 1:nE
    fprintf('%-17s %9d %9d %9d %9d\n', ENS{e}, n_cls(e,:));
end

fprintf('\nbinary flood map (k >= %d)\n', K_FLOOD);
fprintf('%-17s %9s %9s %9s %9s %10s\n', 'ensemble', 'precision', 'recall', 'F1', 'IoU', 'flood km2');
for e = 1:nE
    fprintf('%-17s %9.4f %9.4f %9.4f %9.4f %10.2f\n', ENS{e}, BM{e}.prec, BM{e}.rec, ...
            BM{e}.f1, BM{e}.iou, area(e));
end
fprintf('%-17s %9.4f %9.4f %9.4f %9.4f   (3 methods, k >= 1, for reference)\n', ...
        'without (any)', BM3any.prec, BM3any.rec, BM3any.f1, BM3any.iou);

gap4 = 100*(p_cls(1,4) - p_cls(1,3));
gap3 = 100*(p_cls(2,4) - p_cls(2,3));
fprintf('\nHigh minus Medium precision: %+.1f points with adaptive | %+.1f points without\n', gap4, gap3);
fprintf('binary F1 change when adaptive is removed: %+.4f\n', BM{2}.f1 - BM{1}.f1);

%% Section E - save tables
Tp = table(cn(:), 100*p_cls(1,:)', 100*p_cls(2,:)', n_cls(1,:)', n_cls(2,:)', ...
    'VariableNames', {'class','precision_pct_with_adaptive','precision_pct_without_adaptive', ...
                      'pixels_with_adaptive','pixels_without_adaptive'});
writetable(Tp, fullfile(P.out,'ablation_class_precision.csv'));

Tb = table(ENS(:), cellfun(@(s) s.tp, BM(:)), cellfun(@(s) s.fp, BM(:)), ...
           cellfun(@(s) s.fn, BM(:)), cellfun(@(s) s.tn, BM(:)), ...
           cellfun(@(s) s.prec, BM(:)), cellfun(@(s) s.rec, BM(:)), ...
           cellfun(@(s) s.f1, BM(:)), cellfun(@(s) s.iou, BM(:)), area(:), mono(:), ...
    'VariableNames', {'ensemble','tp','fp','fn','tn','precision','recall','f1','iou', ...
                      'flood_km2','monotonic'});
writetable(Tb, fullfile(P.out,'ablation_binary.csv'));
save(fullfile(P.out,'ablation_adaptive.mat'), 'p_cls', 'n_cls', 'mono', 'ENS', 'cn');

%% Section F - figure
col = [0.80 0.40 0.30; 0.20 0.45 0.85];                  % with adaptive | without adaptive
figure('Color','w','Position',[80 80 1000 420]);

subplot(1,2,1);
b = bar(100*p_cls');                                     % classes on the x-axis
for e = 1:nE, b(e).FaceColor = col(e,:); end
set(gca, 'XTickLabel', cn); ylabel('observed precision (%)'); ylim([0 105]); grid on
for e = 1:nE
    for c = 1:4
        text(b(e).XEndPoints(c), 100*p_cls(e,c), sprintf('%.1f', 100*p_cls(e,c)), ...
             'HorizontalAlignment','center', 'VerticalAlignment','bottom', 'FontSize',8);
    end
end
lg = cell(1, nE);
for e = 1:nE
    if mono(e), s = 'ordered'; else, s = 'NOT ordered'; end
    lg{e} = sprintf('%s (%s)', strrep(ENS{e},'_',' '), s);
end
legend(lg, 'Location', 'southoutside');
title('Class precision vs Sentinel-2 MNDWI');

subplot(1,2,2);
b2 = bar(n_cls');
for e = 1:nE, b2(e).FaceColor = col(e,:); end
set(gca, 'XTickLabel', cn, 'YScale', 'log'); ylabel('pixels (log scale)'); grid on
title('Class sizes');
saveas(gcf, fullfile(P.out,'ablation_adaptive.png'));

%% Section G - self-check (numbers from the report)
near = @(a, b, tol) abs(a - b) <= tol;
fprintf('\n--- step6a verification ---\n');
report(abs(n_eval - 5550032)/5550032 < 0.02, ...
       sprintf('evaluated pixels %d within 2 %% of the report (5,550,032)', n_eval));
report(~mono(1) && p_cls(1,4) < p_cls(1,3), ...
       sprintf('with adaptive: High %.1f %% < Medium %.1f %% (ordering broken, as reported)', ...
               100*p_cls(1,4), 100*p_cls(1,3)));
report(near(p_cls(1,1), 0.049, 0.02) && near(p_cls(1,2), 0.829, 0.03) && ...
       near(p_cls(1,3), 0.886, 0.02) && near(p_cls(1,4), 0.771, 0.02), ...
       sprintf('original four-method precisions %.1f / %.1f / %.1f / %.1f %% (report 4.9 / 82.9 / 88.6 / 77.1)', ...
               100*p_cls(1,:)));
report(near(BM{1}.prec, 0.866, 0.02) && near(BM{1}.rec, 0.761, 0.02) && near(BM{1}.iou, 0.680, 0.02), ...
       sprintf('original binary map precision %.3f / recall %.3f / IoU %.3f (report 0.866 / 0.761 / 0.680)', ...
               BM{1}.prec, BM{1}.rec, BM{1}.iou));
report(mono(2), 'without adaptive: High > Medium > Low is restored');
report(near(p_cls(2,1), 0.033, 0.02) && near(p_cls(2,2), 0.432, 0.03) && ...
       near(p_cls(2,3), 0.826, 0.02) && near(p_cls(2,4), 0.884, 0.02), ...
       sprintf('three-method precisions %.1f / %.1f / %.1f / %.1f %% (report 3.3 / 43.2 / 82.6 / 88.4)', ...
               100*p_cls(2,:)));
report(MA.rec < 0.5 && mean(ka) < 0.15, ...
       sprintf('adaptive is the weak member: recall %.3f, kappa vs base three %.3f', MA.rec, mean(ka)));

fprintf('\n--- take-away ---\n');
fprintf('With adaptive, High (%.1f %%) is less precise than Medium (%.1f %%).\n', ...
        100*p_cls(1,4), 100*p_cls(1,3));
fprintf('Without it, High %.1f %% > Medium %.1f %% > Low %.1f %%: the ordering returns.\n', ...
        100*p_cls(2,4), 100*p_cls(2,3), 100*p_cls(2,2));
fprintf('Next (step 6b): replace adaptive with Kittler or GMM to keep four members.\n');

%% ============================ local functions ============================

function s = binmetrics(pred, ref)
% Confusion counts and scores for two logical vectors.
pred = pred(:);  ref = ref(:);
s.tp = nnz(pred & ref);    s.fp = nnz(pred & ~ref);
s.fn = nnz(~pred & ref);   s.tn = nnz(~pred & ~ref);
s.prec = s.tp / max(s.tp + s.fp, 1);
s.rec  = s.tp / max(s.tp + s.fn, 1);
s.f1   = 2*s.prec*s.rec / max(s.prec + s.rec, eps);
s.iou  = s.tp / max(s.tp + s.fp + s.fn, 1);
end

function cls = conf_class(k, N, low_min)
% Vote count -> class. 1 Dry | 2 Low | 3 Medium | 4 High
%   Dry    : k < low_min        (4 methods: low_min = 2, 3 methods: low_min = 1)
%   Low    : k >= low_min, but not enough for Medium
%   Medium : all except one agree (k = N-1)
%   High   : all agree (k = N)
cls = ones(size(k), 'uint8');
cls(k >= low_min)                = 2;
cls(k == N-1 & k >= low_min)     = 3;
cls(k == N   & k >= low_min)     = 4;
end

function [k, po] = cohen_kappa(a, b)
% Cohen's kappa for two logical masks: (observed - chance agreement) / (1 - chance)
a = a(:);  b = b(:);
n   = numel(a);
n11 = nnz(a & b);   n10 = nnz(a & ~b);   n01 = nnz(~a & b);
n00 = n - n11 - n10 - n01;
po  = (n11 + n00) / n;
pe  = ((n11+n10)*(n11+n01) + (n01+n00)*(n10+n00)) / n^2;
if pe == 1, k = NaN; else, k = (po - pe) / (1 - pe); end
end

function report(ok, msg)
if ok, tag = 'PASS'; else, tag = 'FAIL'; end
fprintf('%s  %s\n', tag, msg);
end