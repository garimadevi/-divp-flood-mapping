%% step3_kappa_comparison.m — are the thresholding methods really independent?
% Cohen's kappa between methods:
%   (1) Otsu VV vs Otsu VH        same algorithm, different polarization
%   (2) Otsu vs change detection  single image vs before/after
%   (3) Adaptive vs the others    local threshold vs global thresholds
% Then: does adding methods add confidence, or just repeat one answer?
% Needs: out/thresholds.csv, processed/masks.mat   (from step 2)
% Outputs: out/kappa_matrix.png, out/kappa_pairs.png, out/kappa_redundancy.png,
%          out/kappa_disagreement_maps.png, out/kappa_summary.csv, out/kappa_matrix.csv
if ~exist('P','var'), setup_paths; end

%% Section A — inputs, parameters, common domain
ADAPT_WIN      = 151;     % adaptive window in pixels (odd) = 1.5 km at 10 m
ADAPT_SENS     = 0.5;     % adaptthresh sensitivity (higher = more flood)
ADAPT_GUARD_DB = 3;       % adaptive may only flag pixels below Otsu VV + this
PIX_M          = 10;

need = {fullfile(P.processed,'s1_post_vv_db.tif'), ...
        fullfile(P.processed,'s1_post_vh_db.tif'), ...
        fullfile(P.processed,'s1_pre_vv_db.tif'), ...     % <- edit if named differently
        fullfile(P.processed,'masks.mat'), ...
        fullfile(P.out,'thresholds.csv')};
for k = 1:numel(need)
    if ~isfile(need{k}), error('Missing input file: %s', need{k}); end
end

[VVpost,~] = readgeoraster(need{1},'OutputType','double'); VVpost(VVpost == -9999) = NaN;
[VHpost,~] = readgeoraster(need{2},'OutputType','double'); VHpost(VHpost == -9999) = NaN;
[VVpre ,~] = readgeoraster(need{3},'OutputType','double'); VVpre(VVpre   == -9999) = NaN;
S = load(need{4}, 'analysis');
T = readtable(need{5});

names = {'otsu_vv','otsu_vh','change_vv','kittler','gmm','adaptive'};
lab   = strrep(names,'_',' ');
nM = numel(names);
t = nan(1,nM);
for k = 1:5, t(k) = T.threshold(strcmp(T.method, names{k})); end   % adaptive has no single number

% TRAP 1: kappa is only comparable if every method is judged on the SAME pixels
dom = S.analysis & ~isnan(VVpost) & ~isnan(VHpost) & ~isnan(VVpre);
fprintf('pixels compared : %d (%.1f %% of the scene)\n', nnz(dom), 100*nnz(dom)/numel(dom));

%% Section B — the six flood masks
M = cell(1,nM);
M{1} = VVpost < t(1);                    % Otsu VV
M{2} = VHpost < t(2);                    % Otsu VH
M{3} = (VVpost - VVpre) < t(3);          % change detection
M{4} = VVpost < t(4);                    % Kittler
M{5} = VVpost < t(5);                    % GMM

% adaptive: a pixel is flood if it is darker than its own neighbourhood
lo = min(VVpost(dom)); hi = max(VVpost(dom));
Vf = VVpost;  Vf(isnan(Vf)) = median(VVpost(dom));       % adaptthresh cannot take NaN
W  = single(1 - (Vf - lo)/(hi - lo));                    % invert: dark water -> bright
W  = min(max(W,0),1);
Tloc = adaptthresh(W, 'NeighborhoodSize', ADAPT_WIN*[1 1], ...
                      'Sensitivity', ADAPT_SENS, 'Statistic', 'gaussian');
% TRAP 2: a local threshold also fires on dry, flat, noisy land, so it needs a global guard
M{6} = (W > Tloc) & (VVpost < t(1) + ADAPT_GUARD_DB);
clear Vf W Tloc

Fd = false(nnz(dom), nM);                % one column per method, domain pixels only
for k = 1:nM, Fd(:,k) = M{k}(dom); end
clear M
n_dom = size(Fd,1);

area_km2  = sum(Fd,1) * PIX_M^2 / 1e6;
prevalence = 100*mean(Fd,1);
fprintf('\n%-10s %10s %12s %12s\n','method','thr (dB)','flood km2','flood %');
for k = 1:nM
    fprintf('%-10s %10.3f %12.2f %12.2f\n', names{k}, t(k), area_km2(k), prevalence(k));
