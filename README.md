# RNNTEST — RNNoise experiment

It explains how to design **one MATLAB script** that performs an experiment. 

The local paper is:

[1709.08243v3.pdf](C:/Users/Mhamed/Documents/sys835/project/1709.08243v3.pdf)
. Its MATLAB experiment is one file:

[run_rnnoise_simple.m](matlab/run_rnnoise_simple.m)


## Run

Open MATLAB and execute:

```matlab
cd('C:\Users\Mhamed\Documents\sys835\project\RNNTEST\matlab')
run_rnnoise_simple
```

The script:

1. loads one clean MAT signal and one MAT noise signal;
2. creates a 10 dB mixture;
3. converts the data from the assumed 8192 Hz to 48 kHz;
4. pads the input to complete 480-sample RNNoise frames;
5. writes raw mono signed PCM16;
6. calls the local official RNNoise executable through WSL;
7. reads the denoised PCM16 output;
8. compensates the small processing delay;
9. calculates SNR, MSE, and improvement;
10. saves `generated\results.mat`;
11. plots waveforms and spectrograms;
12. plays clean speech, noise, noisy speech, and enhanced speech.

## Independent runtime

The `rnnoise` directory is copied inside `RNNTEST`. The executable is the
official compiled RNNoise demo and requires its adjacent `.libs` runtime.
On Windows, MATLAB invokes it through `wsl.exe`. The source and build are
included so this folder does not depend on the original project's paths.

RNNoise expects raw mono signed PCM16 at 48 kHz, not WAV. This is why the
script writes `.pcm` files directly.

## Configuration

At the top of the script:

```matlab
FsOriginal = 8192;
FsRNNoise = 48000;
snrTargetDb = 10;
cleanFileName = '1z88153a8.mat';
noiseFileName = 'white8.mat';
playAudio = true;
```

The sampling-rate assumption is based on the professor data and must be
confirmed with the professor. The input and noise filenames can be changed to
the other supplied files.

## MATLAB built-ins used


- `resample` when available, with `interp1` as an offline fallback;
- `fft` for the fallback spectrogram;
- `spectrogram` when available;
- a local Hamming-window formula for visualization when the Signal
  Processing Toolbox is unavailable;
- `load`, `fread`, and `fwrite` for data and PCM;
- `sound` for playback.

RNNoise itself is still performed by the official C program, not by MATLAB.

## Results

The script saves:

```text
generated\noisy_input_48k.pcm
generated\denoised_output_48k.pcm
generated\results.mat
```

The results structure contains:

- `inputSnrDb`;
- `outputSnrDb`;
- `improvementDb`;
- `inputMse`;
- `outputMse`;
- estimated delay.

The validated run with `1z88153a8.mat`, `white8.mat`, and the configured
10 dB target produced:

| Measurement | Value |
|---|---:|
| Input SNR at 48 kHz | 11.244 dB |
| Output SNR | 13.836 dB |
| Improvement | 2.592 dB |
| Input MSE | 0.0024 |
| Output MSE | 0.0013 |
| Estimated delay | 479 samples |

This MATLAB installation did not provide `resample`, so this run used the
documented linear-interpolation fallback. The fallback is sufficient for
this offline demonstration, but a toolbox-enabled `resample` run can give
slightly different numerical results.

## References

- J.-M. Valin, “A Hybrid DSP/Deep Learning Approach to Real-Time Full-Band
  Speech Enhancement,” IEEE MMSP Workshop, 2018,
  `arXiv:1709.08243`.
- Official RNNoise source and README included in `rnnoise`. https://github.com/xiph/rnnoise
