%% step3_masks.m - the six flood masks, cleaned exactly as Python does
% Mirrors code/flood_masks/run_masks.py and the six candidate members of
% code/confidence/agreement.py (ADR-23).
%
% Contract:
%   in  : data/processed/s1_{post_vv,post_vh,pre_vv}_db.tif, slope_deg.tif,
%         masks/permanent_water.tif, matlab/out/thresholds.csv (from step2)
%   out : matlab/out/masks.mat, matlab/out/mask_areas.csv,
%         matlab/out/masks_overview_matlab.png
%
% Writes ONLY to matlab/out. data/processed is Python-owned and read-only here.
if ~exist('P','var'), setup_paths; end

%% Section A - the analysis-ready layers (nothing is filtered again here)
need = {fullfile(P.processed,'s1_post_vv_db.tif'), ...
        fullfile(P.processed,'s1_post_vh_db.tif'), ...
        fullfile(P.processed,'s1_pre_vv_db.tif'), ...
        fullfile(P.processed,'slope_deg.tif'), ...
        fullfile(P.processed,'masks','permanent_water.tif'), ...
        fullfile(P.out,'thresholds.csv')};
for k = 1:numel(need)
    if ~isfile(need{k}), error('Missing input file: %s', need{k}); end
end

[post_vv, R] = readgeoraster(need{1},'OutputType','double');  post_vv(post_vv == -9999) = NaN;
[post_vh, ~] = readgeoraster(need{2},'OutputType','double');  post_vh(post_vh == -9999) = NaN;
[pre_vv , ~] = readgeoraster(need{3},'OutputType','double');  pre_vv(pre_vv  == -9999) = NaN;
[slope  , ~] = readgeoraster(need{4},'OutputType','double');  slope(slope    == -9999) = NaN;
 permanent     = readgeoraster(need{5});

[nr, nc] = size(post_vv);
fprintf('grid : %d x %d px (%.1f km2)\n', nr, nc, nr*nc*1e-4);

%% Section B - the domain, exactly as run_masks.py builds it
valid    = ~isnan(post_vv) & ~isnan(slope);
base     = valid & (permanent == 0);          % radar-valid, not permanent water
slope_ok = slope <= 10;                        % masks.slope_deg_max; NaN -> false
domain   = base & slope_ok;                    % the analysis domain

fprintf('valid        : %8d px (%7.3f km2)\n', nnz(valid),    nnz(valid)*1e-4);
fprintf('base         : %8d px (%7.3f km2)\n', nnz(base),     nnz(base)*1e-4);
fprintf('domain       : %8d px (%7.3f km2)   Python 7,273,545 px / 727.355 km2\n', ...
        nnz(domain), nnz(domain)*1e-4);

%% Section C - thresholds: the MATLAB handoff, plus Python's for the gate
T = readtable(fullfile(P.out,'thresholds.csv'),'TextType','string');
M = readtable(fullfile(P.tables,'mask_stats.csv'),'TextType','string');
C = readtable(fullfile(P.tables,'candidate_members.csv'),'TextType','string');
th   = @(name) T.threshold(strcmp(T.method,name));
t_py = @(tbl,name) tbl.threshold(strcmp(tbl.method,name));
km   = @(tbl,name,col) tbl.(col)(strcmp(tbl.method,name));

%% Section D - the adaptive member needs a local threshold FIELD, not a scalar
% Python: uniform_filter(filled, 51) on the valid pixels, k_std = 1.5
w    = 51;                     % masks.methods[adaptive_vv].window
kstd = 1.5;                    % masks.methods[adaptive_vv].k_std
k1   = ones(1,w)/w;

