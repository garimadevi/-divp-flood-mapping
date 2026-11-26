%% setup_paths.m - every path in one place (mirrors code/config/config.yaml)
this_dir = fileparts(mfilename('fullpath'));
if isempty(this_dir), this_dir = pwd; end

% Locate project root (containing 'data' or 'outputs' or '-divp-flood-mapping')
cand = fileparts(this_dir);
if ~exist(fullfile(cand, 'outputs'), 'dir') && exist(fullfile(cand, '-divp-flood-mapping', 'outputs'), 'dir')
    cand = fullfile(cand, '-divp-flood-mapping');
elseif ~exist(fullfile(cand, 'outputs'), 'dir') && exist(fullfile('D:\DIVP PROJECT', '-divp-flood-mapping', 'outputs'), 'dir')
    cand = fullfile('D:\DIVP PROJECT', '-divp-flood-mapping');
end

P.root      = cand;
P.processed = fullfile(P.root,'data','processed');
P.raw       = fullfile(P.root,'data','raw');
P.tables    = fullfile(P.root,'outputs','tables');
P.out       = fullfile(P.root,'matlab','out');
if ~exist(P.out,'dir'), mkdir(P.out); end
disp('paths ready');