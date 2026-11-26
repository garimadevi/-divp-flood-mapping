%% step4_confidence.m - confidence classes from the vote count k
% k = number of methods that call a pixel flooded (cleaned masks from step3_masks).
%   4/4 High | 3/4 Medium | 2/4 Low | 0-1/4 Dry        binary flood map: k >= 2
% Mirrors the ADR-23 ensemble in code/confidence/agreement.py
%
% Contract:
%   in  : matlab/out/masks.mat (step3_masks.m), data/processed/s1_post_vv_db.tif (grid only)
%   out : matlab/out/confidence_class.tif, votes_k.tif, flood_k2.tif,
%         confidence_areas.csv, confidence.mat,
%         confidence_map.png, confidence_summary.png
%
% Writes ONLY to matlab/out. data/processed is Python-owned and read-only here.
if ~exist('P','var'), setup_paths; end

%% Section A - inputs and the ensemble definition
f_grid = fullfile(P.processed,'s1_post_vv_db.tif');
need = {fullfile(P.out,'masks.mat'), f_grid};
for q = 1:numel(need)
    if ~isfile(need{q}), error('Missing input file: %s (run step3_masks first)', need{q}); end
end

S      = load(need{1}, 'masks', 'domain', 'names');
masks  = S.masks;
domain = S.domain;                      % the analysis domain (no permanent water, slope <= 10)
[nr, nc] = size(domain);

[~, R] = readgeoraster(f_grid);         % only the georeference is needed
tags   = geotiffinfo(f_grid).GeoTIFFTags.GeoKeyDirectoryTag;

MEMBERS = {'otsu_vv','otsu_vh','change_vv','gmm'};    % ADR-23 members, GMM as the 4th
K_FLOOD = 2;                                          % binary flood map: k >= 2
PIX_KM2 = 1e-4;                                       % 10 m pixel = 0.0001 km2
N = numel(MEMBERS);

missing = setdiff(MEMBERS, S.names);
if ~isempty(missing), error('Member(s) not in masks.mat: %s', strjoin(missing, ', ')); end
fprintf('ensemble : %s  (N = %d)\n', strjoin(MEMBERS, ', '), N);
fprintf('domain   : %d px (%.3f km2)\n', nnz(domain), nnz(domain)*PIX_KM2);

%% Section B - the vote count k
k = zeros(nr, nc, 'uint8');
for m = 1:N
    k = k + uint8(masks.(MEMBERS{m}) & domain);       % one vote per method
end

%% Section C - confidence classes
% 0 not analysed | 1 Dry | 2 Low | 3 Medium | 4 High
% TRAP 1: pixels outside the domain are NOT "Dry" - nobody looked at them
cls = conf_class(k, N);
cls(~domain) = 0;

cn = {'not analysed','Dry','Low','Medium','High'};
fprintf('\nrule (N = %d methods):\n', N);
for kk = 0:N
    fprintf('  k = %d / %d  ->  %s\n', kk, N, cn{double(conf_class(uint8(kk), N)) + 1});
end

%% Section D - the binary flood map
flood = (k >= K_FLOOD) & domain;                      % Flood = (k >= 2)

%% Section E - how much area in each class
cnt = zeros(1, 5);
for c = 0:4, cnt(c+1) = nnz(cls == c); end
n_dom   = nnz(domain);
n_flood = nnz(flood);

fprintf('\n%-13s %10s %10s %12s %12s\n', 'class', 'pixels', 'km2', '% of domain', '% of flood');
for c = 1:4
    if c >= 2
        pf = sprintf('%12.1f', 100*cnt(c+1)/max(n_flood,1));
    else
        pf = sprintf('%12s', '-');
    end
    fprintf('%-13s %10d %10.3f %12.2f %s\n', cn{c+1}, cnt(c+1), cnt(c+1)*PIX_KM2, ...
            100*cnt(c+1)/n_dom, pf);
end
fprintf('%-13s %10d %10.3f %12.2f\n', sprintf('flood (k>=%d)', K_FLOOD), n_flood, ...
        n_flood*PIX_KM2, 100*n_flood/n_dom);

