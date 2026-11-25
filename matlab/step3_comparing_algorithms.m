%% step3_comparing_algorithms.m - are the thresholding methods really independent?
% Contributed by Pritom. Cohen's kappa between methods:
%   (1) Otsu VV vs Otsu VH        same algorithm, different polarization
%   (2) Otsu vs change detection  single image vs before/after
%   (3) Adaptive vs the others    local threshold vs global thresholds
% Then: does adding methods add confidence, or just repeat one answer?
%
% Changed from the first version so the numbers are comparable with Python:
%   * consumes matlab/out/masks.mat from step3_masks.m instead of rebuilding
%     the masks here (a rebuilt adaptive mask used window 151 / sensitivity 0.5
%     and a +3 dB guard, which is not the canonical member)
%   * kappa is computed over `base`, exactly as run_masks.py does, so the values
%     can be checked against outputs/tables/mask_kappa.csv
%   * the ADR-23 rule (4 members, k >= 2) is reported explicitly
%
% Needs : matlab/out/masks.mat (step3_masks.m)
% Outputs: out/kappa_matrix.png, out/kappa_pairs.png, out/kappa_redundancy.png,
%          out/kappa_disagreement_maps.png, out/kappa_summary.csv,
%          out/kappa_matrix.csv, out/kappa_vs_python.csv
if ~exist('P','var'), setup_paths; end

%% Section A - inputs and the common comparison set
need = {fullfile(P.out,'masks.mat'), fullfile(P.tables,'mask_kappa.csv'), ...
        fullfile(P.tables,'ensemble_area.csv')};
for k = 1:numel(need)
    if ~isfile(need{k}), error('Missing input file: %s (run step3_masks first)', need{k}); end
end

S     = load(need{1}, 'masks', 'base', 'domain', 't_mat', 'names');
masks = S.masks;
names = S.names;
nM    = numel(names);
lab   = strrep(names,'_',' ');
t     = S.t_mat;
PIX_M = 10;

ia = find(strcmp(names,'adaptive_vv'));    % adaptive has no single threshold

% TRAP: kappa is only comparable if every method is judged on the SAME pixels.
% run_masks.py uses `base` (radar-valid, not permanent water) - including the
% steep pixels, where every mask is 0 by construction - so we use `base` too.
dom = S.base;
fprintf('comparison set : %d px (base, %.1f %% of the scene)\n', nnz(dom), 100*nnz(dom)/numel(dom));
fprintf('analysis domain: %d px (%.3f km2)\n', nnz(S.domain), nnz(S.domain)*1e-4);

%% Section B - the six masks, as built by step3_masks.m
Fd = false(nnz(dom), nM);                  % one column per method, domain pixels only
for k = 1:nM, Fd(:,k) = masks.(names{k})(dom); end
n_dom = size(Fd,1);

area_km2  = sum(Fd,1) * PIX_M^2 / 1e6;
prevalence = 100*mean(Fd,1);
fprintf('\n%-12s %12s %10s %10s\n','method','thr (dB)','flood km2','flood %');
for k = 1:nM
    fprintf('%-12s %12.3f %10.2f %10.2f\n', names{k}, t(k), area_km2(k), prevalence(k));
end

%% Section C - Cohen's kappa for every pair of methods
KAPPA = zeros(nM);  PO = zeros(nM);
for i = 1:nM
    for j = 1:nM
        [KAPPA(i,j), PO(i,j)] = cohen_kappa(Fd(:,i), Fd(:,j));
    end
end

fprintf('\nCohen''s kappa (1 = identical, 0 = no better than chance):\n');
fprintf('%-12s', ''); fprintf('%10s', names{:}); fprintf('\n');
for i = 1:nM
    fprintf('%-12s', names{i}); fprintf('%10.3f', KAPPA(i,:)); fprintf('\n');
end

%% Section D - the three comparisons
fprintf('\n=== (1) Otsu VV vs Otsu VH  (same algorithm, different data) ===\n');
k12 = KAPPA(1,2);
fprintf('kappa = %.3f (%s) | raw agreement %.1f %%\n', k12, landis(k12), 100*PO(1,2));

fprintf('\n=== (2) Otsu vs change detection  (static vs temporal) ===\n');
k13 = KAPPA(1,3);
fprintf('Otsu VV vs change : kappa = %.3f (%s)\n', k13, landis(k13));
fprintf('Otsu VH vs change : kappa = %.3f (%s)\n', KAPPA(2,3), landis(KAPPA(2,3)));

