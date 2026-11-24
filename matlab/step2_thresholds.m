%% step2_masks_and_thresholds.m — terrain / land-cover masks, then the five thresholds
% PART 1  masks  : DEM slope, JRC permanent water, ESA WorldCover (urban, vegetation)
% PART 2  thresholds : Otsu VV, Otsu VH, change, Kittler, GMM (ADR-23 ensemble)
% Outputs: processed/mask_analysis.tif, processed/masks.mat,
%          out/masks_overview.png, out/thresholds.csv
if ~exist('P','var'), setup_paths; end

%% ====================== PART 1 — TERRAIN & LAND-COVER MASKS ======================

%% Section A — reference grid: every mask is built on the S1 pixel grid
f = fullfile(P.processed,'s1_post_vv_db.tif');
[I, R] = readgeoraster(f,'OutputType','double');
I(I == -9999) = NaN;          % TRAP 1: nodata before ANY statistic
valid = ~isnan(I);
[nr, nc] = size(I);

% latitude / longitude of every S1 pixel (used to sample the other layers)
[col, row] = meshgrid(1:nc, 1:nr);
if isa(R,'map.rasterref.GeographicCellsReference')
    [lat, lon] = intrinsicToGeographic(R, col, row);
else                                             % projected grid (UTM)
    [xw, yw] = intrinsicToWorld(R, col, row);
    [lat, lon] = projinv(R.ProjectedCRS, xw, yw);
end
clear col row xw yw

% the two exclusion rules
SLOPE_MAX = 10;               % degrees, steeper = excluded
JRC_MIN   = 90;               % % occurrence, at or above = permanent water
fprintf('S1 grid : %d x %d | valid %.2f %%\n', nr, nc, 100*mean(valid(:)));

%% Section B — DEM -> slope
[Z, Rz] = readgeoraster(fullfile(P.raw,'dem','dem.tif'),'OutputType','double');
Z(Z < -1000) = NaN;                              % DEM nodata

% TRAP 2: the DEM pixel size is in DEGREES, slope needs METRES
lat0 = mean(lat(:));
dy = deg2rad(Rz.CellExtentInLatitude)  * 6371000;
dx = deg2rad(Rz.CellExtentInLongitude) * 6371000 * cosd(lat0);

[gx, gy] = gradient(Z, dx, dy);                  % rise per metre
slope = atand(sqrt(gx.^2 + gy.^2));              % degrees

slope = geointerp(slope, Rz, lat, lon, 'linear');   % move onto the S1 grid
steep = slope > SLOPE_MAX;                       % NaN -> false (kept)

%% Section C — JRC permanent water
[occ, Rj] = readgeoraster(fullfile(P.raw,'jrc','gsw_occurrence.tif'),'OutputType','double');
occ(occ == 255) = NaN;                           % JRC nodata
occ = geointerp(occ, Rj, lat, lon, 'nearest');
perm_water = occ >= JRC_MIN;                     % NaN -> false

%% Section D — ESA WorldCover: urban and vegetation
[wc, Rw] = readgeoraster(fullfile(P.raw,'worldcover','worldcover.tif'),'OutputType','double');
wc = geointerp(wc, Rw, lat, lon, 'nearest');     % TRAP 3: classes -> nearest, never linear

urban = (wc == 50);                              % built-up
veg   = ismember(wc, [10 20 30]);                % tree, shrub, grass

%% Section E — combine: what the flood analysis may use
exclude  = perm_water | steep;
analysis = valid & ~exclude;                     % 1 = pixel enters flood analysis

p = @(m) 100*nnz(m & valid)/nnz(valid);
fprintf('permanent water : %5.2f %%\n', p(perm_water));
fprintf('slope > %d deg  : %5.2f %%\n', SLOPE_MAX, p(steep));
fprintf('analysis domain : %5.2f %%\n', p(analysis));
fprintf('urban %.2f %% | vegetation %.2f %%\n', p(urban), p(veg));

geotiffwrite(fullfile(P.processed,'mask_analysis.tif'), uint8(analysis), R, ...
    'GeoKeyDirectoryTag', geotiffinfo(f).GeoTIFFTags.GeoKeyDirectoryTag);
save(fullfile(P.processed,'masks.mat'), 'perm_water','steep','urban','veg','analysis','slope');

