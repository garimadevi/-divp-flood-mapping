clc;
clear;
close all;

% ==========================================
% MASTER SCRIPT - FLOOD MAPPING PROJECT
% ==========================================

% Get the directory containing this script
project_dir = fileparts(mfilename('fullpath'));

% Move MATLAB to the correct directory
cd(project_dir);

fprintf('\n====================================\n');
fprintf('   FLOOD MAPPING PIPELINE STARTED\n');
fprintf('====================================\n\n');

% Define execution sequence
scripts = {
    'setup_paths.m'
    'step1_read_filter.m'
    'step2_thresholds.m'
    'step3_masks.m'
    'step3_comparing_algorithms.m'
    'step4_confidence.m'
    'step5_validate.m'
    'step5_confidence_a.m'
    'step5_confidence_b.m'
    'step6_verify.m'
    'check_terrain.m'
};

% Execute scripts sequentially. Use a loop variable that the scripts
% themselves do not define: `run` shares this workspace, and step4
% uses `k` for the vote count.
for runIdx = 1:numel(scripts)

    fprintf('\n------------------------------------\n');
    fprintf('Running: %s\n', scripts{runIdx});
    fprintf('------------------------------------\n');

    try
        run(fullfile(project_dir, scripts{runIdx}));

        fprintf('SUCCESS: %s completed.\n', scripts{runIdx});

    catch ME
        fprintf('\nERROR in %s:\n', scripts{runIdx});
        fprintf('%s\n', ME.message);

        rethrow(ME);
    end

end

fprintf('\n====================================\n');
fprintf('   FLOOD MAPPING PIPELINE COMPLETED\n');
fprintf('====================================\n');