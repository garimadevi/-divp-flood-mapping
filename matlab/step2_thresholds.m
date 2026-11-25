%% step2_thresholds.m - the five scalar thresholds (ADR-23 ensemble)
% Mirrors code/confidence/alternative_members.py (kittler_threshold, gmm_threshold).
% Output: matlab/out/thresholds.csv
if ~exist('P','var'), setup_paths; end

%% ---- load both polarizations once ----
[VV,~] = readgeoraster(fullfile(P.processed,'s1_post_vv_db.tif'),'OutputType','double');
VV(VV == -9999) = NaN;
x = VV(~isnan(VV));                 % VV valid pixels -> Otsu VV, Kittler, GMM

[VH,~] = readgeoraster(fullfile(P.processed,'s1_post_vh_db.tif'),'OutputType','double');
VH(VH == -9999) = NaN;
y = VH(~isnan(VH));                 % VH valid pixels -> Otsu VH

fprintf('VV valid %d px | VH valid %d px\n', numel(x), numel(y));

%% ---- the five thresholds ----
t_vv      = otsu_db(x);
t_vh      = otsu_db(y);
t_change  = -3.0;                   % fixed in code/config/config.yaml
t_kittler = kittler_threshold(x, 256);
t_gmm     = gmm_threshold(x(1:8:end), 40, 20001);   % 1-in-8 subsample, as Python

fprintf('Otsu VV = %8.4f dB   (Python -12.5534)\n', t_vv);
fprintf('Otsu VH = %8.4f dB   (Python -17.3090)\n', t_vh);
fprintf('Kittler = %8.4f dB   (Python -14.0180)\n', t_kittler);
fprintf('GMM     = %8.4f dB   (Python -10.2654)\n', t_gmm);

%% ---- write thresholds.csv and self-check against the Python tables ----
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

%% ======================= local functions =======================

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