%% Section F - who disagrees? (which method is the odd one out)
med  = (cls == 3);                      % all but one agree
low  = (cls == 2);
lone = (k == 1) & domain;               % exactly one vote, so classed Dry
dis  = zeros(1, N);  inlow = zeros(1, N);  alone = zeros(1, N);
for m = 1:N
    mm = masks.(MEMBERS{m}) & domain;
    dis(m)   = 100*nnz(~mm & med)  / max(nnz(med),  1);   % the one that says dry in Medium
    inlow(m) = 100*nnz(mm  & low)  / max(nnz(low),  1);   % votes flood in Low pixels
    alone(m) = 100*nnz(mm  & lone) / max(nnz(lone), 1);   % lone vote, rejected by the rest
end
fprintf('\n%-12s %18s %18s %18s\n', 'method', 'dissents in Medium', 'votes in Low', 'lone vote (k=1)');
for m = 1:N
    fprintf('%-12s %17.1f %% %17.1f %% %17.1f %%\n', MEMBERS{m}, dis(m), inlow(m), alone(m));
end
fprintf('(columns 1 and 3 add up to 100 %%; column 2 adds up to %d x 100 %% / N)\n', K_FLOOD);

%% Section G - save the layers, the table and the .mat
wr = @(name, A) geotiffwrite(fullfile(P.out, name), A, R, 'GeoKeyDirectoryTag', tags);
wr('confidence_class.tif', cls);                      % 0..4
wr('votes_k.tif', k);                                 % 0..N
wr(sprintf('flood_k%d.tif', K_FLOOD), uint8(flood));  % binary flood map

fid = fopen(fullfile(P.out,'confidence_areas.csv'), 'w');
fprintf(fid, 'class,pixels,km2,pct_of_domain,pct_of_flood\n');
for c = 1:4
    if c >= 2, pf = 100*cnt(c+1)/max(n_flood,1); else, pf = NaN; end
    fprintf(fid, '%s,%d,%.3f,%.3f,%.3f\n', cn{c+1}, cnt(c+1), cnt(c+1)*PIX_KM2, ...
            100*cnt(c+1)/n_dom, pf);
end
fprintf(fid, 'flood_k_ge_%d,%d,%.3f,%.3f,100\n', K_FLOOD, n_flood, n_flood*PIX_KM2, ...
        100*n_flood/n_dom);
fclose(fid);
save(fullfile(P.out,'confidence.mat'), 'k', 'cls', 'flood', 'MEMBERS', 'K_FLOOD', 'cnt', '-v7.3');

%% Section H - figures
% Display is cropped to the analysis-domain bounding box, as in step3_masks.
[rw, cl] = find(domain);
r0 = max(1, min(rw)-1);  r1 = min(nr, max(rw)+1);
c0 = max(1, min(cl)-1);  c1 = min(nc, max(cl)+1);
ds = max(1, floor(max(r1-r0, c1-c0)/1100));
ri = r0:ds:r1;  ci = c0:ds:c1;

cmap = [0.35 0.35 0.35;      % not analysed
        0.94 0.94 0.94;      % Dry
        0.65 0.80 0.95;      % Low
        0.30 0.58 0.88;      % Medium
        0.05 0.20 0.55];     % High

asp = numel(ci) / max(numel(ri), 1);
figure('Color','w','Position',[80 80 1000 round(1000/asp) + 80]);
imagesc(cls(ri,ci)); axis image off; colormap(cmap); caxis([-0.5 4.5]);
cb = colorbar; cb.Ticks = 0:4; cb.TickLabels = cn;
title(sprintf('Flood confidence from vote count k (%d methods, flood = k \\geq %d)', N, K_FLOOD));
saveas(gcf, fullfile(P.out,'confidence_map.png'));

