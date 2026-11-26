%% step6b_alternative_members.m - replace the adaptive member? Kittler vs GMM
% Mirrors the alternative-member validation of the report (Step 6B):
%   (1) validate the candidate 4th members (adaptive, Kittler, GMM) against S2 MNDWI
%   (2) check how well each agrees with the three base methods (Cohen's kappa)
%   (3) rebuild the four-method confidence ensemble with each candidate
%   (4) keep the candidate that gives a monotonic High > Medium > Low ordering
%       and the best binary (k >= 2) F1
%
% Contract:
%   in  : matlab/out/masks.mat (step3_masks.m), the S2 MNDWI water reference
%   out : matlab/out/alt_member_metrics.csv, alt_ensemble_metrics.csv,
%         alt_member_choice.mat, alt_members.png, alt_ensembles.png
%
% Writes ONLY to matlab/out. data/processed is Python-owned and read-only here.
if ~exist('P','var'), setup_paths; end

%% Section A - inputs and the evaluation set
f_ref = fullfile(P.out,'s2_water_mndwi.tif');
if ~isfile(f_ref)
    f_ref = fullfile(P.processed,'reference','s2_water_mndwi.tif');   % <- 1 water, 0 land
end
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
clear_px = ismember(REF, [0 1]);              % NaN, 255, -9999 ... -> not clear
water    = (REF == 1);
ev       = domain & clear_px;                 % evaluation set: analysis domain AND clear sky
n_eval   = nnz(ev);
fprintf('evaluated : %d px (%.1f %% of the domain is clear in the reference)\n', ...
        n_eval, 100*n_eval/nnz(domain));
fprintf('reference : %.1f %% water in the evaluated pixels\n', 100*nnz(water & ev)/n_eval);

BASE3   = {'otsu_vv','otsu_vh','change_vv'};
CAND    = {'adaptive_vv','kittler','gmm'};    % candidate 4th members
K_FLOOD = 2;                                  % binary flood map: k >= 2
PIX_KM2 = 1e-4;

allnames = [BASE3, CAND];
missing  = setdiff(allnames, S.names);
if ~isempty(missing), error('Mask(s) not in masks.mat: %s', strjoin(missing, ', ')); end

%% Section B - masks restricted to the evaluation set
refv = water(ev);                             % reference water, evaluated pixels only
V = struct();
for q = 1:numel(allnames)
    V.(allnames{q}) = masks.(allnames{q})(ev);
end

%% Section C - the candidates on their own (precision / recall / F1) and their kappa
nC = numel(CAND);
MM = cell(1, nC);
kb = zeros(1, nC);                            % mean kappa vs the three base methods
for c = 1:nC
    MM{c} = binmetrics(V.(CAND{c}), refv);
    ks = zeros(1, numel(BASE3));
    for b = 1:numel(BASE3)
        ks(b) = cohen_kappa(masks.(CAND{c})(base), masks.(BASE3{b})(base));
    end
    kb(c) = mean(ks);
end

fprintf('\n%-13s %9s %9s %9s %9s %12s\n', 'candidate', 'precision', 'recall', 'F1', 'IoU', 'kappa vs 3');
for c = 1:nC
    fprintf('%-13s %9.3f %9.3f %9.3f %9.3f %12.3f\n', CAND{c}, MM{c}.prec, MM{c}.rec, ...
            MM{c}.f1, MM{c}.iou, kb(c));
end

%% Section D - the four-method confidence ensemble with each candidate
ENS = strcat(strrep(CAND, '_vv', ''), '_4th');   % adaptive_4th, kittler_4th, gmm_4th
nE  = nC;
EM  = cell(1, nE);
p_cls = zeros(nE, 4);  n_cls = zeros(nE, 4);     % columns: Dry, Low, Medium, High
mono  = false(1, nE);
area  = zeros(1, nE);
for e = 1:nE
    members = [BASE3, CAND(e)];
    N = numel(members);

    k = zeros(size(refv), 'uint8');                      % votes, evaluated pixels
    for m = 1:N, k = k + uint8(V.(members{m})); end
    cls = conf_class(k, N);                              % 1 Dry | 2 Low | 3 Medium | 4 High
    for c = 1:4
        in = (cls == c);
        n_cls(e,c) = nnz(in);
        p_cls(e,c) = nnz(in & refv) / max(nnz(in), 1);   % observed precision of the class
    end
    EM{e}   = binmetrics(k >= K_FLOOD, refv);
    mono(e) = p_cls(e,4) > p_cls(e,3) && p_cls(e,3) > p_cls(e,2);   % High > Medium > Low

    kf = zeros(size(domain), 'uint8');                   % flood area on the whole domain
    for m = 1:N, kf = kf + uint8(masks.(members{m}) & domain); end
    area(e) = nnz(kf >= K_FLOOD) * PIX_KM2;
    clear kf
end

cn = {'Dry','Low','Medium','High'};
fprintf('\nobserved precision per confidence class (share of class pixels that are reference water)\n');
fprintf('%-13s %8s %8s %8s %8s   %s\n', 'ensemble', cn{:}, 'ordering');
for e = 1:nE
    if mono(e), tag = 'High > Medium > Low'; else, tag = 'NOT monotonic'; end
    fprintf('%-13s %7.1f%% %7.1f%% %7.1f%% %7.1f%%   %s\n', ENS{e}, 100*p_cls(e,:), tag);
end

fprintf('\nbinary flood map (k >= %d)\n', K_FLOOD);
fprintf('%-13s %9s %9s %9s %9s %10s\n', 'ensemble', 'precision', 'recall', 'F1', 'IoU', 'flood km2');
for e = 1:nE
    fprintf('%-13s %9.4f %9.4f %9.4f %9.4f %10.2f\n', ENS{e}, EM{e}.prec, EM{e}.rec, ...
            EM{e}.f1, EM{e}.iou, area(e));
end

%% Section E - the decision: monotonic ordering first, then the best binary F1
f1s = cellfun(@(s) s.f1, EM);
ok  = find(mono);
if isempty(ok)
    chosen = 0;
    fprintf('\nNo candidate gives a monotonic ordering - keep investigating.\n');
else
    [~, i] = max(f1s(ok));
    chosen = ok(i);
    fprintf('\nDecision: %s as 4th member  (%s)\n', CAND{chosen}, ...
            strjoin([BASE3, CAND(chosen)], ', '));
    fprintf('  monotonic ordering : %s\n', string(mono(chosen)));
    fprintf('  binary F1          : %.4f (best among monotonic ensembles)\n', f1s(chosen));
end
ik = find(strcmp(CAND, 'kittler'));  ig = find(strcmp(CAND, 'gmm'));
fprintf('  GMM vs Kittler as members: recall %.3f vs %.3f | F1 %.3f vs %.3f\n', ...
        MM{ig}.rec, MM{ik}.rec, MM{ig}.f1, MM{ik}.f1);

%% Section F - save tables and the choice
Tm = table(CAND(:), cellfun(@(s) s.tp, MM(:)), cellfun(@(s) s.fp, MM(:)), ...
           cellfun(@(s) s.fn, MM(:)), cellfun(@(s) s.tn, MM(:)), ...
           cellfun(@(s) s.prec, MM(:)), cellfun(@(s) s.rec, MM(:)), ...
           cellfun(@(s) s.f1, MM(:)), cellfun(@(s) s.iou, MM(:)), kb(:), ...
    'VariableNames', {'method','tp','fp','fn','tn','precision','recall','f1','iou','mean_kappa_vs_base3'});
writetable(Tm, fullfile(P.out,'alt_member_metrics.csv'));

mem_str = cellfun(@(c) strjoin([BASE3, {c}], '+'), CAND(:), 'UniformOutput', false);
sel = false(nE,1);  if chosen > 0, sel(chosen) = true; end
Te = table(ENS(:), mem_str, cellfun(@(s) s.tp, EM(:)), cellfun(@(s) s.fp, EM(:)), ...
           cellfun(@(s) s.fn, EM(:)), cellfun(@(s) s.tn, EM(:)), ...
           cellfun(@(s) s.prec, EM(:)), cellfun(@(s) s.rec, EM(:)), ...
           cellfun(@(s) s.f1, EM(:)), cellfun(@(s) s.iou, EM(:)), area(:), ...
           p_cls(:,1), p_cls(:,2), p_cls(:,3), p_cls(:,4), mono(:), sel, ...
    'VariableNames', {'ensemble','members','tp','fp','fn','tn','precision','recall','f1','iou', ...
                      'flood_km2','prec_dry','prec_low','prec_medium','prec_high','monotonic','selected'});
writetable(Te, fullfile(P.out,'alt_ensemble_metrics.csv'));
save(fullfile(P.out,'alt_member_choice.mat'), 'chosen', 'CAND', 'BASE3', 'ENS', 'mono', 'p_cls', 'n_cls');

%% Section G - figures
cc = [0.70 0.70 0.70; 0.65 0.80 0.95; 0.30 0.58 0.88; 0.05 0.20 0.55];   % Dry, Low, Medium, High

figure('Color','w','Position',[80 80 1000 400]);
subplot(1,2,1);
bar([cellfun(@(s) s.prec, MM(:)), cellfun(@(s) s.rec, MM(:)), cellfun(@(s) s.f1, MM(:))]);
set(gca, 'XTickLabel', strrep(CAND,'_',' ')); ylim([0 1]); grid on
legend('precision','recall','F1','Location','southoutside','Orientation','horizontal');
title('Candidate 4th members vs Sentinel-2 MNDWI');
subplot(1,2,2);
bar(kb, 'FaceColor', [.3 .3 .35]);
set(gca, 'XTickLabel', strrep(CAND,'_',' ')); ylim([0 1]); ylabel('mean Cohen''s \kappa'); grid on
title('Agreement with the three base methods');
saveas(gcf, fullfile(P.out,'alt_members.png'));

figure('Color','w','Position',[80 80 900 420]);
b = bar(100*p_cls);
for c = 1:4, b(c).FaceColor = cc(c,:); end
xl = cell(1, nE);
for e = 1:nE
    if mono(e), tag = 'ordered'; else, tag = 'NOT ordered'; end
    xl{e} = sprintf('%s | %s', strrep(ENS{e},'_',' '), tag);
end
set(gca, 'XTickLabel', xl); grid on
ylabel('% of class pixels that are water in the reference');
legend(cn, 'Location', 'northwest');
title('Observed precision of each confidence class');
saveas(gcf, fullfile(P.out,'alt_ensembles.png'));

%% Section H - self-check (numbers from the report)
near = @(a, b, tol) abs(a - b) <= tol;
ia = find(strcmp(CAND,'adaptive_vv'));
fprintf('\n--- step6b verification ---\n');
report(abs(n_eval - 5550032)/5550032 < 0.02, ...
       sprintf('evaluated pixels %d within 2 %% of the report (5,550,032)', n_eval));
report(near(MM{ik}.prec, 0.925, 0.02) && near(MM{ik}.rec, 0.667, 0.02), ...
       sprintf('Kittler precision %.3f / recall %.3f (report 0.925 / 0.667)', MM{ik}.prec, MM{ik}.rec));
report(near(MM{ig}.prec, 0.788, 0.02) && near(MM{ig}.rec, 0.815, 0.02), ...
       sprintf('GMM precision %.3f / recall %.3f (report 0.788 / 0.815)', MM{ig}.prec, MM{ig}.rec));
report(kb(ia) > 0.02 && kb(ia) < 0.15, ...
       sprintf('adaptive kappa vs the base three %.3f (report 0.06-0.08)', kb(ia)));
report(kb(ik) > 0.5 && kb(ig) > 0.5, ...
       sprintf('Kittler %.2f and GMM %.2f agree much better with the base three', kb(ik), kb(ig)));
report(~mono(ia) && near(EM{ia}.prec, 0.866, 0.02) && near(EM{ia}.rec, 0.761, 0.02), ...
       'original four-method ensemble: NOT monotonic, precision 0.866 / recall 0.761');
report(mono(ig), 'GMM ensemble has a monotonic High > Medium > Low ordering');
report(near(EM{ig}.f1, 0.8138, 0.01) && near(EM{ig}.prec, 0.826, 0.01) && near(EM{ig}.rec, 0.802, 0.01), ...
       sprintf('GMM ensemble binary F1 %.4f / precision %.3f / recall %.3f (report 0.8138 / 0.826 / 0.802)', ...
               EM{ig}.f1, EM{ig}.prec, EM{ig}.rec));
report(all(near(p_cls(ig,2:4), [0.455 0.837 0.884], 0.03)), ...
       sprintf('GMM class precision Low/Medium/High %.1f / %.1f / %.1f %% (report 45.5 / 83.7 / 88.4)', ...
               100*p_cls(ig,2:4)));
report(chosen == ig, 'the decision picks GMM as the 4th member');

f_ea = fullfile(P.tables, 'ensemble_area.csv');
if isfile(f_ea)
    EA = readtable(f_ea, 'TextType', 'string');
    py = EA.k_ge2_km2(strcmp(EA.ensemble, 'gmm_4th'));
    if ~isempty(py)
        report(abs(area(ig) - py)/py < 0.01, ...
               sprintf('GMM ensemble area %.2f km2 within 1 %% of Python %.2f km2', area(ig), py));
    end
end

fprintf('\n--- take-away ---\n');
fprintf('Adaptive: recall %.3f, kappa %.2f with the base three -> the weak, uncorrelated member.\n', ...
        MM{ia}.rec, kb(ia));
fprintf('Kittler is more precise (%.3f) but misses water (recall %.3f); GMM balances both (F1 %.3f).\n', ...
        MM{ik}.prec, MM{ik}.rec, MM{ig}.f1);

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

function cls = conf_class(k, N)
% Vote count -> class. 1 Dry | 2 Low | 3 Medium | 4 High  (same rule as step4)
cls = ones(size(k), 'uint8');                 % k <= 1  -> Dry
cls(k >= 2)            = 2;                   % at least two agree -> Low ...
cls(k == N-1 & k >= 2) = 3;                   % ... all except one -> Medium
cls(k == N   & k >= 2) = 4;                   % ... all agree      -> High
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