fprintf('\n=== (3) Adaptive vs the other methods ===\n');
ka_idx = setdiff(1:nM, ia);
for k = ka_idx
    fprintf('adaptive vs %-12s: kappa = %.3f (%s)\n', names{k}, KAPPA(ia,k), landis(KAPPA(ia,k)));
end
ka = KAPPA(ia, ka_idx);
fprintf('mean kappa adaptive vs others = %.3f\n', mean(ka));

%% Section E - does a bigger ensemble add confidence, or just repeat itself?
off   = KAPPA;  off(1:nM+1:end) = NaN;
kbar  = mean(off(:),'omitnan');                     % mean pairwise kappa, all six
keep  = ka_idx;                                     % the five non-adaptive methods
kbar5 = mean(reshape(KAPPA(keep,keep) + diag(nan(numel(keep),1)),[],1),'omitnan');
N_eff = nM / (1 + (nM-1)*min(max(kbar,0),1));       % heuristic "independent votes"
fprintf('\nmean pairwise kappa: all %d = %.3f | without adaptive = %.3f\n', nM, kbar, kbar5);
fprintf('effective number of independent methods ~ %.2f out of %d (heuristic)\n', N_eff, nM);

votes   = sum(Fd,2);
cons    = votes > nM/2;                             % strict majority, DIAGNOSTIC only
fprintf('strict majority of all %d: %.2f km2 (>%d votes) - NOT the adopted rule\n', ...
        nM, nnz(cons)*PIX_M^2/1e6, floor(nM/2));

% the adopted rule (ADR-23): four members, flood-positive when k >= 2
EA   = readtable(need{3},'TextType','string');
ens4 = {'otsu_vv','otsu_vh','change_vv','gmm'};
v4   = sum(Fd(:, ismember(names, ens4)), 2);
gmm_km2 = EA.k_ge2_km2(strcmp(EA.ensemble,'gmm_4th'));
% TRAP: kappa is computed over `base`, but the FLOOD MAP is defined on the
% analysis domain. Mask Fd rows so the ADR-23 area is comparable with
% ensemble_area.csv (which intersects with the domain, as agreement.py does).
dom_in_base = S.domain(dom);
v4a         = sum(Fd(:, ismember(names,{'otsu_vv','otsu_vh','change_vv','adaptive_vv'})), 2);
adr23_km2   = nnz((v4 >= 2) & dom_in_base) * PIX_M^2/1e6;
adr23a_km2  = nnz((v4a >= 2) & dom_in_base) * PIX_M^2/1e6;
fprintf('ADR-23 ensemble (4 members, k >= 2): %.2f km2   (Python gmm_4th %.2f km2)\n', ...
        adr23_km2, gmm_km2);

kcons = zeros(1,nM);  kloo = zeros(1,nM);
for k = 1:nM
    kcons(k) = cohen_kappa(Fd(:,k), cons);          % method vs full consensus
    rest = setdiff(1:nM, k);
    cons_k = sum(Fd(:,rest),2) > numel(rest)/2;     % consensus WITHOUT method k
    kloo(k) = cohen_kappa(cons, cons_k);            % ~1 -> method k changes nothing
end
fprintf('\n%-12s %18s %22s\n','method','kappa vs consensus','kappa consensus w/o it');
for k = 1:nM, fprintf('%-12s %18.3f %22.3f\n', names{k}, kcons(k), kloo(k)); end

vc = histcounts(votes, -0.5:1:nM+0.5);
fprintf('\nvotes   share of comparison set\n');
for v = 0:nM, fprintf('%d       %6.2f %%\n', v, 100*vc(v+1)/n_dom); end
flood_any = nnz(votes > 0);
fprintf('unanimous = %.1f %% of everything any method calls flood\n', 100*vc(nM+1)/flood_any);

%% Section F - figure 1: full kappa matrix
figure('Color','w','Position',[80 80 640 560]);
imagesc(KAPPA); axis image; caxis([0 1]); colorbar; colormap(parula);
set(gca,'XTick',1:nM,'XTickLabel',lab,'YTick',1:nM,'YTickLabel',lab);
for i = 1:nM
    for j = 1:nM
        text(j,i,sprintf('%.2f',KAPPA(i,j)),'HorizontalAlignment','center', ...
             'Color','w','FontWeight','bold');
    end
