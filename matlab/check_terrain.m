%% check_terrain.m - independent cross-check of the canonical static layers
% Contributed by Pritom (originally appended to step1, then merged into step2).
% It re-derives slope, JRC permanent water and WorldCover classes straight from
% the raw 30 m rasters onto the 10 m S1 grid, and compares them with the layers
% Python already built (data/processed/slope_deg.tif and masks/*.tif).
%
% Why this exists: the MATLAB layer is a tool-independence proof. If two
% independent resamplings of the same DEM agree, the static layers are not an
% artefact of one library's reprojection.
%
% It is a CHECK, not a pipeline stage: it writes only to matlab/out and never
% touches data/processed (which is Python-owned).
if ~exist('P','var'), setup_paths; end

%% Section A - reference grid and canonical layers
f = fullfile(P.processed,'s1_post_vv_db.tif');
[I, R] = readgeoraster(f,'OutputType','double');
I(I == -9999) = NaN;                       % nodata before ANY statistic
valid = ~isnan(I);
[nr, nc] = size(I);

canon_slope = readgeoraster(fullfile(P.processed,'slope_deg.tif'),'OutputType','double');
canon_slope(canon_slope == -9999) = NaN;
canon_perm   = readgeoraster(fullfile(P.processed,'masks','permanent_water.tif')) > 0;
canon_urban  = readgeoraster(fullfile(P.processed,'masks','urban.tif'))            > 0;
canon_veg    = readgeoraster(fullfile(P.processed,'masks','vegetation.tif'))       > 0;

%% Section B - lat/lon of every S1 pixel (used to sample the 30 m rasters)
[col, row] = meshgrid(1:nc, 1:nr);
if isa(R,'map.rasterref.GeographicCellsReference')
    [lat, lon] = intrinsicToGeographic(R, col, row);
else                                        % projected grid (UTM 32646)
    [xw, yw] = intrinsicToWorld(R, col, row);
    [lat, lon] = projinv(R.ProjectedCRS, xw, yw);
end
clear col row xw yw

SLOPE_MAX = 10;                             % config: masks.slope_deg_max
JRC_MIN   = 50;                             % config: masks.permanent_water.occurrence_threshold

%% Section C - DEM -> slope, independently
[Z, Rz] = readgeoraster(fullfile(P.raw,'dem','dem_aoi.tif'),'OutputType','double');
Z(Z < -1000) = NaN;

% TRAP: pixel size must be in METRES; a lat/lon DEM is in degrees
if isa(Rz,'map.rasterref.GeographicCellsReference')
    lat0 = mean(lat(:),'omitnan');
    dy = deg2rad(Rz.CellExtentInLatitude)  * 6371000;
    dx = deg2rad(Rz.CellExtentInLongitude) * 6371000 * cosd(lat0);
else
    dx = Rz.CellExtentInWorldX;
    dy = Rz.CellExtentInWorldY;
end
[gx, gy] = gradient(Z, dx, dy);             % rise per metre
S = atand(sqrt(gx.^2 + gy.^2));             % degrees, on the 30 m DEM grid
slope = sample_on_grid(S, Rz, lat, lon, 'linear');
clear Z gx gy S

%% Section D - JRC occurrence and WorldCover, independently
[occ, Rj] = readgeoraster(fullfile(P.raw,'reference','jrc_occurrence_aoi.tif'),'OutputType','double');
occ(occ == 255) = NaN;
occ = sample_on_grid(occ, Rj, lat, lon, 'nearest');
perm_water = occ >= JRC_MIN;                % NaN -> false

[wc, Rw] = readgeoraster(fullfile(P.raw,'landcover','worldcover_aoi.tif'),'OutputType','double');
wc(wc == 0) = NaN;
wc = sample_on_grid(wc, Rw, lat, lon, 'nearest');   % TRAP: classes -> nearest

urban = (wc == 50);
veg   = ismember(wc, [10 20 30 40]);        % tree, shrub, grass, cropland
clear lat lon

% TRAP: Python's slope_ok = slope <= 10 drops NaN; `slope > 10` would keep them.
slope_ok = slope <= SLOPE_MAX;
steep    = valid & ~slope_ok;
domain   = valid & ~perm_water & slope_ok;

%% Section E - agreement with the canonical Python layers
d_slope = slope - canon_slope;
both    = isfinite(d_slope);
ad      = abs(d_slope(both));

fprintf('\nslope vs data/processed/slope_deg.tif (%d px compared)\n', nnz(both));
fprintf('  median |diff| : %.3f deg   P95 %.3f   P99 %.3f   max %.3f\n', ...
        median(ad), prctile(ad,95), prctile(ad,99), max(ad));
fprintf('  correlation   : %.4f\n', corr(slope(both), canon_slope(both)));
fprintf('  slope_ok disagreement : %.2f %% of valid\n', ...
        100*nnz(valid & (slope_ok ~= (canon_slope <= SLOPE_MAX)))/nnz(valid));

fprintf('\nstatic masks vs data/processed/masks/*.tif (%% of valid px that differ)\n');
fprintf('  permanent water : %6.2f %%   (this %6.2f %% | canonical %6.2f %%)\n', ...
        100*nnz(valid & (perm_water ~= canon_perm))/nnz(valid), ...
        100*nnz(perm_water & valid)/nnz(valid), 100*nnz(canon_perm & valid)/nnz(valid));
fprintf('  urban           : %6.2f %%   (this %6.2f %% | canonical %6.2f %%)\n', ...
        100*nnz(valid & (urban ~= canon_urban))/nnz(valid), ...
        100*nnz(urban & valid)/nnz(valid), 100*nnz(canon_urban & valid)/nnz(valid));
fprintf('  vegetation      : %6.2f %%   (this %6.2f %% | canonical %6.2f %%)\n', ...
        100*nnz(valid & (veg ~= canon_veg))/nnz(valid), ...
        100*nnz(veg & valid)/nnz(valid), 100*nnz(canon_veg & valid)/nnz(valid));
fprintf('  analysis domain : %7.3f km2 (this) vs %7.3f km2 (canonical)\n', ...
        nnz(domain)*1e-4, nnz(valid & ~canon_perm & (canon_slope <= SLOPE_MAX))*1e-4);

%% Section F - write the check table (matlab/out only)
fid = fopen(fullfile(P.out,'terrain_check.csv'),'w');
fprintf(fid,'quantity,this_script,canonical_python,diff\n');
fprintf(fid,'slope_median_abs_diff_deg,%.4f,0,%.4f\n', median(ad), median(ad));
fprintf(fid,'slope_p99_abs_diff_deg,%.4f,0,%.4f\n', prctile(ad,99), prctile(ad,99));
fprintf(fid,'slope_correlation,%.4f,1,%.4f\n', corr(slope(both), canon_slope(both)), ...
        corr(slope(both), canon_slope(both)) - 1);
fprintf(fid,'permanent_water_km2,%.3f,%.3f,%.3f\n', nnz(perm_water & valid)*1e-4, ...
        nnz(canon_perm & valid)*1e-4, ...
        (nnz(perm_water & valid) - nnz(canon_perm & valid))*1e-4);
fprintf(fid,'urban_km2,%.3f,%.3f,%.3f\n', nnz(urban & valid)*1e-4, ...
        nnz(canon_urban & valid)*1e-4, ...
        (nnz(urban & valid) - nnz(canon_urban & valid))*1e-4);
fprintf(fid,'vegetation_km2,%.3f,%.3f,%.3f\n', nnz(veg & valid)*1e-4, ...
        nnz(canon_veg & valid)*1e-4, ...
        (nnz(veg & valid) - nnz(canon_veg & valid))*1e-4);
fprintf(fid,'analysis_domain_km2,%.3f,%.3f,%.3f\n', nnz(domain)*1e-4, ...
        nnz(valid & ~canon_perm & (canon_slope <= SLOPE_MAX))*1e-4, ...
        (nnz(domain) - nnz(valid & ~canon_perm & (canon_slope <= SLOPE_MAX)))*1e-4);
fclose(fid);

%% Section G - the figure (2x2, downsampled so it does not freeze MATLAB)
ds = max(1, floor(max(nr,nc)/1200));
ri = 1:ds:nr;  ci = 1:ds:nc;

asp  = numel(ci) / max(numel(ri),1);
figw = 1150;
figh = round(figw / asp) + 90;
figure('Color','w','Position',[80 80 figw figh]);
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');

nexttile; imagesc(slope(ri,ci)); axis image off; colorbar; clim([0 30]);
title('Slope from raw DEM (deg)');
nexttile; imagesc(perm_water(ri,ci)); axis image off; clim([0 1]);
colormap(gca, gray(2)); title(sprintf('JRC occurrence >= %d %%', JRC_MIN));
nexttile; imagesc(urban(ri,ci) + 2*veg(ri,ci)); axis image off; clim([0 2]);
colormap(gca, parula(3)); title('WorldCover: 1 urban, 2 vegetation');
nexttile; imagesc(domain(ri,ci)); axis image off; clim([0 1]);
colormap(gca, gray(2)); title(sprintf('Analysis domain (white = used) %.1f km^2', nnz(domain)*1e-4));

sgtitle('Independent re-derivation of the static layers (cross-check only, nothing written to data/processed)', ...
        'FontSize',11);
saveas(gcf, fullfile(P.out,'terrain_check.png'));

%% Section H - self-check
% The gate is about coverage and plausibility, not bit-equality: a different
% resampling SHOULD differ slightly. What would be wrong is a systematic gap.
fprintf('\n--- check_terrain verification ---\n');
report(isequal(size(slope), [nr nc]), 'derived layers are on the S1 grid');
report(all(isfinite([min(ad) median(ad) prctile(ad,99)])), 'slope comparison is finite');
report(median(ad) < 2, sprintf('median slope difference %.2f deg (resampling tolerance 2 deg)', median(ad)));
report(nnz(valid & (perm_water ~= canon_perm))/nnz(valid) < 0.02, ...
       'permanent water agrees with the canonical mask to better than 2 %');
report(nnz(valid & (veg ~= canon_veg))/nnz(valid) < 0.05, ...
       'vegetation agrees with the canonical mask to better than 5 %');
report(abs(nnz(domain) - nnz(valid & ~canon_perm & (canon_slope <= SLOPE_MAX)))/nnz(domain) < 0.02, ...
       'analysis domain agrees with the canonical domain to better than 2 %');
report(nnz(perm_water) > 0, 'JRC finds permanent water - the Brahmaputra is in the scene');

fprintf('Wrote %s\n', fullfile(P.out,'terrain_check.csv'));
fprintf('Wrote %s\n', fullfile(P.out,'terrain_check.png'));

%% ============================ local functions ============================

function B = sample_on_grid(A, RA, lat, lon, method)
% Sample raster A (referenced by RA) at the S1 pixel lat/lon.
% Works for lat/lon rasters and projected (UTM) rasters. NaN outside A.
if isa(RA,'map.rasterref.GeographicCellsReference')
    [xi, yi] = geographicToIntrinsic(RA, lat, lon);
else
    [xq, yq] = projfwd(RA.ProjectedCRS, lat, lon);
    [xi, yi] = worldToIntrinsic(RA, xq, yq);
end
B = interp2(A, xi, yi, method);
end

function report(ok, msg)
if ok, tag = 'PASS'; else, tag = 'FAIL'; end
fprintf('%s  %s\n', tag, msg);
end
