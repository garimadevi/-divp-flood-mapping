%% setup_paths.m - every path in one place (mirrors code/config/config.yaml)
P.root      = 'D:\DIVP PROJECT';
P.processed = fullfile(P.root,'data','processed');
P.raw       = fullfile(P.root,'data','raw');
P.tables    = fullfile(P.root,'outputs','tables');
P.out       = fullfile(P.root,'matlab','out');
if ~exist(P.out,'dir'), mkdir(P.out); end
disp('paths ready');