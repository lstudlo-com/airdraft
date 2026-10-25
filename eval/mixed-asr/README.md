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

## AD-082 follow-up: local output guards

AD-082 adds deterministic guards to local speech output. This section records
their before/after measurement, taken 2026-10-23/24 on the same Mac from base
commit `9e93a8f`. The corpus came from `prepare_corpus.py`, and all 180 audio files
match the manifest digests byte for byte. `run_guards.py` drives the same
production route as above, `score_guards.py` scores it, `guard_log.py` attaches the
app's text-free `asr-guard` log lines, and `punctuation_eval.py` compares
punctuation. `english_control.json` adds 20 pure-English sentences, spoken by four
macOS English voices, as a false-positive check. All results are in
`results/guards-ad082.json`; the AD-074 files are unchanged. The system languages
were en-TW and zh-Hant-TW.

What the guards do:
- **Qwen3-ASR decode budget**: `maxTokens` per chunk is 16 tokens per second of
  audio plus 48, with a ceiling of 1024 (previously a fixed 1024).
- **Loop trimming** for every local engine: a block of up to 10 tokens repeated
  8× (one token), 6× (two tokens) or 4× and at least 12 tokens is cut to its
  first occurrence. Ordinary emphasis such as `對對對` or `哈哈哈哈哈哈` is kept.
- **Language sanity** under Auto, for local engines with a language control
  (Qwen3-ASR, Whisper, SenseVoice, GGUF):
  - When 30% or more of the letters are in a script none of the user's languages
    use, the audio is decoded once more with the user's first non-English
    language that the model supports. The retry is kept only when its script
    fits the user's languages better.
  - For Whisper, a Latin-only result triggers a check of Whisper's own
    spoken-language distribution: one encoder pass. When P(zh) is 0.1 or more,
    the audio is decoded once with zh, and that result is kept only when at
    least 20% of its letters are Han.
- **Empty Whisper output** on audible audio (at least 0.25 s above −40 dBFS) gets
  one retry without the no-speech gate or prompt. Known filler hallucinations
  such as "Thank you." are rejected.
- Retries use the same model under the same lease, never another model. They
  run only when the first decode took at most max(8 s, 1.5 × audio duration), and
  a failed retry keeps the first result.
- **SenseVoice/FireRedASR2 text**: all-capitals English gets natural case.
  Dictionary terms, an acronym/product allowlist, vowel-less acronyms and
  spelled letters keep their spelling, and English-only sentences start with a
  capital. One sentence-final mark is added (`。`, `？` after 嗎, `.` or `?`) when
  the text has at least three tokens and no final punctuation.

Results (ASCEND 100 + Meijia 40, first attempt; MER is case-insensitive):

| Config | Measure | Before | After |
|---|---|---|---|
| Qwen3-ASR 0.6B zh, tw08 ×2 | loop, asrMs, peak footprint | looped to 1,024 tokens, 25.6–28.5 s, 18.5 GB | `是爸爸在克里`, 1.1 s, 1.6 GB |
| Qwen3-ASR 1.7B Auto, tw08 ×2 | output language | Ukrainian | Chinese (retried with zh, = the zh result) |
| Qwen3-ASR 1.7B Auto / 0.6B zh | MER, EN keep (both corpora) | unchanged | unchanged |
| Whisper v3 Turbo Auto, ASCEND | empty / Chinese lost / MER | 2 / 7 / 0.211 | 0 / 3 / 0.186 |
| Whisper v3 Turbo zh, ASCEND | empty / Chinese lost / MER | 3 / 4 / 0.208 | 0 / 1 / 0.192 |
| Whisper problem IDs ×3, zh | empty runs | 6 of 30 | 0 of 30 |
| SenseVoice Auto, ASCEND | ALL-CAPS outputs / punctuated | 84 / 0 | 1 / 100 |
| FireRedASR2, ASCEND | ALL-CAPS outputs / punctuated | 90 / 0 | 2 / 100 |
| SenseVoice / FireRedASR2, Meijia | EN keep, exact case | 6.9% / 8.1% | 57.5% / 77.0% |
| SenseVoice / FireRedASR2, English control | EN keep, exact case | 2.8% / 2.8% | 84.5% / 97.2% |

The remaining ALL-CAPS outputs contain only acronyms (KPI, LG, CRP, WCH). MER and
case-insensitive English retention are identical before and after for
SenseVoice, FireRedASR2 and Qwen3-ASR.

On the English control set, no guard changed any output. Whisper's probe gave
P(zh) ≤ 0.0002 for all 20 English sentences, against 0.14–0.85 for the ASCEND
utterances it had translated. Two translated utterances stay English: their
P(zh) was 0.006 and 0.03, and their references are mostly English. One more
(tes-00678) is fixed in 1 of 3 runs because Whisper's zh retry itself varies.

**Cost.** The Whisper language probe runs only for Latin-only Auto results when
the user also has a Chinese, Japanese or Korean system language. It adds about
0.4 s to such a dictation: the English control median rose from 584 to 980 ms.
On ASCEND it ran for 6 of 100 utterances. Every other configuration's latency is
unchanged within noise.