end

%% Section C — Cohen's kappa for every pair of methods
KAPPA = zeros(nM);  PO = zeros(nM);
for i = 1:nM
    for j = 1:nM
        [KAPPA(i,j), PO(i,j)] = cohen_kappa(Fd(:,i), Fd(:,j));
    end
end

fprintf('\nCohen''s kappa (1 = identical, 0 = no better than chance):\n');
fprintf('%-10s', ''); fprintf('%10s', names{:}); fprintf('\n');
for i = 1:nM
    fprintf('%-10s', names{i}); fprintf('%10.3f', KAPPA(i,:)); fprintf('\n');
end

%% Section D — the three comparisons
fprintf('\n=== (1) Otsu VV vs Otsu VH  (same algorithm, different data) ===\n');
k12 = KAPPA(1,2);
fprintf('kappa = %.3f (%s) | raw agreement %.1f %%\n', k12, landis(k12), 100*PO(1,2));

fprintf('\n=== (2) Otsu vs change detection  (static vs temporal) ===\n');
k13 = KAPPA(1,3);   k23 = KAPPA(2,3);
fprintf('Otsu VV vs change : kappa = %.3f (%s)\n', k13, landis(k13));
fprintf('Otsu VH vs change : kappa = %.3f (%s)\n', k23, landis(k23));

fprintf('\n=== (3) Adaptive vs the other methods ===\n');
ka = KAPPA(6,1:5);
for j = 1:5
    fprintf('adaptive vs %-10s: kappa = %.3f (%s)\n', names{j}, ka(j), landis(ka(j)));
end
fprintf('mean kappa adaptive vs others = %.3f\n', mean(ka));

%% Section E — does a bigger ensemble add confidence, or just repeat itself?
off   = KAPPA;  off(1:nM+1:end) = NaN;
kbar  = mean(off(:),'omitnan');                          % mean pairwise kappa, all 6
kbar5 = mean(reshape(KAPPA(1:5,1:5) + diag(nan(5,1)),[],1),'omitnan');   % original 5 only
N_eff = nM / (1 + (nM-1)*min(max(kbar,0),1));            % heuristic "independent votes"
fprintf('\nmean pairwise kappa: all %d = %.3f | original 5 = %.3f\n', nM, kbar, kbar5);
fprintf('effective number of independent methods ~ %.2f out of %d (heuristic)\n', N_eff, nM);

votes   = sum(Fd,2);
cons    = votes > nM/2;                                  % strict majority flood map
fprintf('consensus flood: %.2f km2 (>%d of %d votes)\n', nnz(cons)*PIX_M^2/1e6, floor(nM/2), nM);

kcons = zeros(1,nM);  kloo = zeros(1,nM);
for k = 1:nM
    kcons(k) = cohen_kappa(Fd(:,k), cons);               % method vs full consensus
    rest = setdiff(1:nM, k);
    cons_k = sum(Fd(:,rest),2) > numel(rest)/2;          % consensus WITHOUT method k
    kloo(k) = cohen_kappa(cons, cons_k);                 % ~1 -> method k changes nothing
end
fprintf('\n%-10s %18s %22s\n','method','kappa vs consensus','kappa consensus w/o it');
for k = 1:nM, fprintf('%-10s %18.3f %22.3f\n', names{k}, kcons(k), kloo(k)); end

vc = histcounts(votes, -0.5:1:nM+0.5);
fprintf('\nvotes   share of domain\n');
for v = 0:nM, fprintf('%d       %6.2f %%\n', v, 100*vc(v+1)/n_dom); end
flood_any = nnz(votes > 0);
fprintf('unanimous = %.1f %% of everything any method calls flood\n', 100*vc(nM+1)/flood_any);

%% Section F — figure 1: full kappa matrix
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

%% Section G — figure 2: the three comparisons
vals  = [k12, k13, ka];
blab  = [{'Otsu VV vs VH','Otsu VV vs change'}, strcat('adaptive vs ', lab(1:5))];
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

