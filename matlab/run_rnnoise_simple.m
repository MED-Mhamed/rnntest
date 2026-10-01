% RUN_RNNOISE_SIMPLE
% Independent one-file MATLAB experiment using the official RNNoise
% executable copied into this RNNTEST folder.
%
% Pipeline:
%   MAT speech/noise -> controlled SNR mixture -> 48 kHz -> PCM16
%   -> official RNNoise C program -> PCM16 -> metrics and plots.
%
% The implementation uses MATLAB built-ins for the experiment. It does not
% call scripts or functions from SYS835_RNNoise.

clear;
clc;
close all;

%% Configuration
FsOriginal = 8192;
FsRNNoise = 48000;
snrTargetDb = 10;
cleanFileName = '1z88153a8.mat';
noiseFileName = 'white8.mat';
playAudio = true;

thisFolder = fileparts(mfilename('fullpath'));
projectFolder = fileparts(thisFolder);
dataFolder = fullfile(projectFolder, 'professor_data');
generatedFolder = fullfile(projectFolder, 'generated');
if ~exist(generatedFolder, 'dir')
    mkdir(generatedFolder);
end

cleanFile = fullfile(dataFolder, 'Signal', cleanFileName);
noiseFile = fullfile(dataFolder, 'Bruit', noiseFileName);
rnnoiseExecutable = fullfile(projectFolder, 'rnnoise', 'examples', ...
    'rnnoise_demo');
if ~isfile(rnnoiseExecutable)
    error('RNNoise executable is missing: %s', rnnoiseExecutable);
end

%% Load and create a controlled noisy signal
clean = load_vector(cleanFile);
noise = load_vector(noiseFile);
noise = noise - mean(noise);
noise = repeat_to_length(noise, length(clean));
noise = noise(1:length(clean));

cleanEnergy = sum(clean .^ 2);
noiseEnergy = max(sum(noise .^ 2), eps);
noiseScale = sqrt(cleanEnergy / ...
    (10^(snrTargetDb / 10) * noiseEnergy));
scaledNoise = noiseScale * noise;
noisy = clean + scaledNoise;
inputPeak = max(abs(noisy));
if inputPeak <= 0
    error('The noisy signal is silent.');
end
clean = clean / inputPeak;
scaledNoise = scaledNoise / inputPeak;
noisy = noisy / inputPeak;

fprintf('Target SNR: %.3f dB\n', snrTargetDb);
fprintf('Measured SNR at source rate: %.3f dB\n', ...
    10 * log10(sum(clean .^ 2) / max(sum(scaledNoise .^ 2), eps)));

%% Prepare 48 kHz RNNoise input
clean48 = resample_signal(clean, FsOriginal, FsRNNoise);
noisy48 = resample_signal(noisy, FsOriginal, FsRNNoise);
noise48 = resample_signal(scaledNoise, FsOriginal, FsRNNoise);
commonLength = min([length(clean48), length(noisy48), length(noise48)]);
clean48 = clean48(1:commonLength);
noisy48 = noisy48(1:commonLength);
noise48 = noise48(1:commonLength);

frameSize = 480;
padding = mod(-length(noisy48), frameSize);
noisy48 = [noisy48; zeros(padding, 1)];
clean48 = [clean48; zeros(padding, 1)];
noise48 = [noise48; zeros(padding, 1)];

inputPcm = fullfile(generatedFolder, 'noisy_input_48k.pcm');
outputPcm = fullfile(generatedFolder, 'denoised_output_48k.pcm');
write_pcm16(inputPcm, noisy48);

%% Call the official C implementation through WSL on Windows
if ispc
    command = sprintf('wsl.exe "%s" "%s" "%s"', ...
        to_wsl_path(rnnoiseExecutable), to_wsl_path(inputPcm), ...
        to_wsl_path(outputPcm));
else
    command = sprintf('"%s" "%s" "%s"', rnnoiseExecutable, ...
        inputPcm, outputPcm);