fill = post_vv;
fill(~isfinite(fill)) = median(post_vv(valid));       % NaN-free, as Python does
mu   = imfilter(imfilter(fill,      k1, 'symmetric'), k1', 'symmetric');
mu2  = imfilter(imfilter(fill.^2,   k1, 'symmetric'), k1', 'symmetric');
clear fill
lsd  = sqrt(max(mu2 - mu.^2, 0));
lt   = mu - kstd*lsd;                                 % local threshold (dB)
t_adaptive = median(lt(valid));
clear mu mu2 lsd

fprintf('adaptive threshold median = %8.4f dB   (Python -9.5686)\n', t_adaptive);

%% Section E - the six raw masks
names = {'otsu_vv','otsu_vh','change_vv','adaptive_vv','kittler','gmm'};
nM    = numel(names);

t_mat = [th('otsu_vv'), th('otsu_vh'), th('change_vv'), t_adaptive, ...
         th('kittler'), th('gmm')];
t_ref = [t_py(M,'otsu_vv'), t_py(M,'otsu_vh'), t_py(M,'change_vv'), t_adaptive, ...
         t_py(C,'kittler'), t_py(C,'gmm')];

raw = cell(1,nM);
for k = 1:nM
    raw{k} = mask_for(names{k}, post_vv, post_vh, pre_vv, lt, t_mat(k));
end

%% Section F - clean: domain first, then open, close, drop < 100 px (4-connected)
% Order matters: Python does clean(mask & base & slope_ok, 100)
MIN_PX = 100;                  % flood_masks.morphology.min_component_px
masks  = struct();
area_mat = zeros(1,nM);
py_area  = zeros(1,nM);
for k = 1:nM
    masks.(names{k}) = clean_mask(raw{k} & domain, MIN_PX);
    area_mat(k) = nnz(masks.(names{k})) * 1e-4;

    if abs(t_mat(k) - t_ref(k)) < 1e-9
        py_area(k) = area_mat(k);                       % same threshold: reuse
    else
        % diagnostic: same threshold Python used, so only the mask logic is tested
        m = clean_mask(mask_for(names{k}, post_vv, post_vh, pre_vv, lt, t_ref(k)) & domain, MIN_PX);
        py_area(k) = nnz(m) * 1e-4;
        clear m
    end
end
clear raw lt

ref_km2 = [km(M,'otsu_vv','flood_km2'), km(M,'otsu_vh','flood_km2'), ...
           km(M,'change_vv','flood_km2'), km(M,'adaptive_vv','flood_km2'), ...
           km(C,'kittler','area_km2'), km(C,'gmm','area_km2')];

%% Section G - table + gate
fprintf('\n%-12s %10s %10s %10s %8s %8s  %s\n', ...
        'method','thr_mat','km2_mat','km2_py','python','d_pct','gate');
fid = fopen(fullfile(P.out,'mask_areas.csv'),'w');
fprintf(fid,'method,threshold_db,flood_px,flood_km2,python_threshold_db,python_km2,diff_pct,status\n');

ok_all = true;
for k = 1:nM
    d_pct = 100*(py_area(k) - ref_km2(k))/ref_km2(k);
    ok    = abs(d_pct) < 0.5;                         % mask logic vs Python
    ok_all = ok_all && ok;
    fprintf(fid,'%s,%.4f,%d,%.3f,%.4f,%.3f,%+.3f,%s\n', names{k}, t_mat(k), ...
            nnz(masks.(names{k})), area_mat(k), t_ref(k), ref_km2(k), d_pct, ...
            string(ok));
    fprintf('%-12s %10.4f %10.3f %10.3f %8.3f %+8.3f  %s\n', names{k}, t_mat(k), ...
            area_mat(k), py_area(k), ref_km2(k), d_pct, string(ok));
end
fclose(fid);

%% Section H - save the masks for step4
save(fullfile(P.out,'masks.mat'), 'masks', 'base', 'slope_ok', 'domain', ...
     't_mat', 't_ref', 'names', 'area_mat', '-v7.3');

%% Section I - the overview figure (same 2x3 layout as the Python version)
% Display is cropped to the analysis-domain bounding box: the AOI corners are
% excluded terrain and would otherwise waste half of every panel.
[rw, cl] = find(domain);
r0 = max(1, min(rw)-1);  r1 = min(nr, max(rw)+1);
c0 = max(1, min(cl)-1);  c1 = min(nc, max(cl)+1);
ds = max(1, floor(max(r1-r0, c1-c0)/1100));
ri = r0:ds:r1;  ci = c0:ds:c1;

asp  = numel(ci) / max(numel(ri),1);          % data aspect (cols / rows)
figw = 1400;
figh = round(figw * 2 / (3 * asp)) + 80;      % 3 cols x 2 rows, plus title room
figure('Color','w','Position',[60 60 figw figh]);
tiledlayout(2,3,'Padding','compact','TileSpacing','compact');
for k = 1:nM
    nexttile;
    imagesc(masks.(names{k})(ri,ci)); axis image off; clim([0 1]);
    colormap(gca, [0.94 0.94 0.94; 0.09 0.32 0.72]);
    title(sprintf('%s  -  %.2f km^2  (thr %.2f dB)', names{k}, area_mat(k), t_mat(k)), ...
          'FontSize',10);
end
sgtitle(sprintf(['Six flood masks, MATLAB re-implementation - analysis domain only, ' ...
                 '1 px = 0.0001 km^2']), 'FontSize',12);
saveas(gcf, fullfile(P.out,'masks_overview_matlab.png'));

%% Section J - self-check
fprintf('\n--- step3 verification ---\n');

sizes_ok = true;
for k = 1:nM, sizes_ok = sizes_ok && isequal(size(masks.(names{k})), [nr nc]); end
report(sizes_ok, 'all six masks are on the S1 grid');

report(abs(nnz(domain)*1e-4 - 727.355) < 0.5, ...
       sprintf('analysis domain %.3f km2 matches Python 727.355 km2', nnz(domain)*1e-4));

report(abs(t_adaptive + 9.5686) < 0.25, ...
       sprintf('adaptive median threshold %.4f dB within 0.25 dB of Python -9.5686', t_adaptive));

report(ok_all, 'every mask area at Python''s threshold matches to better than 0.5 %');

nonempty = all(area_mat > 0);
report(nonempty, 'no mask is empty');

inside = all(area_mat < nnz(domain)*1e-4);
report(inside, 'no mask exceeds the analysis domain');

fprintf('Wrote %s\n', fullfile(P.out,'masks.mat'));
fprintf('Wrote %s\n', fullfile(P.out,'mask_areas.csv'));
fprintf('Wrote %s\n', fullfile(P.out,'masks_overview_matlab.png'));

%% ============================ local functions ============================

function m = mask_for(name, post_vv, post_vh, pre_vv, lt, t)
% One raw (uncleaned) flood mask. NaN comparisons are false, as in numpy.
switch name
    case 'otsu_vv',     m = post_vv < t;
    case 'otsu_vh',     m = post_vh < t;
    case 'change_vv',   m = (post_vv - pre_vv) < t;
    case 'adaptive_vv', m = post_vv < lt;      % t is ignored: the field is lt
    case 'kittler',     m = post_vv < t;
    case 'gmm',         m = post_vv < t;
    otherwise, error('Unknown method: %s', name);
end
end

function m = clean_mask(m, min_px)
% Exactly run_masks.py clean(): opening -> closing -> drop components < min_px.
% TRAP 1: bwareaopen defaults to 8-connectivity; scipy.ndimage.label uses 4.
% TRAP 2: MATLAB erosion pads with the maximum (1), so a 3-pixel frame of
%         water survives that scipy (border_value = 0) erodes away. erode0 fixes that.
se = strel('square',3);
m  = erode0(m, se);          % opening
m  = imdilate(m, se);
m  = imdilate(m, se);        % closing
m  = erode0(m, se);
m  = bwareaopen(m, min_px, 4);
end

function m = erode0(m, se)
% Binary erosion with scipy's border_value = 0, on a zero-padded canvas.
pr = (size(se.Neighborhood,1)-1)/2;
pc = (size(se.Neighborhood,2)-1)/2;
[nr, nc] = size(m);
mp = false(nr+2*pr, nc+2*pc);
mp(pr+1:pr+nr, pc+1:pc+nc) = m;
mp = imerode(mp, se);
m  = mp(pr+1:pr+nr, pc+1:pc+nc);
end

function report(ok, msg)
if ok, tag = 'PASS'; else, tag = 'FAIL'; end
fprintf('%s  %s\n', tag, msg);
end