%% Section F — the masks figure
figure('Color','w','Position',[80 80 940 760]);
subplot(2,2,1); imagesc(slope);      axis image off; colorbar; caxis([0 30]);
title('Slope (deg)');
subplot(2,2,2); imagesc(perm_water); axis image off; colormap(gca, gray(2));
title('JRC permanent water');
subplot(2,2,3); imagesc(urban + 2*veg); axis image off; colormap(gca, parula(3));
title('WorldCover: 1 urban, 2 vegetation');
subplot(2,2,4); imagesc(analysis);   axis image off; colormap(gca, gray(2));
title('Analysis domain (white = used)');
saveas(gcf, fullfile(P.out,'masks_overview.png'));

%% Section G — masks self-check
fprintf('\n--- step2 masks verification ---\n');
if isequal(size(slope), size(I)) && isequal(size(perm_water), size(I)) && isequal(size(wc), size(I))
    fprintf('PASS  all layers have the S1 grid size\n');
else
    fprintf('FAIL  a layer does not match the S1 grid size\n');
end
s = slope(isfinite(slope));
if all(s >= 0 & s <= 90)
    fprintf('PASS  slope is within 0-90 deg (max %.1f)\n', max(s));
else
    fprintf('FAIL  slope has values outside 0-90 deg\n');
end

%% ========================= PART 2 — THE FIVE THRESHOLDS =========================
% Mirrors code/confidence/alternative_members.py (kittler_threshold, gmm_threshold).

%% Section H — load both polarizations once
% false = all valid pixels (matches the Python tables); true = analysis domain only
USE_MASK_FOR_THRESHOLDS = false;

inside = true(size(I));
if USE_MASK_FOR_THRESHOLDS, inside = analysis; end

VV = I;                                          % already loaded in Section A
x = VV(~isnan(VV) & inside);                     % -> Otsu VV, Kittler, GMM

[VH,~] = readgeoraster(fullfile(P.processed,'s1_post_vh_db.tif'),'OutputType','double');
VH(VH == -9999) = NaN;
y = VH(~isnan(VH) & inside);                     % -> Otsu VH

fprintf('\nVV used %d px | VH used %d px\n', numel(x), numel(y));

%% Section I — the five thresholds
t_vv      = otsu_db(x);
t_vh      = otsu_db(y);
t_change  = -3.0;                   % fixed in code/config/config.yaml
t_kittler = kittler_threshold(x, 256);
t_gmm     = gmm_threshold(x(1:8:end), 40, 20001);   % 1-in-8 subsample, as Python

fprintf('Otsu VV = %8.4f dB   (Python -12.5534)\n', t_vv);
fprintf('Otsu VH = %8.4f dB   (Python -17.3090)\n', t_vh);
fprintf('Kittler = %8.4f dB   (Python -14.0180)\n', t_kittler);
fprintf('GMM     = %8.4f dB   (Python -10.2654)\n', t_gmm);

%% Section J — write thresholds.csv and self-check against the Python tables
M = readtable(fullfile(P.tables,'mask_stats.csv'),'TextType','string');
C = readtable(fullfile(P.tables,'candidate_members.csv'),'TextType','string');
expv = @(tbl,name) tbl.threshold(strcmp(tbl.method,name));

vals = struct('otsu_vv',t_vv,'otsu_vh',t_vh,'change_vv',t_change, ...
              'kittler',t_kittler,'gmm',t_gmm);
ref  = struct('otsu_vv',expv(M,'otsu_vv'),'otsu_vh',expv(M,'otsu_vh'), ...
              'change_vv',-3.0,'kittler',expv(C,'kittler'),'gmm',expv(C,'gmm'));

names = {'otsu_vv','otsu_vh','change_vv','kittler','gmm'};   % report order
fid = fopen(fullfile(P.out,'thresholds.csv'),'w');
fprintf(fid,'method,threshold\n');
fprintf('\n--- step2 thresholds verification ---\n');
for k = 1:numel(names)
    n = names{k};  v = vals.(n);  e = ref.(n);
    fprintf(fid,'%s,%.4f\n', n, v);
    if abs(v-e) < 0.25
        status = 'PASS';
    else
        status = 'FAIL';
    end
    fprintf('%-10s MATLAB %8.4f | Python %8.4f | d=%+7.4f  %s\n', n, v, e, v-e, status);
end
fclose(fid);
fprintf('Wrote %s\n', fullfile(P.out,'thresholds.csv'));

