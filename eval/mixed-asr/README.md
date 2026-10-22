# AD-074: local speech models for mixed Chinese–English dictation

This is a measurement only. It does not change product behavior. The question:
which local speech model should a Traditional Chinese (zh-TW) user get first when
they mix Mandarin and English terms in one sentence? Onboarding currently marks
SenseVoice "Best fit" for zh/en/ja/ko system languages, while Models describes
Qwen3-ASR 1.7B as best for mixed Chinese and English.

Measured 2026-10-21 at source commit `2242fb4` on an Apple M4 Pro (48 GB, macOS
27.0.1). `results/environment.json` records the hardware, model artifacts and
digests.

## Method

**Route.** Each utterance runs once through the Debug app's production pipeline:
`LocalE2E --e2e-action transcribe --e2e-prepare`. `run_matrix.py` drives it with
isolated data (one `--e2e-local` directory per configuration) and
`AIRDRAFT_E2E_MODEL_ROOT=/tmp/.../models`. Refinement and app context are off,
insertion is disabled and the dictionary is empty. The pipeline resolves
`SpeechLanguagePolicy`, sends the script hint (`以下是繁體中文的內容。` only when
Chinese is selected) and applies `ChineseScriptConverter` with the ASRConfig
default, Traditional. The scored text is the pipeline's final output, as saved
to history. Utterances form the outer loop and configurations the inner loop.

**Language settings.** Two settings a zh-TW user would actually have: **Auto**
(the default for a new install) and **zh** (Mandarin Chinese), both with the
Traditional script. FireRedASR2 ignores the setting (`.notApplied`), so it runs
only once.

**Models.** SenseVoice Small (sherpa-onnx int8 2025-09-09) and FireRedASR2-AED
(int8 2026-02-26) were installed with the app's own download path
(`--e2e-action download`, which checks the archive hash before unpacking).
Qwen3-ASR 1.7B MLX 5-bit, Qwen3-ASR 0.6B MLX 4-bit and Whisper Large v3 Turbo
(Core ML) are APFS clones of the user's installed copies. Cohere was not tested.

**Corpora** (`manifest.json`; audio stays under `/tmp`):