figure('Color','w','Position',[80 80 1000 400]);
subplot(1,2,1);
b = bar(cnt(3:5)*PIX_KM2, 'FaceColor', 'flat');
b.CData = cmap(3:5,:);
set(gca, 'XTickLabel', cn(3:5)); ylabel('area (km^2)'); grid on
for q = 1:3
    text(q, cnt(q+2)*PIX_KM2, sprintf('%.1f', cnt(q+2)*PIX_KM2), ...
         'HorizontalAlignment','center', 'VerticalAlignment','bottom');
end
title(sprintf('Flooded area by confidence (%.1f km^2 in total)', n_flood*PIX_KM2));
subplot(1,2,2);
bar([dis; alone]');
set(gca, 'XTick', 1:N, 'XTickLabel', strrep(MEMBERS,'_',' ')); ylabel('% of pixels'); grid on
legend('dissents in Medium', 'lone vote (k = 1)', 'Location', 'northwest');
title('Which method is the odd one out?');
saveas(gcf, fullfile(P.out,'confidence_summary.png'));

%% Section I - self-check
fprintf('\n--- step4 verification ---\n');
report(isequal(conf_class(uint8(0:4), 4), uint8([1 1 2 3 4])), ...
       'rule: 4/4 High, 3/4 Medium, 2/4 Low, 0-1/4 Dry');
report(isequal(size(k), [nr nc]) && max(k(:)) <= N, ...
       sprintf('k is on the S1 grid and lies in 0..%d', N));
report(cnt(1) == nnz(~domain) && sum(cnt(2:5)) == n_dom, ...
       'classes partition the scene: not analysed + Dry + Low + Medium + High');
report(nnz(flood & ~domain) == 0, 'no flood pixel outside the analysis domain');
report(nnz(flood) == sum(cnt(3:5)), 'binary flood map = Low + Medium + High');

sub_ok = true;
for m = 1:N
    sub_ok = sub_ok && (nnz(cls == 4 & ~masks.(MEMBERS{m})) == 0);
end
report(sub_ok, 'every High pixel is flooded in every single method');

f_ea = fullfile(P.tables, 'ensemble_area.csv');
if isfile(f_ea) && N == 4 && K_FLOOD == 2 && ismember('gmm', MEMBERS)
    EA = readtable(f_ea, 'TextType', 'string');
    py = EA.k_ge2_km2(strcmp(EA.ensemble, 'gmm_4th'));
    if ~isempty(py)
        report(abs(n_flood*PIX_KM2 - py)/py < 0.01, ...
               sprintf('flood (k>=2) %.2f km2 within 1 %% of Python gmm_4th %.2f km2', ...
                       n_flood*PIX_KM2, py));
    end
end

fprintf('\n--- take-away ---\n');
fprintf('Of %.2f km2 flagged as flood: %.1f %% High, %.1f %% Medium, %.1f %% Low.\n', ...
        n_flood*PIX_KM2, 100*cnt(5)/max(n_flood,1), 100*cnt(4)/max(n_flood,1), ...
        100*cnt(3)/max(n_flood,1));
[~, odd] = max(dis);
fprintf('Most frequent dissenter in Medium pixels: %s (%.1f %%).\n', MEMBERS{odd}, dis(odd));
fprintf('Agreement is not accuracy: check each class against the Sentinel-2 reference.\n');

fprintf('Wrote confidence_class.tif, votes_k.tif, flood_k%d.tif, confidence_areas.csv in %s\n', ...
        K_FLOOD, P.out);

%% ============================ local functions ============================

function cls = conf_class(k, N)
% Vote count -> class. 1 Dry | 2 Low | 3 Medium | 4 High  (0 is set by the caller)
cls = ones(size(k), 'uint8');                 % k <= 1  -> Dry
cls(k >= 2)            = 2;                   % at least two agree -> Low ...
cls(k == N-1 & k >= 2) = 3;                   % ... all except one -> Medium
cls(k == N   & k >= 2) = 4;                   % ... all agree      -> High
end

function report(ok, msg)
if ok, tag = 'PASS'; else, tag = 'FAIL'; end
fprintf('%s  %s\n', tag, msg);
end