%% Section K — what the masks remove from the "water-looking" pixels
dark = valid & (VV < t_vv);                      % darker than the Otsu VV threshold
fprintf('\ndark pixels (VV < %.2f dB): %d\n', t_vv, nnz(dark));
fprintf('  removed as permanent water : %5.1f %%\n', 100*nnz(dark & perm_water)/nnz(dark));
fprintf('  removed as steep terrain   : %5.1f %%\n', 100*nnz(dark & steep & ~perm_water)/nnz(dark));
fprintf('  left as flood candidates   : %5.1f %%\n', 100*nnz(dark & analysis)/nnz(dark));

%% ============================ local functions ============================

function t = otsu_db(v)
% Otsu threshold in dB. graythresh needs [0,1], so rescale in and back out.
v  = v(isfinite(v));
lo = min(v); hi = max(v);
if hi <= lo, t = lo; return; end
t = lo + graythresh((v-lo)/(hi-lo))*(hi-lo);
end

function t = kittler_threshold(v, bins)
% Kittler-Illingworth minimum-error threshold: fit two Gaussians, minimise J.
v = v(:); v = v(isfinite(v));
lo = min(v); hi = max(v);
if hi <= lo, t = lo; return; end

edges = linspace(lo, hi, bins+1);
h = histcounts(v, edges);
miss = numel(v) - sum(h);
if miss > 0, h(end) = h(end) + miss; end     % numpy includes the max in the last bin
c = (edges(1:end-1) + edges(2:end))/2;       % bin centres
h = h(:); c = c(:);

N = cumsum(h);  S = cumsum(h.*c);  Q = cumsum(h.*c.^2);   % prefix sums

n1 = N(1:end-1);  n2 = N(end) - n1;          % split after bin k, k = 1..bins-1
s1 = S(1:end-1);  s2 = S(end) - s1;
q1 = Q(1:end-1);  q2 = Q(end) - q1;

p1 = n1/N(end);  p2 = n2/N(end);
m1 = s1./n1;     m2 = s2./n2;
v1 = q1./n1 - m1.^2;   v2 = q2./n2 - m2.^2;
sd1 = sqrt(max(v1,0)); sd2 = sqrt(max(v2,0));

J = 1 + 2*(p1.*log(sd1) + p2.*log(sd2)) - 2*(p1.*log(p1) + p2.*log(p2));
bad = (n1==0) | (n2==0) | (v1<=0) | (v2<=0) | ~isfinite(J);
J(bad) = inf;

[~,i] = min(J);
t = c(i+1);      % TRAP: threshold is the FIRST CENTRE of the upper class
end

function t = gmm_threshold(v, n_iter, n_grid)
% 2-component 1-D Gaussian mixture by EM; threshold where the densities are equal.
v = v(:); v = v(isfinite(v));
if isempty(v), t = NaN; return; end

mu1 = prctile(v,35);  mu2 = prctile(v,65);
sd1 = std(v,1);       sd2 = sd1;          % std(...,1) = numpy ddof=0
w1  = 0.5;            w2  = 0.5;

for it = 1:n_iter
    p1 = exp(-0.5*((v-mu1)/sd1).^2)/(sd1*sqrt(2*pi));
    p2 = exp(-0.5*((v-mu2)/sd2).^2)/(sd2*sqrt(2*pi));
    r  = (w1*p1) ./ (w1*p1 + w2*p2 + 1e-300);

    n1 = sum(r);  n2 = numel(v) - n1;
    w1 = n1/numel(v);  w2 = 1 - w1;
    mu1 = sum(r.*v)/n1;       mu2 = sum((1-r).*v)/n2;
    sd1 = max(sqrt(sum(r.*(v-mu1).^2)/n1), 1e-6);
    sd2 = max(sqrt(sum((1-r).*(v-mu2).^2)/n2), 1e-6);
end

if mu1 > mu2
    [mu1,mu2] = deal(mu2,mu1);
    [sd1,sd2] = deal(sd2,sd1);
    [w1,w2]   = deal(w2,w1);
end

xs = linspace(mu1, mu2, n_grid);
l1 = log(w1) - log(sd1) - 0.5*((xs-mu1)/sd1).^2;
l2 = log(w2) - log(sd2) - 0.5*((xs-mu2)/sd2).^2;
d  = l1 - l2;

i = find(diff(sign(d)) ~= 0, 1);
if isempty(i), t = (mu1+mu2)/2; else, t = xs(i); end
end