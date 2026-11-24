%% Section A — read the analysis-ready layer
if ~exist('P','var'), setup_paths; end

f = fullfile(P.processed,'s1_post_vv_db.tif');
[I, R] = readgeoraster(f,'OutputType','double');
I(I == -9999) = NaN;          % TRAP 1: nodata before ANY statistic
valid = ~isnan(I);
x = I(valid);

fprintf('size        : %d x %d\n', size(I,1), size(I,2));
fprintf('valid       : %.2f %%\n', 100*mean(valid(:)));
fprintf('min/med/max : %.3f / %.3f / %.3f dB\n', min(x), median(x), max(x));

%% Section B — the histogram you can see
figure('Color','w');
histogram(x, 200, 'FaceColor',[.30 .30 .35], 'EdgeColor','none');
xlabel('VV backscatter (dB)'); ylabel('pixel count');
title('Post-event VV (dB), Lee 7\times7');   % short: avoids the x10^5 offset label
grid on
saveas(gcf, fullfile(P.out,'hist_post_vv.png'));

%% Section C — Otsu, the course way
lo = min(x); hi = max(x);
t_norm = graythresh((x - lo)/(hi - lo));        % TRAP 2: needs [0,1]
t = lo + t_norm*(hi - lo);
fprintf('Otsu VV = %.4f dB   (Python: -12.5534)\n', t);

%% Section D — prove your Lee filter (linear power, then dB)
[Lraw, ~] = readgeoraster(fullfile(P.raw,'sentinel1','s1_rtc_post_vv.tif'), ...
                          'OutputType','double');
Lraw(Lraw == -32768) = NaN;
vraw = ~isnan(Lraw);
L = Lraw; L(~vraw) = 0;                          % fill, as build_stack.py does

w = 7; looks = 4; kern = ones(w)/w^2;
cnt = imfilter(double(vraw), kern, 'symmetric');   % 'symmetric' == scipy 'reflect'
mu  = imfilter(L,    kern, 'symmetric') ./ max(cnt,1e-6);
mu2 = imfilter(L.^2, kern, 'symmetric') ./ max(cnt,1e-6);
vr  = max(mu2 - mu.^2, 0);
wgt = vr ./ (vr + mu.^2/looks + 1e-6);            % Lee weight, Cu = 1/L
Lf  = mu + wgt.*(L - mu);

Idb  = nan(size(Lf));
good = vraw & (Lf > 0);
Idb(good) = 10*log10(Lf(good));

d = abs(Idb - I); d = d(isfinite(d));
fprintf('Lee rebuild vs processed file: max %.6f dB | P99 %.6f dB\n', max(d), prctile(d,99));

%% Section E — what the filter actually did (the demo figure)
r0 = 1200; c0 = 1500; n = 300;            % 300 px = 3.00 km at 10 m
figure('Color','w','Position',[80 80 940 520]);

subplot(1,2,1)
imagesc(Idb(r0:r0+n-1, c0:c0+n-1)); axis image off
colormap(gray); caxis([-22 -2]); title('Lee 7\times7, 4 looks');
set(gca,'Position',[0.05 0.06 0.42 0.80]);      % square box -> no white margins
hold on
text(15, 180, 'Brahmaputra channel (water)', 'Color','w', 'FontSize',10, 'FontWeight','bold');
text(15,  30, 'vegetated bank',              'Color','k', 'FontSize',10, 'FontWeight','bold');
plot([15 115], [288 288], 'k-', 'LineWidth', 3); % 100 px = 1 km scale bar
text(15, 272, '1 km', 'Color','k', 'FontSize',10, 'FontWeight','bold');
hold off

subplot(1,2,2)
imagesc(10*log10(Lraw(r0:r0+n-1, c0:c0+n-1))); axis image off
colormap(gray); caxis([-22 -2]); title('raw \rightarrow dB (speckle)');
set(gca,'Position',[0.53 0.06 0.42 0.80]);
hold on
plot([15 115], [288 288], 'k-', 'LineWidth', 3);
text(15, 272, '1 km', 'Color','k', 'FontSize',10, 'FontWeight','bold');
hold off

sgtitle(['Same 90,000 pixels (3\times3 km), 23 Jun 2023, ', ...
         'lon 91.70-91.73 E - only the filter differs'], 'FontSize',12);
saveas(gcf, fullfile(P.out,'lee_before_after.png'));

%% Section F — self-check (the two numbers a viva will ask for)
fprintf('\n--- step1 verification ---\n');
if abs(t - (-12.5534)) < 0.25
    fprintf('PASS  Otsu VV %.4f dB is within one 256-bin histogram bin of Python -12.5534\n', t);
else
    fprintf('FAIL  Otsu VV %.4f dB is further than one bin from Python -12.5534\n', t);
end
if max(d) < 1e-3
    fprintf('PASS  Lee filter matches build_stack.py (max |diff| %.6f dB)\n', max(d));
else
    fprintf('FAIL  Lee filter diverges from build_stack.py (max |diff| %.6f dB)\n', max(d));
end

%% Implementing the terrain and landcover masks for flood analysis
%% Section A — reference grid: every mask is built on the S1 pixel grid
if ~exist('P','var'), setup_paths; end

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
    [x, y] = intrinsicToWorld(R, col, row);
    [lat, lon] = projinv(R.ProjectedCRS, x, y);
end

% the three rules of this step
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

% move the slope onto the S1 grid
slope = geointerp(slope, Rz, lat, lon, 'linear');
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

%% Section F — the figure
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

%% Section G — self-check
fprintf('\n--- step2 verification ---\n');
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

% same Otsu as Step 1: how many "water-looking" pixels do the masks remove?
x = I(valid); lo = min(x); hi = max(x);
t = lo + graythresh((x - lo)/(hi - lo))*(hi - lo);
dark = valid & (I < t);
fprintf('dark pixels (VV < %.2f dB): %d\n', t, nnz(dark));
fprintf('  removed as permanent water : %5.1f %%\n', 100*nnz(dark & perm_water)/nnz(dark));
fprintf('  removed as steep terrain   : %5.1f %%\n', 100*nnz(dark & steep & ~perm_water)/nnz(dark));
fprintf('  left as flood candidates   : %5.1f %%\n', 100*nnz(dark & analysis)/nnz(dark));