%% Section H — figure 3: redundancy
figure('Color','w','Position',[80 80 1000 400]);
subplot(1,2,1);
bar([kcons; kloo]'); set(gca,'XTick',1:nM,'XTickLabel',lab,'XTickLabelRotation',30);
ylim([min(0.5, min([kcons kloo])-0.05) 1.0]); ylabel('\kappa'); grid on
legend('method vs consensus','consensus without method','Location','southoutside');
title('A method with \kappa \approx 1 adds nothing');
subplot(1,2,2);
bar(0:nM, 100*vc/n_dom,'FaceColor',[.3 .3 .35]);
xlabel('number of methods saying flood'); ylabel('% of domain'); grid on
set(gca,'YScale','log'); title(sprintf('Vote counts (N_{eff} \\approx %.1f of %d)', N_eff, nM));
saveas(gcf, fullfile(P.out,'kappa_redundancy.png'));

%% Section I — figure 4: where do the paired methods disagree?
[nr, nc] = size(dom);
ds = max(1, floor(max(nr,nc)/1200));
ri = 1:ds:nr;  ci = 1:ds:nc;
others = sum(Fd(:,1:5),2) > 2.5;                         % consensus of the five others
pairs = {Fd(:,1), Fd(:,2),  'Otsu VV | Otsu VH'; ...
         Fd(:,1), Fd(:,3),  'Otsu VV | change'; ...
         Fd(:,6), others,   'adaptive | other five'};
figure('Color','w','Position',[60 60 1150 420]);
for q = 1:3
    a = pairs{q,1};  c = pairs{q,2};
    cat4 = zeros(n_dom,1);  cat4(a & c) = 1;  cat4(a & ~c) = 2;  cat4(~a & c) = 3;
    tmp = nan(nr,nc);  tmp(dom) = cat4;
    subplot(1,3,q); imagesc(tmp(ri,ci)); axis image off; caxis([0 3]);
    colormap(gca, [0.88 0.88 0.88; 0.10 0.35 0.90; 0.85 0.20 0.15; 0.95 0.65 0.10]);
    nm = strsplit(pairs{q,3},' | ');
    title(sprintf('%s   \\kappa = %.2f', pairs{q,3}, cohen_kappa(a,c)));
    xlabel(sprintf('blue: both | red: only %s | orange: only %s', nm{1}, nm{2}));
end
saveas(gcf, fullfile(P.out,'kappa_disagreement_maps.png'));

%% Section J — save tables
Tsum = table(names(:), t(:), area_km2(:), prevalence(:), kcons(:), kloo(:), ...
    'VariableNames', {'method','threshold_db','flood_km2','flood_pct', ...
                      'kappa_vs_consensus','kappa_consensus_without_method'});
writetable(Tsum, fullfile(P.out,'kappa_summary.csv'));
Kt = array2table(KAPPA, 'VariableNames', names, 'RowNames', names);
writetable(Kt, fullfile(P.out,'kappa_matrix.csv'), 'WriteRowNames', true);
fprintf('\nWrote kappa_summary.csv and kappa_matrix.csv in %s\n', P.out);

%% Section K — self-check and take-away
fprintf('\n--- step3 verification ---\n');
if all(abs(diag(KAPPA) - 1) < 1e-12) && max(abs(KAPPA(:) - reshape(KAPPA',[],1))) < 1e-12
    fprintf('PASS  kappa matrix is symmetric with 1 on the diagonal\n');
else
    fprintf('FAIL  kappa matrix is not symmetric / diagonal is not 1\n');
end
rng(1);
shuf = Fd(randperm(n_dom), 1);                           % same flood %, random place
ks = cohen_kappa(Fd(:,1), shuf);
if abs(ks) < 0.01
    fprintf('PASS  shuffled mask gives kappa %.4f (chance level is 0)\n', ks);
else
    fprintf('FAIL  shuffled mask gives kappa %.4f, expected about 0\n', ks);
end
if all(isfinite(KAPPA(:))) && all(KAPPA(:) >= -1 & KAPPA(:) <= 1)
    fprintf('PASS  all kappa values are defined and inside [-1, 1]\n');
else
    fprintf('FAIL  a kappa is NaN or outside [-1, 1] - a method flags nothing or everything\n');
end
if any(prevalence < 1)
    fprintf('WARN  a method flags < 1 %% of the domain: kappa is unstable at low prevalence\n');
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
fprintf('Most redundant method: %s (removing it leaves the consensus kappa at %.3f).\n', ...
        names{redundant}, kloo(redundant));

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
else,            s = 'almost perfect';
end
end