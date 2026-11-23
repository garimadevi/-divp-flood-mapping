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