end
fprintf('RNNoise command: %s\n', command);
tic;
[status, commandOutput] = system(command);
elapsed = toc;
if status ~= 0
    error('RNNoise failed (%d): %s', status, commandOutput);
end
if ~isfile(outputPcm)
    error('RNNoise did not create: %s', outputPcm);
end
denoised48 = read_pcm16(outputPcm);
fprintf('RNNoise processing time: %.3f s\n', elapsed);

%% Compensate the small algorithmic delay with a short correlation search
[cleanReference, denoisedAligned, delay] = align_by_correlation( ...
    clean48, denoised48, 2 * frameSize);
noisyReference = noisy48(1:length(cleanReference));
noiseReference = noise48(1:length(cleanReference));

inputError = noisyReference - cleanReference;
outputError = denoisedAligned - cleanReference;
metrics.inputSnrDb = 10 * log10(sum(cleanReference .^ 2) / ...
    max(sum(inputError .^ 2), eps));
metrics.outputSnrDb = 10 * log10(sum(cleanReference .^ 2) / ...
    max(sum(outputError .^ 2), eps));
metrics.improvementDb = metrics.outputSnrDb - metrics.inputSnrDb;
metrics.inputMse = mean(inputError .^ 2);
metrics.outputMse = mean(outputError .^ 2);

fprintf('Estimated delay: %d samples\n', delay);
fprintf('Input SNR: %.3f dB\n', metrics.inputSnrDb);
fprintf('Output SNR: %.3f dB\n', metrics.outputSnrDb);
fprintf('Improvement: %.3f dB\n', metrics.improvementDb);

save(fullfile(generatedFolder, 'results.mat'), ...
    'cleanReference', 'noiseReference', 'noisyReference', ...
    'denoisedAligned', 'metrics', 'delay', 'FsOriginal', 'FsRNNoise');

%% Plot waveforms and spectrograms
time = (0:length(cleanReference)-1) / FsRNNoise;
figure('Name', 'RNNTEST - waveforms');
subplot(4, 1, 1); plot(time, cleanReference); grid on;
title('Clean speech');
subplot(4, 1, 2); plot(time, noiseReference); grid on;
title('Noise');
subplot(4, 1, 3); plot(time, noisyReference); grid on;
title('Noisy speech');
subplot(4, 1, 4); plot(time, denoisedAligned); grid on;
title('RNNoise enhanced speech'); xlabel('Time (s)');

figure('Name', 'RNNTEST - spectrograms');
plot_spectrogram(cleanReference, FsRNNoise, 'Clean speech');
figure('Name', 'RNNTEST - noisy spectrogram');
plot_spectrogram(noisyReference, FsRNNoise, 'Noisy speech');
figure('Name', 'RNNTEST - enhanced spectrogram');
plot_spectrogram(denoisedAligned, FsRNNoise, 'RNNoise enhanced speech');

if playAudio
    play_one('Clean speech', cleanReference, FsRNNoise);
    play_one('Noise', noiseReference, FsRNNoise);
    play_one('Noisy speech', noisyReference, FsRNNoise);
    play_one('Enhanced speech', denoisedAligned, FsRNNoise);
end

%% Local helper functions
function vector = load_vector(fileName)
data = load(fileName);
if ~isfield(data, 'sigd')
    error('Missing variable sigd in %s', fileName);
end
vector = double(data.sigd(:));
if isempty(vector) || any(~isfinite(vector))
    error('Invalid signal in %s', fileName);
end
end

function output = repeat_to_length(input, targetLength)
repetitions = ceil(targetLength / length(input));
output = repmat(input, repetitions, 1);
end

function output = resample_signal(input, inputRate, outputRate)
if inputRate == outputRate
    output = input;
elseif exist('resample', 'file') == 2
    output = resample(input, outputRate, inputRate);
else
    warning('resample unavailable; using interp1 fallback.');
    oldTime = (0:length(input)-1)' / inputRate;
    newLength = round(length(input) * outputRate / inputRate);
    newTime = (0:newLength-1)' / outputRate;
    output = interp1(oldTime, input, newTime, 'linear', 'extrap');
