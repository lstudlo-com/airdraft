# Parakeet TDT v3

Airdraft supports NVIDIA Parakeet TDT 0.6B v3 through its existing sherpa-onnx CPU runtime. Select **Parakeet TDT v3** on Models and download it explicitly. The app and `airdraft-cli transcribe <audio> --parakeet` then load the installed files without downloading during inference.

The model recognizes **25 European languages**, including English, with automatic language detection. It does **not** support Mandarin or Cantonese. Language and vocabulary hints do not force its decoder. It is a whole-utterance recognizer; Airdraft splits long recordings near silence. Live preview, when enabled, uses Apple Speech with an independently selected language. Speed and accuracy remain unrated until Airdraft has comparative measurements.

## Installation and runtime

- Runtime: existing sherpa-onnx **v1.13.8**, ONNX Runtime **1.28.2**; no new dependency. The C API uses `nemo_transducer`, encoder/decoder/joiner, CPU and greedy decoding. NeMo feature settings are read from model metadata.
- Archive: [official v3 INT8 conversion](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2), **487,170,055 bytes**; about **640 MiB** of installed model files.
- SHA256: `5793d0fd397c5778d2cf2126994d58e9d56b1be7c04d13c7a15bb1b4eafb16bf`. `ModelDownloader` verifies this published release-asset digest before extraction.
- Required files: `encoder.int8.onnx`, `decoder.int8.onnx`, `joiner.int8.onnx`, `tokens.txt`, all nonempty regular files.
- Location: `~/Library/Application Support/Transcribar/Models/sherpa-onnx/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/`. An incomplete-download marker blocks loading until installation finishes.

The provider ID is `parakeet`; its engine/history ID is `sherpa-onnx:parakeet`. Models, menu selection, saved settings, factory caching and the CLI share this identity. No app preferences or model directories are changed by the test fixture initializer.

## Attribution and primary references

**Model:** [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), licensed under [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/legalcode.en). NVIDIA created the original model; the [sherpa-onnx project](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/nemo-transducer-models.html#sherpa-onnx-nemo-parakeet-tdt-0-6b-v3-int8-25-european-languages) supplies the ONNX conversion and INT8 quantization used here. Airdraft uses that conversion without further model modification. These credits do not imply endorsement.

**Runtime:** sherpa-onnx uses [Apache License 2.0](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/LICENSE). Integration follows its [pinned C example](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/c-api-examples/nemo-parakeet-c-api.c) and [NeMo feature-metadata handling](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.8/sherpa-onnx/csrc/offline-recognizer-transducer-nemo-impl.h#L227-L250). Archive size and digest come from the [official release metadata](https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/asr-models), checked September 26, 2026.

## Validation

`ParakeetTests` covers saved-config round trips, factory identity and caching, all required assets, interrupted installs, archive integrity and failure without implicit download. The native test is opt-in: set `AIRDRAFT_PARAKEET_TEST_MODEL_DIR` to an explicitly downloaded, verified model folder. With Xcode, pass it as `TEST_RUNNER_AIRDRAFT_PARAKEET_TEST_MODEL_DIR` if needed to propagate it to the test process.

The native test resamples the included 24 kHz `test_wavs/en.wav` to 16 kHz, checks the official reference sentence, unloads and reloads, and checks nine repetitions in a 45-second recording across chunk boundaries. It never installs model files or changes user settings. These checks validate integration and lifecycle, not a multilingual accuracy benchmark.

Validated September 26, 2026 on this Mac: the official sample, unload/reload and all nine phrases in the 45-second recording passed. The full suite passed 240 tests with three pre-existing skips. Sample inference took about 0.11 seconds and the 45-second fixture about 1.00 second; these are fixture timings, not general performance claims.