**Punctuation model (not adopted).** sherpa-onnx's offline CT-Transformer zh-en
int8 model (`sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12-int8`,
64.7 MB, SHA-256 `c0d5aa5f…a6e1`) was run through the vendored C API in an
evaluation-only harness. Qwen3-ASR 1.7B zh punctuation served as the proxy
reference. F1 for punctuation after aligned tokens:

| Method | SenseVoice | FireRedASR2 |
|---|---|---|
| Shipped final-mark rule (precision / recall / F1) | 0.96 / 0.46 / 0.62 | 0.99 / 0.46 / 0.63 |
| CT-Transformer | 0.87 / 0.74 / 0.80 | 0.90 / 0.75 / 0.82 |

It loads in 72 ms, runs in about 1.3 ms per utterance and changes no tokens.
However, it removes the spaces between English and Chinese in 126 of 140
outputs and ends English sentences with full-width `？`/`。`. Adopting it needs
a space-preserving realignment and an explicit, pinned, optional download in
Models. It remains a follow-up.

## 2026-10-24 follow-up: the original multilingual SenseVoice

AD-083 found that the SenseVoice archive measured above (sherpa-onnx int8
2025-09-09) is converted from ASLP-lab WSYue-ASR `sensevoice_small_yue`, a
Cantonese fine-tune. Airdraft now also installs the original SenseVoiceSmall
(int8 2024-07-17, pinned by URL, bytes and SHA-256) as "SenseVoice"
(`sherpa:senseVoiceMultilingual`); the fine-tune keeps `sherpa:senseVoice` as
"SenseVoice Cantonese". Both, plus Qwen3-ASR 1.7B, were rerun through the same
production route from a working tree on `0196926` (`run_matrix.py --followup`):
ASCEND and the Meijia set, Auto and zh, at one build. The corpus was regenerated
with `prepare_corpus.py`; `manifest.json` did not change. The original artifact
was installed with the app's `--e2e-action download`. `score.py --followup` writes
`results/followup-2026-10-24/`; the AD-074 and AD-082 result files are unchanged.
The output guards (AD-082) are active in every row here.

| Corpus | Model | Lang | MER | CER | WER | EN keep | p50 ms |
|---|---|---|---|---|---|---|---|
| ASCEND | SenseVoice | Auto | 0.126 | 0.097 | 0.429 | 59.3% | 52 |
| ASCEND | SenseVoice | zh | 0.136 | 0.104 | 0.460 | 54.9% | 52 |
| ASCEND | SenseVoice Cantonese | Auto | 0.136 | 0.093 | 0.509 | 52.6% | 52 |
| ASCEND | SenseVoice Cantonese | zh | 0.137 | 0.092 | 0.522 | 50.9% | 52 |
| ASCEND | Qwen3-ASR 1.7B | Auto | 0.089 | 0.077 | 0.243 | 76.1% | 292 |
| ASCEND | Qwen3-ASR 1.7B | zh | 0.089 | 0.082 | 0.217 | 78.8% | 300 |
| Meijia | SenseVoice | Auto | 0.122 | 0.026 | 0.506 | 57.5% | 45 |
| Meijia | SenseVoice | zh | 0.117 | 0.026 | 0.483 | 59.8% | 46 |
| Meijia | SenseVoice Cantonese | Auto | 0.103 | 0.026 | 0.483 | 58.6% | 45 |
| Meijia | SenseVoice Cantonese | zh | 0.117 | 0.024 | 0.552 | 51.7% | 45 |
| Meijia | Qwen3-ASR 1.7B | Auto | 0.028 | 0.003 | 0.138 | 89.7% | 255 |
| Meijia | Qwen3-ASR 1.7B | zh | 0.028 | 0.009 | 0.115 | 90.8% | 264 |

CIs are in `summary.json`. The SenseVoice Cantonese and Qwen3-ASR rows equal the
AD-074 rows to three decimals. Paired (`paired_vs_sensevoice_auto`, keyed by
`vs`; negative MER is better):

| Corpus | Comparison | ΔMER (95% CI) | ΔEN keep (95% CI) |
|---|---|---|---|
| ASCEND | SenseVoice − SenseVoice Cantonese, Auto | −0.010 (−0.026…+0.007) | +6.6 pt (−2.0…+14.8) |
| Meijia | SenseVoice − SenseVoice Cantonese, Auto | +0.019 (−0.019…+0.056) | −1.1 pt (−12.9…+10.5) |
| ASCEND | Qwen3-ASR 1.7B − SenseVoice, Auto | −0.037 (−0.053…−0.021) | +16.8 pt (+8.9…+24.9) |
| Meijia | Qwen3-ASR 1.7B − SenseVoice, Auto | −0.094 (−0.134…−0.055) | +32.2 pt (+20.0…+43.5) |
| ASCEND | SenseVoice zh − SenseVoice Auto | +0.010 (+0.002…+0.019) | −4.4 pt (−8.6…−0.5) |