end
output = output(:);
end

function write_pcm16(fileName, signal)
signal = max(-1, min(1, signal));
file = fopen(fileName, 'w', 'ieee-le');
if file < 0
    error('Cannot open PCM file for writing: %s', fileName);
end
count = fwrite(file, round(signal * 32767), 'int16');
fclose(file);
if count ~= length(signal)
    error('PCM write was incomplete.');
end
end

function signal = read_pcm16(fileName)
file = fopen(fileName, 'r', 'ieee-le');
if file < 0
    error('Cannot open PCM file for reading: %s', fileName);
end
signal = double(fread(file, inf, 'int16')) / 32768;
fclose(file);
signal = signal(:);
end

function pathWsl = to_wsl_path(pathWindows)
pathWindows = char(pathWindows);
if length(pathWindows) < 3 || pathWindows(2) ~= ':'
    error('Invalid Windows path: %s', pathWindows);
end
pathWsl = ['/mnt/' lower(pathWindows(1)) ...
    strrep(pathWindows(3:end), '\', '/')];
end

function [reference, aligned, bestDelay] = align_by_correlation(reference, ...
    signal, maximumDelay)
reference = reference(:);
signal = signal(:);
bestScore = -inf;
bestDelay = 0;
for delay = -maximumDelay:maximumDelay
    if delay >= 0
        count = min(length(reference), length(signal) - delay);
        a = reference(1:count);
        b = signal(delay + 1:delay + count);
    else
        shift = -delay;
        count = min(length(reference) - shift, length(signal));
        a = reference(shift + 1:shift + count);
        b = signal(1:count);
    end
    a = a - mean(a);
    b = b - mean(b);
    denominator = sqrt(sum(a .^ 2) * sum(b .^ 2));
    if denominator <= eps
        score = -inf;
    else
        score = abs(sum(a .* b)) / denominator;
    end
    if score > bestScore
        bestScore = score;
        bestDelay = delay;
    end
end
if bestDelay >= 0
    count = min(length(reference), length(signal) - bestDelay);
    reference = reference(1:count);
    aligned = signal(bestDelay + 1:bestDelay + count);
else
    shift = -bestDelay;
    count = min(length(reference) - shift, length(signal));
    reference = reference(shift + 1:shift + count);
    aligned = signal(1:count);
end
end

function play_one(label, signal, sampleRate)
fprintf('Playing %s\n', label);
peak = max(abs(signal));
if peak > 0
    signal = signal / peak;
end
sound(signal, sampleRate);
pause(length(signal) / sampleRate + 0.5);
end

function plot_spectrogram(signal, sampleRate, titleText)
if exist('spectrogram', 'file') == 2
    spectrogram(signal, local_hamming(960), 480, 1024, sampleRate, 'yaxis');
    title(titleText);
    colorbar;
else
    window = local_hamming(960);
    [spectrum, frequency, time] = manual_spectrogram(signal, window, ...
        480, 1024, sampleRate);
    imagesc(time, frequency, 20 * log10(max(spectrum, 1e-8)));
    axis xy;
    title(titleText);
    xlabel('Time (s)');
    ylabel('Frequency (Hz)');
    colorbar;
end

function window = local_hamming(lengthWindow)
index = (0:lengthWindow - 1)';
window = 0.54 - 0.46 * cos(2 * pi * index / (lengthWindow - 1));
end
end

function [magnitude, frequency, time] = manual_spectrogram(signal, window, ...
    hop, fftSize, sampleRate)
count = floor((length(signal) - length(window)) / hop) + 1;
magnitude = zeros(fftSize / 2 + 1, count);
for frame = 1:count
    startIndex = (frame - 1) * hop + 1;
    block = signal(startIndex:startIndex + length(window) - 1) .* window;
    spectrum = fft(block, fftSize);
    magnitude(:, frame) = abs(spectrum(1:fftSize / 2 + 1));
end
frequency = (0:fftSize / 2)' * sampleRate / fftSize;
time = (0:count - 1) * hop / sampleRate;
end