end
title('Cohen''s \kappa between thresholding methods');
saveas(gcf, fullfile(P.out,'kappa_matrix.png'));

%% Section G - figure 2: the three comparisons
vals  = [k12, k13, ka];
blab  = [{'Otsu VV vs VH','Otsu VV vs change'}, strcat('adaptive vs ', lab(ka_idx))];
figure('Color','w','Position',[80 80 900 420]);
b = bar(vals, 'FaceColor', 'flat');
b.CData(1,:) = [.85 .33 .10];  b.CData(2,:) = [.93 .69 .13];
for k = 3:numel(vals), b.CData(k,:) = [.20 .45 .85]; end
hold on
for yv = [0.2 0.4 0.6 0.8], yline(yv,':','Color',[.5 .5 .5]); end
set(gca,'XTick',1:numel(vals),'XTickLabel',blab,'XTickLabelRotation',30);
ylim([min(0,min(vals)-0.05) 1]); ylabel('Cohen''s \kappa'); grid on
title('Pairwise agreement (dotted lines: Landis-Koch bands)');
saveas(gcf, fullfile(P.out,'kappa_pairs.png'));

%% Section H - figure 3: redundancy
figure('Color','w','Position',[80 80 1000 400]);
subplot(1,2,1);
bar([kcons; kloo]'); set(gca,'XTick',1:nM,'XTickLabel',lab,'XTickLabelRotation',30);
ylim([min(0.5, min([kcons kloo])-0.05) 1.0]); ylabel('\kappa'); grid on
legend('method vs consensus','consensus without method','Location','southoutside');
title('A method with \kappa \approx 1 adds nothing');
subplot(1,2,2);
bar(0:nM, 100*vc/n_dom,'FaceColor',[.3 .3 .35]);
xlabel('number of methods saying flood'); ylabel('% of comparison set'); grid on
set(gca,'YScale','log'); title(sprintf('Vote counts (N_{eff} \\approx %.1f of %d)', N_eff, nM));
saveas(gcf, fullfile(P.out,'kappa_redundancy.png'));

%% Section I - figure 4: where do the paired methods disagree?
[nr, nc] = size(dom);
ds = max(1, floor(max(nr,nc)/1200));
ri = 1:ds:nr;  ci = 1:ds:nc;
others = sum(Fd(:,ka_idx),2) > numel(ka_idx)/2;         % consensus of the other five
pairs = {Fd(:,1),  Fd(:,2), 'Otsu VV | Otsu VH', 'Otsu VV',  'Otsu VH'; ...
         Fd(:,1),  Fd(:,3), 'Otsu VV | change',  'Otsu VV',  'change'; ...
         Fd(:,ia), others, 'adaptive | other five', 'adaptive', 'other five'};
figure('Color','w','Position',[60 60 1150 420]);
for q = 1:3
    a = pairs{q,1};  c = pairs{q,2};
    cat4 = zeros(n_dom,1);  cat4(a & c) = 1;  cat4(a & ~c) = 2;  cat4(~a & c) = 3;
    tmp = nan(nr,nc);  tmp(dom) = cat4;
    subplot(1,3,q); imagesc(tmp(ri,ci)); axis image off; caxis([0 3]);
    colormap(gca, [0.88 0.88 0.88; 0.10 0.35 0.90; 0.85 0.20 0.15; 0.95 0.65 0.10]);
    title(sprintf('%s   \\kappa = %.2f', pairs{q,3}, cohen_kappa(a,c)));
    xlabel(sprintf('blue: both | red: only %s | orange: only %s', pairs{q,4}, pairs{q,5}));
end
saveas(gcf, fullfile(P.out,'kappa_disagreement_maps.png'));

%% Section J - save tables, and check against Python
Tsum = table(names(:), t(:), area_km2(:), prevalence(:), kcons(:), kloo(:), ...
    'VariableNames', {'method','threshold_db','flood_km2','flood_pct', ...
                      'kappa_vs_consensus','kappa_consensus_without_method'});
writetable(Tsum, fullfile(P.out,'kappa_summary.csv'));
Kt = array2table(KAPPA, 'VariableNames', names, 'RowNames', names);
writetable(Kt, fullfile(P.out,'kappa_matrix.csv'), 'WriteRowNames', true);

% Python reference: outputs/tables/mask_kappa.csv (four-method ensemble only)
Kp  = readtable(need{2},'TextType','string');
fid = fopen(fullfile(P.out,'kappa_vs_python.csv'),'w');
fprintf(fid,'a,b,kappa_matlab,kappa_python,diff\n');
paired_ok = true;
for r = 1:height(Kp)
    a = Kp.a(r);  b = Kp.b(r);  kp = Kp.kappa(r);
    km = KAPPA(find(strcmp(names,a)), find(strcmp(names,b)));
    d  = km - kp;
    paired_ok = paired_ok && abs(d) < 0.02;
    fprintf(fid,'%s,%s,%.4f,%.4f,%+.4f\n', a, b, km, kp, d);
    fprintf('%-12s %-12s MATLAB %.4f | Python %.4f | d=%+.4f\n', a, b, km, kp, d);
end
fclose(fid);
fprintf('Wrote kappa_summary.csv, kappa_matrix.csv, kappa_vs_python.csv in %s\n', P.out);

%% Section K - self-check and take-away
fprintf('\n--- step3_comparing_algorithms verification ---\n');
report(all(abs(diag(KAPPA) - 1) < 1e-12) && max(abs(KAPPA(:) - reshape(KAPPA',[],1))) < 1e-12, ...
       'kappa matrix is symmetric with 1 on the diagonal');
rng(1);
shuf = Fd(randperm(n_dom), 1);                      % same flood %, random place
ks = cohen_kappa(Fd(:,1), shuf);
report(abs(ks) < 0.01, sprintf('shuffled mask gives kappa %.4f (chance level is 0)', ks));
report(all(isfinite(KAPPA(:))) && all(KAPPA(:) >= -1 & KAPPA(:) <= 1), ...
       'all kappa values are defined and inside [-1, 1]');
report(paired_ok, 'every pairwise kappa agrees with mask_kappa.csv to within 0.02');
report(abs(adr23_km2 - gmm_km2)/gmm_km2 < 0.01, ...
       sprintf('ADR-23 k>=2 area %.2f km2 within 1 %% of the Python GMM ensemble %.2f km2', ...
               adr23_km2, gmm_km2));
if any(prevalence < 1)
    fprintf('WARN  a method flags < 1 %% of the comparison set: kappa is unstable at low prevalence\n');
end

fprintf('\n--- take-away ---\n');
if kbar > 0.8
    fprintf('Mean kappa %.2f: the methods are almost the same classifier. The vote count mostly repeats one answer.\n', kbar);
elseif kbar > 0.6
    fprintf('Mean kappa %.2f: substantial overlap. About %.1f independent methods out of %d.\n', kbar, N_eff, nM);
else
    fprintf('Mean kappa %.2f: the methods differ enough that votes carry extra information.\n', kbar);
end
[~, redundant] = max(kloo);
fprintf(['Most redundant method under a strict-majority-of-%d rule: %s ' ...
         '(kappa %.3f for the consensus without it).\n'], ...
        nM, names{redundant}, kloo(redundant));
fprintf(['NB: strict majority is not the adopted rule. Under ADR-23 (k >= 2) the 4th member ' ...
         'sets the binary area (adaptive %.1f -> GMM %.1f km2), which is why GMM is retained.\n'], ...
        adr23a_km2, adr23_km2);

%% ============================ local functions ============================

function [k, po] = cohen_kappa(a, b)
% Cohen's kappa for two logical masks: (observed - chance agreement) / (1 - chance)
a = a(:);  b = b(:);
n   = numel(a);
n11 = nnz(a & b);   n10 = nnz(a & ~b);   n01 = nnz(~a & b);
n00 = n - n11 - n10 - n01;
po  = (n11 + n00) / n;                                       % observed agreement
pe  = ((n11+n10)*(n11+n01) + (n01+n00)*(n10+n00)) / n^2;     % agreement expected by chance
if pe == 1, k = NaN; else, k = (po - pe) / (1 - pe); end
end

function s = landis(k)
% Landis & Koch (1977) verbal bands
if isnan(k),     s = 'undefined';
elseif k < 0,    s = 'worse than chance';
elseif k <= 0.2, s = 'slight';
elseif k <= 0.4, s = 'fair';
elseif k <= 0.6, s = 'moderate';
elseif k <= 0.8, s = 'substantial';
else             s = 'almost perfect';
end
end

function report(ok, msg)
if ok, tag = 'PASS'; else, tag = 'FAIL'; end
fprintf('%s  %s\n', tag, msg);
end