| Corpus | Utterances | Audio | Description |
|---|---|---|---|
| `ascend` | 100 | 480 s | Real conversational Mandarin–English code-switching from [ASCEND](https://huggingface.co/datasets/CAiRE/ASCEND) (CAiRE, CC BY-SA 4.0), test and validation splits at revision `737e980`. Selection: `mixed` label, ≥4 Han characters, ≥1 English word, 2.5–15 s, deterministic order, at most 25 per speaker (5 speakers). The references are Simplified Chinese, from speakers in Hong Kong and Mainland China. |
| `tw-tts-meijia` | 40 | ~130 s | 40 Taiwan-style workplace and developer sentences (`taiwan_synthetic.json`, e.g. 「我等一下把 PR merge 到 main branch」) spoken by the macOS `say` zh_TW Meijia voice. |
| `tw-tts` | 40 | 132 s | The same sentences rotated across the Meijia, Flo, Eddy and Reed zh_TW voices. Flo, Eddy and Reed pronounce English badly: every model drops to roughly 0–30% English retention on them (`tw_tts_by_voice`), so this set mostly measures robustness to degraded audio. |

Synthetic TTS is a weak proxy for real Taiwanese speakers. It has clean audio,
no disfluencies and textbook English pronunciation. The `ascend` set is the main
evidence; the Meijia set adds Taiwan vocabulary and Traditional characters.
The manifest includes ASCEND transcriptions, so it is shared under CC BY-SA 4.0
with attribution to CAiRE/ASCEND.

**Normalization** (`score.py`, applied to both reference and hypothesis):
convert with ICU `Hans-Hant`, the transform `ChineseScriptConverter` uses; apply
NFKC and lowercase; drop apostrophes; remove punctuation; tokenize each Han
character and each Latin or digit run; join spelled single letters
(`p r` → `pr`); drop fillers (呃 嗯 欸 誒 唔 / uh um uhm hmm mm erm). Digits and
Chinese numerals are not converted.

**Metrics.**
- **MER**: edit distance over the combined token sequence divided by the number
  of reference tokens. The table shows a 95% bootstrap CI.
- **CER**: the same, Han tokens only. **WER**: the same, Latin tokens only.
- **EN keep**: the share of reference English words found in the hypothesis
  (multiset match, case-insensitive). On the TTS sets, case-exact retention is
  also recorded.
- **Latency**: `asrMs` after `--e2e-prepare`, so the model is already loaded.
  Each utterance runs in its own process, so every measurement is that model's
  first inference after load. It is an upper bound on warm steady-state latency.
- **Memory**: peak footprint from `/usr/bin/time -l`. Without a model the app
  uses about 22 MB.
- **Load**: `asrMs` without `--e2e-prepare` minus `asrMs` with it, on the same
  file, with the OS file cache warm.

A failed or empty run is scored as a full deletion. For Whisper, the first
attempt is scored; retries are listed in `results/anomalies.json`.

## Results

ASCEND (real code-switching, 100 utterances):

| Model | Lang | MER (95% CI) | CER | WER | EN keep | EN dropped | Chinese lost | ALL-CAPS English | Punctuated | p50 / p90 ms |
|---|---|---|---|---|---|---|---|---|---|---|
| SenseVoice | Auto | 0.136 (0.113–0.160) | 0.093 | 0.509 | 52.6% | 8 | 0 | 84 | 0 | 52 / 87 |
| SenseVoice | zh | 0.137 (0.114–0.161) | 0.092 | 0.522 | 50.9% | 9 | 0 | 83 | 0 | 414* / 448 |
| Qwen3-ASR 1.7B | Auto | **0.089** (0.073–0.108) | 0.077 | 0.243 | 76.1% | 7 | 0 | 3 | 100 | 300 / 456 |
| Qwen3-ASR 1.7B | zh | **0.089** (0.072–0.108) | 0.082 | **0.217** | **78.8%** | 7 | 0 | 3 | 100 | 308 / 472 |
| Qwen3-ASR 0.6B | Auto | 0.107 (0.087–0.130) | 0.094 | 0.292 | 73.0% | 9 | 1 | 4 | 100 | 244 / 375 |
| Qwen3-ASR 0.6B | zh | 0.106 (0.085–0.128) | 0.098 | 0.257 | 74.8% | 8 | 0 | 4 | 100 | 244 / 388 |
| FireRedASR2 | (n/a) | 0.093 (0.075–0.113) | 0.077 | 0.279 | 74.8% | 8 | 0 | 90 | 0 | 612 / 1226 |
| Whisper v3 Turbo | Auto | 0.211 (0.167–0.264) | 0.183 | 0.589 | 68.1% | 6 | 7 | 5 | 34 | 634 / 1208 |
| Whisper v3 Turbo | zh | 0.208 (0.172–0.248) | 0.195 | 0.460 | 62.8% | 13 | 4 | 5 | 87 | 622 / 733 |

"EN dropped" counts utterances whose output has no English word although the
reference has one. "Chinese lost" counts outputs that keep less than 30% of the
reference's Han characters, which includes translation into English and empty
output. Each count is out of 100.

Taiwan-style TTS, Meijia voice (40 sentences):

| Model | Lang | MER (95% CI) | CER | WER | EN keep | EN keep (exact case) | p50 ms |
|---|---|---|---|---|---|---|---|
| SenseVoice | Auto | 0.103 (0.074–0.133) | 0.026 | 0.483 | 58.6% | 6.9% | 45 |
| SenseVoice | zh | 0.117 (0.091–0.146) | 0.024 | 0.552 | 51.7% | 5.7% | 388* |
| Qwen3-ASR 1.7B | Auto | **0.028** (0.012–0.048) | 0.003 | 0.138 | 89.7% | 80.5% | 258 |
| Qwen3-ASR 1.7B | zh | **0.028** (0.012–0.047) | 0.009 | **0.115** | **90.8%** | **82.8%** | 266 |
| Qwen3-ASR 0.6B | Auto | 0.059 (0.030–0.090) | 0.035 | 0.218 | 80.5% | 56.3% | 200 |
| Qwen3-ASR 0.6B | zh | 0.068 (0.032–0.110) | 0.050 | 0.230 | 79.3% | 58.6% | 201 |
| FireRedASR2 | (n/a) | 0.059 (0.036–0.085) | 0.003 | 0.287 | 79.3% | 8.1% | 504 |
| Whisper v3 Turbo | Auto | 0.063 (0.035–0.098) | 0.021 | 0.241 | 78.2% | 48.3% | 596 |
| Whisper v3 Turbo | zh | 0.070 (0.042–0.106) | 0.024 | 0.264 | 75.9% | 49.4% | 606 |

\* SenseVoice rebuilds its recognizer when its effective language changes.
`--e2e-prepare` loads it for Auto, so the zh runs include a rebuild of about
350 ms. In normal use the recognizer stays built for the saved language, so
expect latency close to the Auto rows.

Paired bootstrap against the current recommendation, SenseVoice with Auto
(`paired_vs_sensevoice_auto`). Negative MER is better:

| Model | Lang | ASCEND ΔMER (95% CI) | ASCEND ΔEN keep | Meijia ΔMER | Meijia ΔEN keep |
|---|---|---|---|---|---|
| Qwen3-ASR 1.7B | Auto | −0.046 (−0.064…−0.030) | +23 pt (+17…+30) | −0.075 (−0.105…−0.046) | +31 pt |
| Qwen3-ASR 1.7B | zh | −0.046 (−0.064…−0.030) | +26 pt (+19…+33) | −0.075 (−0.104…−0.048) | +32 pt |
| Qwen3-ASR 0.6B | Auto | −0.028 (−0.048…−0.009) | +20 pt | −0.045 (−0.076…−0.012) | +22 pt |
| FireRedASR2 | (n/a) | −0.043 (−0.061…−0.025) | +22 pt | −0.045 (−0.067…−0.023) | +21 pt |
| Whisper v3 Turbo | Auto | +0.075 (+0.033…+0.125) | +15 pt | −0.040 (−0.072…−0.005) | +20 pt |

Cost and resources on the M4 Pro:

| Model | Download | On disk | Peak footprint median / p95 | Load (warm cache) | Latency fit (ms) | RTF median |
|---|---|---|---|---|---|---|
| SenseVoice | 166 MB | 247 MB | 886 / 974 MB | 0.36 s | 16 + 9/s audio | 0.013 |
| Qwen3-ASR 1.7B | 2.3 GB | 2.3 GB | 2388 / 2683 MB | 0.60 s | 126 + 42/s | 0.073 |
| Qwen3-ASR 0.6B | 680 MB | 680 MB | 1270 / 1555 MB (one 17.6 GB outlier) | 0.60 s | 90 + 37/s | 0.059 |
| FireRedASR2 | 840 MB | 1.2 GB | 2697 / 2887 MB | 1.26 s | −18 + 153/s | 0.149 |
| Whisper v3 Turbo | 1.5 GB | 1.6 GB | 227 / 235 MB in process** | 1.35 s (87.6 s on first load from a new path) | 344 + 91/s | 0.167 |

\*\* Core ML and Neural Engine memory partly lives outside the app process, so
Whisper's footprint is not comparable with the others.

### Behavior notes (see `results/utterances.csv`, `results/anomalies.json`)

- **SenseVoice and FireRed output English in ALL CAPS** (for example
  `我現在換 MAJ了換成 CO EGINERING` or `先跑一下 UNIT TEST再 DEPLOY`), in 84% and
  90% of ASCEND outputs, and they add no punctuation. The case-insensitive
  metrics hide this. The text a user actually gets keeps the original case of
  only about 6–8% of English words (Meijia set).
- Qwen3-ASR punctuates every output and keeps natural English case. Auto and zh
  perform the same on real speech. On one degraded TTS clip (tw08, Reed voice),
  1.7B with Auto returned Ukrainian text; the result reproduces, and zh avoids it.
- **Qwen3-ASR 0.6B can loop.** With zh on tw08 it repeated `克里克里…` until its
  1024-token cap: 24 s and a reproducible peak footprint of about 18.5 GB. That
  would be serious on 8–16 GB Macs.
- **Whisper Turbo is unsuitable for this use**. Under Auto it translated 5 of
  100 real code-switched utterances into English, and 1 even with zh. In 6 of
  360 first attempts it returned no text at all, so the pipeline delivered
  nothing. Retries succeed
  only sometimes; the empty result is nondeterministic. Its first load from a
  new model path took 87.6 s.
- The raw output of most models is Simplified (e.g. SenseVoice 94/100 ASCEND).
  The app's converter fixes the characters but not word choice (软件/軟體), which
  is left to refinement.

## Interpretation

On real code-switched speech, Qwen3-ASR 1.7B has the lowest error of every model
tested: 35% fewer mixed-token errors than SenseVoice and 23–26 points more
English words kept. The Meijia set agrees, with 73% fewer errors. FireRed is
close on Chinese characters, but like SenseVoice it outputs English in ALL CAPS
without punctuation, and it is the slowest model with the most memory.
SenseVoice's advantages are size (14× smaller download), speed (about 6× faster)
and memory (about 2.7× less). On this Mac its speed difference, about 50 ms
against 300 ms, is small next to refinement time. Auto and zh are statistically
indistinguishable for Qwen3-ASR 1.7B on real speech.

## Caveats

- Five ASCEND speakers, with Mainland/HK accents and conversational speech. Real
  Taiwanese accents and dictation-style speech are not covered except by TTS.
- Latency is each model's first inference after load, on a machine shared with
  concurrent Xcode builds; each run records its 1-minute load average, typically
  6–11. Treat the numbers as relative.
- Lower-end Macs were not measured. Two estimates, neither measured:
  - Qwen3-ASR runs on the GPU through MLX, and decoding is limited by memory
    bandwidth. An 8-GPU-core M1 (68 GB/s against 273 GB/s here) would likely be
    3–4× slower: roughly 1 s for a 5 s phrase and 4–5 s for 30 s of speech.
  - SenseVoice uses 4 CPU threads and would stay well under 200 ms.
  Memory matters more: about 2.4 GB for Qwen 1.7B against 0.9 GB for SenseVoice
  on an 8 GB Mac that may also run a local refinement LLM.
- Load times assume a warm OS file cache. A true cold start after reboot
  (`purge` needs sudo) was not measured.
- Qwen3-ASR and Whisper weights came from Hub `main` at measurement time, when the
  app did not pin them. The recorded file digests match the revisions that 0.11.0
  pins and verifies in `local-pinned-models.json`.

## Reproduce

```sh
APP="$HOME/Library/Developer/Xcode/DerivedData/<airdraft-…>/Build/Products/Debug/Airdraft Debug.app"
W=/tmp/airdraft-groupA/asr-eval
python3 -I eval/mixed-asr/prepare_corpus.py --work "$W"
# Models: APFS-clone installed models into $W/models (LocalModels layout), or run
# "$APP/Contents/MacOS/Airdraft Debug" --e2e-local "$W/sessions/dl" --e2e-action download --e2e-model sherpa:senseVoice
# with AIRDRAFT_E2E_MODEL_ROOT="$W/models".
python3 -I eval/mixed-asr/run_matrix.py --app "$APP" --work "$W"
python3 -I eval/mixed-asr/score.py --work "$W"
```

`run_matrix.py` retries failed runs when restarted. To keep first-attempt
scoring, keep failed run files before rerunning.