On mixed Mandarin–English the two SenseVoice artifacts are statistically tied.
Together with FLEURS (`eval/eja-asr/`, same date: the original is 2.8 points
better on Mandarin, the fine-tune 0.8 points better on Cantonese, and the
fine-tune fails on Japanese, Korean and English), "SenseVoice" now means the
original model and the fine-tune is retired for new users. Qwen3-ASR 1.7B stays
the Chinese recommendation, with SenseVoice first on Macs with 8 GB or less.
With an explicit zh, SenseVoice's latency now equals Auto (52 ms p50 on ASCEND,
against 414 ms in AD-074): preparation builds the recognizer for the recording's
language.

```sh
W=/tmp/airdraft-wave/sensevoice-fixes/work
python3 -I eval/mixed-asr/prepare_corpus.py --work "$W"
python3 -I eval/mixed-asr/run_matrix.py --app "$APP" --work "$W" --followup
python3 -I eval/mixed-asr/score.py --work "$W" --followup
```

## AD-098 follow-up: the Auto language guard for every script

The Auto language guard now covers every script, not only Chinese, Japanese and
Korean. A result in a script that none of the system languages (plus English)
use was already decoded again; with a language probe (Whisper) it is now decoded
in the most probable system language: a non-English one when it reaches its
translation threshold, otherwise the most probable one, so English speech is not
forced into the user's other language. Without a probe it uses the first non-English
system language, as before. The Latin-only translation check now applies to every
system language written in another script (Cyrillic, Arabic, Devanagari, Hebrew,
Greek, Thai, Bengali and the other `WritingScript` scripts; Serbian is excluded
because it is written in Latin as often as Cyrillic), with the default threshold
0.1 per language.

Measured 2026-10-25 on the M4 Pro from `claude/intl-core` (after) against its base
`5161b58` (before), with APFS clones of the installed Whisper Large v3 Turbo and
Qwen3-ASR 1.7B. `run_guards.py --system-languages` sets the preferred languages
through `-AppleLanguages`; `guard_log.py --app` keeps only that build's log lines,
because other worktrees ran the app at the same time. New corpora (macOS `say`,
16 kHz): `intl_control.json`, 14 Russian (Milena), 14 Hindi (Lekha) and 8 Arabic
(Majed) dictation sentences, 8 of them code-switched with English terms, and
`en-in-control`, the 20 English control sentences in three Indian English voices.
All results are in `results/guards-ad098.json`.

| System languages | Corpus, model | Measure | Before | After |
|---|---|---|---|---|
| ru, en | English control 40 (20 US/UK/AU/IN + 20 IN), Whisper Auto | language retries / max P(ru) | 0 / not probed | 0 / 0.0011 |
| hi, en | same | language retries / max P(hi) | 0 / not probed | 0 / 0.000015 |
| ar, en | same | language retries / max P(ar) | 0 / not probed | 0 / 0.0001 |
| ru / hi / ar | native speech 14 / 14 / 8, Whisper and Qwen3-ASR 1.7B Auto | outputs without the native script; WER | 0; 0.150 / 0.260 / 0.093 (Whisper) | identical outputs |
| en-TW, zh-Hant-TW | ASCEND 100, Meijia 40, English control 20, Whisper Auto; tw08 ×2, Qwen3-ASR Auto | language retries, MER, Chinese lost | 2 / 0 / 2 retries, MER 0.199 / 0.063, 4 lost | same retries, MER 0.196 / 0.063, 4 lost |

Every Russian, Hindi and Arabic output, and every English control output, is byte
for byte the same before and after. On the Chinese sets 3 of 162 outputs differ;
all three are Whisper's nondeterministic empty first decode (the empty retry ran in
the before run only), not the language guard. English speech scores at most 0.0011
for any of these languages, two orders of magnitude below the 0.1 threshold, so no
per-language threshold is set (`LocalASROutputGuard.measuredTranslationProbabilities`).

The synthetic Russian, Hindi and Arabic speech never came back translated or
transliterated, not even with English terms, so this measures only false positives
and cost, not how many real translations the check repairs. **Cost:** the probe now
runs for Latin-only Whisper Auto results of Russian, Hindi and Arabic users too:
the English control median rose from 606 to 1001 ms (ru) and 597 to 1045 ms (ar),
the same ~0.4 s that Chinese users already pay (the hi run was noisy: 1170 to
1208 ms). The 1-minute load average was 4.4–34, median 7.4 (other worktrees were building); treat latencies as relative.

```sh
W=/tmp/airdraft-wave/intl-core/asr-eval   # models/ and audio/ as above
python3 -I eval/mixed-asr/run_guards.py --app "$APP" --work "$W" --tag after-ru \
    --system-languages ru-RU,en-US --intl --corpora intl-ru --configs whisper:turbo:auto,qwen3:1.7b:auto
python3 -I eval/mixed-asr/run_guards.py --app "$APP" --work "$W" --tag after-ru \
    --system-languages ru-RU,en-US --english --english-in --corpora en-control,en-in-control --configs whisper:turbo:auto
python3 -I eval/mixed-asr/guard_log.py --work "$W" --tag after-ru --app "$APP"
python3 -I eval/mixed-asr/score_guards.py --work "$W" --tags before-ru,after-ru
```
