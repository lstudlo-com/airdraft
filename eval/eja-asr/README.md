# AD-083: local speech models for English, Japanese and Korean

Question: which local speech model should first-run setup and Models recommend
to a user whose system language is English, Japanese or Korean? Through 0.11.0
all three got SenseVoice. AD-074 (`eval/mixed-asr/`) covered Chinese only.

Measured 2026-10-24 from source commit `7f79be0` on an Apple M4 Pro (48 GB,
macOS 27.0.1). `results/environment.json` lists the hardware, artifacts and
digests.

## Method

**Route.** Same as AD-074. Each utterance runs once through the Debug app's
production pipeline, `LocalE2E --e2e-action transcribe --e2e-prepare`, with one
`--e2e-local` data directory per configuration and
`AIRDRAFT_E2E_MODEL_ROOT=<work>/models`. Refinement and app context are off,
insertion is disabled, the dictionary is empty and the Chinese script is the
ASRConfig default (Traditional), as for a new install. Each language runs as a
user of that system language (`-AppleLanguages (en-US|ja-JP|ko-KR)`), which
sets the AD-082 output guards' expected languages. Utterances form the outer
loop and configurations the inner loop.

**Settings.** Every model runs in the languages its `SpeechLanguagePolicy`
supports, under Auto and the explicit language. Parakeet models ignore the
setting (`.notApplied`) and run once. Cohere has no Auto.

**Models.** Qwen3-ASR 1.7B and 0.6B, Whisper Large v3 Turbo, Cohere Transcribe
and Parakeet TDT v3 (sherpa-onnx) are APFS clones of the user's installed copies;
their digests match `local-pinned-models.json` where pinned. SenseVoice, Whisper
Large v3, Parakeet TDT v2 (Core ML) and Parakeet Japanese (Core ML) were
installed with the app's hash-verified `--e2e-action download`. Apple Speech was
not run (it needs OS language assets).

**SenseVoice 2024 (†, evaluation only).** The shipped SenseVoice archive
(`…-int8-2025-09-09`) says it is converted from `ASLP-lab/WSYue-ASR`
`sensevoice_small_yue`, a Cantonese fine-tune. To separate the model family
from that artifact, the original multilingual SenseVoiceSmall
(`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17`, archive SHA-256
`7d1efa21…d347e`, equal to the GitHub release digest) was staged under the
shipped folder name in a separate model root (`run_matrix.py --sensevoice-2024`).
The app cannot install it today.

**Corpus** (`manifest.json`, built by `prepare_corpus.py`; audio stays under
the work directory). [Google FLEURS](https://huggingface.co/datasets/google/fleurs)
test split (Conneau et al., SLT 2022; CC BY 4.0) for `en_us`, `ja_jp` and `ko_kr`,
Hub revision `70bb2e8`, parquet digests checked. Per language: recordings of
2–20 s; one recording per sentence; sentences ordered by SHA-256 of
`lang/id`; the first 60, at most 60% of one gender. FLEURS publishes no speaker
IDs. 60 utterances per language, 582 s (en), 788 s (ja) and 719 s (ko) of audio.
The references are the cased, punctuated `raw_transcription`. The manifest
reproduces them under CC BY 4.0 with this attribution.

**Normalization** (`score.py`, identical for reference and hypothesis): NFKC;
lowercase; apostrophes dropped; every Unicode punctuation or symbol character
becomes a space. English is scored as **WER** over words. Japanese and Korean are
scored as **CER** over characters with all whitespace removed (Korean spacing
varies between writers; Japanese has none). Numbers are not converted
(`25` vs `twenty-five`, `1967年` vs `千九百六十七年`), and kana/kanji spellings
of the same word count as errors.

**Metrics.**
- **Model output**: the engine's text after Airdraft's output guards, before
  `ChineseScriptConverter` and the dictionary. **Delivered**: the pipeline's final
  text as saved to History, which at `7f79be0` includes the script conversion.
- **95% CI**: 2000 bootstrap resamples of utterances (seed 83). Paired deltas
  resample the same utterances for both systems.
- **Clean subset**: utterances whose reference has no digit and no bracket.
  FLEURS references add unspoken glosses in brackets, such as `선거위원회(CEP)`
  or `(Cristina Fernandez de Kirchner)`, in 16 of 60 Korean ones.
- **Lost speech**: outputs with fewer than 70% of the reference's tokens.
- **Latency**: `asrMs` after `--e2e-prepare` (model loaded; it includes lease
  wait and preparation), and stop-to-text as the pipeline's `processingMs`
  (file fixtures have no stop-to-delivery). Each utterance runs in its own
  process, so each is the model's first inference after load.
- **Memory**: peak footprint from `/usr/bin/time -l`. Core ML and Neural Engine
  memory partly lives outside the process, so Whisper and the Core ML Parakeet
  numbers are not comparable with the others.

A failed or empty run counts as a full deletion.

## Results

English (60 utterances, WER):

| Model | Setting | Model output (95% CI) | Delivered | Clean subset (n=48) | Lost speech | asrMs p50 / p90 | Stop-to-text p50 | Peak MB p50 / p95 |
|---|---|---|---|---|---|---|---|---|
| Qwen3-ASR 1.7B | Auto | 3.0% (1.8–4.3) | 3.0% | 3.2% | 0 | 531 / 720 | 570 | 2726 / 3032 |
| Qwen3-ASR 1.7B | en | 3.2% (2.1–4.5) | 3.2% | 3.4% | 0 | 520 / 699 | 554 | 2731 / 3073 |
| **Parakeet TDT v2 (Core ML)** | (n/a) | **3.5% (2.3–4.7)** | 3.5% | 3.7% | 0 | **68 / 86** | **102** | 74 / 78 |
| Whisper v3 Turbo | Auto | 5.1% (3.8–6.5) | 5.1% | 5.0% | 0 | 698 / 1033 | 731 | 228 / 234 |
| Whisper v3 Turbo | en | 5.2% (3.9–6.6) | 5.2% | 5.0% | 0 | 605 / 885 | 636 | 226 / 233 |
| Qwen3-ASR 0.6B | en | 5.3% (3.9–6.8) | 5.3% | 4.7% | 0 | 431 / 570 | 464 | 1564 / 1869 |
| Qwen3-ASR 0.6B | Auto | 5.4% (3.9–6.8) | 5.4% | 5.0% | 0 | 436 / 601 | 472 | 1564 / 1880 |
| Whisper Large v3 | Auto | 5.5% (4.1–7.0) | 5.5% | 4.9% | 0 | 2318 / 3045 | 2346 | 336 / 341 |
| Cohere Transcribe | en | 5.8% (4.2–7.2) | 5.8% | 5.8% | 0 | 660 / 961 | 694 | 2457 / 2556 |
| Whisper Large v3 | en | 5.8% (4.3–7.4) | 5.8% | 5.0% | 0 | 2177 / 2916 | 2204 | 333 / 338 |
| SenseVoice 2024 † | Auto | 7.0% (5.1–8.9) | 7.0% | 7.1% | 0 | 102 / 132 | 136 | 879 / 996 |
| SenseVoice 2024 † | en | 7.2% (5.4–9.3) | 7.2% | 7.4% | 0 | 458 / 491 | 490 | 872 / 976 |
| Parakeet TDT v3 (ONNX) | (n/a) | 9.3% (5.5–14.1) | 9.3% | 9.1% | 2 | 212 / 296 | 245 | 1858 / 1890 |
| SenseVoice (shipped) | en | 31.6% (26.2–37.4) | 31.6% | 28.4% | 1 | 459 / 492 | 492 | 854 / 929 |
| SenseVoice (shipped) | Auto | 32.4% (26.9–38.1) | 32.4% | 29.7% | 1 | 103 / 134 | 136 | 873 / 991 |

Japanese (60 utterances, CER):

| Model | Setting | Model output (95% CI) | Delivered | Clean subset (n=46) | Lost speech | asrMs p50 / p90 | Stop-to-text p50 | Peak MB p50 / p95 |
|---|---|---|---|---|---|---|---|---|
| Cohere Transcribe | ja | 3.8% (2.7–4.8) | 5.7% | 3.0% | 0 | 852 / 1182 | 896 | 2533 / 2673 |
| Qwen3-ASR 1.7B | ja | 4.5% (3.3–5.9) | 6.4% | 4.0% | 0 | 642 / 1452 | 686 | 2968 / 3305 |
| SenseVoice 2024 † | Auto | 5.2% (4.0–6.6) | 7.0% | 4.2% | 0 | 130 / 174 | 174 | 889 / 1011 |
| SenseVoice 2024 † | ja | 5.2% (3.9–6.7) | 7.0% | 4.2% | 0 | 484 / 531 | 528 | 870 / 972 |
| **Qwen3-ASR 1.7B** | **Auto** | **6.2% (4.2–8.8)** | 8.1% | 5.1% | 0 | 640 / 1407 | 684 | 2981 / 3333 |
| Parakeet Japanese (Core ML) | (n/a) | 6.4% (4.1–9.2) | 8.3% | 5.9% | 3 | 64 / 109 | 108 | 59 / 64 |
| Whisper v3 Turbo | Auto | 7.2% (5.3–9.2) | 9.1% | 6.6% | 0 | 940 / 1956 | 992 | 230 / 240 |
| Whisper v3 Turbo | ja | 7.9% (5.8–10.2) | 9.8% | 7.5% | 0 | 866 / 1339 | 918 | 228 / 236 |
| Qwen3-ASR 0.6B | ja | 10.1% (8.2–12.1) | 11.6% | 8.8% | 0 | 532 / 1234 | 584 | 1757 / 2077 |
| Qwen3-ASR 0.6B | Auto | 10.3% (8.2–12.6) | 11.8% | 8.8% | 0 | 529 / 1232 | 572 | 1766 / 2030 |
| Whisper Large v3 | Auto | 10.5% (7.6–13.6) | 12.4% | 9.2% | 0 | 3866 / 7921 | 3918 | 337 / 345 |
| Whisper Large v3 | ja | 11.1% (8.1–14.2) | 13.1% | 9.8% | 0 | 3676 / 5873 | 3726 | 334 / 340 |
| SenseVoice (shipped) | ja | 76.3% (73.9–78.6) | 75.6% | 76.0% | 60 | 471 / 524 | 513 | 847 / 983 |
| SenseVoice (shipped) | Auto | 76.4% (74.0–78.6) | 75.7% | 76.1% | 60 | 127 / 171 | 171 | 877 / 974 |

Korean (60 utterances, CER):

| Model | Setting | Model output (95% CI) | Delivered | Clean subset (n=32) | Lost speech* | asrMs p50 / p90 | Stop-to-text p50 | Peak MB p50 / p95 |
|---|---|---|---|---|---|---|---|---|
| Qwen3-ASR 1.7B | ko | 9.9% (6.1–13.8) | 9.9% | 2.1% | 4 | 737 / 1566 | 774 | 2995 / 3362 |
| Whisper Large v3 | ko | 10.2% (6.7–14.1) | 10.2% | 3.7% | 4 | 2920 / 4338 | 2960 | 333 / 338 |
| Whisper Large v3 | Auto | 10.8% (7.2–14.7) | 10.8% | 4.6% | 4 | 3044 / 4625 | 3083 | 336 / 341 |
| Whisper v3 Turbo | ko | 11.2% (7.6–15.1) | 11.2% | 4.5% | 4 | 732 / 1001 | 771 | 226 / 232 |
| **Qwen3-ASR 1.7B** | **Auto** | **11.6% (7.7–15.8)** | 11.6% | 3.8% | 3 | 730 / 1767 | 767 | 2970 / 3384 |
| Cohere Transcribe | ko | 11.9% (8.2–15.9) | 11.9% | 5.1% | 3 | 890 / 1273 | 932 | 2521 / 2636 |
| Whisper v3 Turbo | Auto | 12.1% (8.4–16.3) | 12.1% | 5.4% | 4 | 822 / 1073 | 860 | 228 / 236 |
| Qwen3-ASR 0.6B | ko | 13.0% (8.9–17.5) | 13.0% | 5.0% | 4 | 601 / 1422 | 642 | 1767 / 2137 |
| SenseVoice 2024 † | Auto | 13.0% (9.0–17.5) | 13.0% | 4.0% | 4 | 122 / 160 | 162 | 880 / 988 |
| Qwen3-ASR 0.6B | Auto | 13.1% (9.3–17.6) | 13.1% | 5.2% | 4 | 591 / 1448 | 629 | 1732 / 2168 |
| SenseVoice 2024 † | ko | 13.2% (9.2–17.8) | 13.2% | 4.1% | 4 | 472 / 517 | 512 | 853 / 953 |
| SenseVoice (shipped) | Auto | 77.4% (74.2–80.5) | 77.4% | 74.1% | 50 | 169 / 665 | 224 | 873 / 951 |
| SenseVoice (shipped) | ko | 77.8% (74.7–80.8) | 77.8% | 75.2% | 50 | 498 / 555 | 542 | 857 / 981 |

\* Except for the shipped SenseVoice, Korean "lost speech" is the same four
references (ko-1814, ko-1817, ko-1877, ko-1902), whose brackets hold text nobody
says; the clean subset excludes them.

Paired differences (`results/summary.json` `decision_pairs`; model output, same utterances; negative = the first-named model has fewer errors):

| Language | Comparison | Δ error (95% CI) |
|---|---|---|
| en | Qwen3-ASR 1.7B Auto − Parakeet TDT v2 | −0.5 pt (−1.5…+0.6) |
| en | Whisper Turbo Auto − Parakeet TDT v2 | +1.6 pt (+0.6…+2.7) |
| ja | Qwen3-ASR 1.7B ja − Qwen3-ASR 1.7B Auto | −1.7 pt (−3.6…−0.2) |
| ja | Parakeet Japanese − Qwen3-ASR 1.7B Auto | +0.2 pt (−3.0…+3.9) |
| ja | Whisper Turbo Auto − Qwen3-ASR 1.7B Auto | +0.9 pt (−1.9…+3.7) |
| ja | Cohere ja − Qwen3-ASR 1.7B ja | −0.8 pt (−1.7…+0.3) |
| ko | Qwen3-ASR 1.7B ko − Qwen3-ASR 1.7B Auto | −1.8 pt (−3.8…−0.2) |
| ko | Whisper Turbo Auto − Qwen3-ASR 1.7B Auto | +0.5 pt (−2.3…+3.2); clean subset +1.6 pt (−2.3…+5.2) |
| ko | Whisper Turbo ko − Qwen3-ASR 1.7B ko | +1.3 pt (−0.2…+2.9); clean subset +2.4 pt (+1.0…+4.0) |
| ko | Cohere ko − Qwen3-ASR 1.7B ko | +2.0 pt (+0.6…+3.7) |
| all | SenseVoice 2024 † − shipped SenseVoice, Auto | en −25 pt, ja −71 pt, ko −64 pt (all CIs exclude 0) |

First load from a new model path (process wall time of the first run minus the
median warm run; Core ML compiles per path): Whisper Turbo 76 s, Whisper Large
v3 22 s, Parakeet TDT v2 13 s, Parakeet Japanese 10 s, Qwen3-ASR under 1 s.

### Findings

- **The shipped SenseVoice is a Cantonese fine-tune and fails outside Chinese.**
  For Japanese it writes only kanji, mostly Simplified, and drops every kana
  (60 of 60 outputs). For Korean it mixes Chinese characters into Hangul, losing
  most of the text in 50 of 60. English WER is 32%, with misspellings such as
  `remaning` and `custmber`. The original SenseVoiceSmall (†) scores 7.0% WER,
  5.2% CER and 13.0% CER (4.0% on the clean Korean subset) at about 120 ms, so the
  problem is the artifact, not the model family. AD-074's Mandarin results used
  the same shipped artifact and still stand.
- **`ChineseScriptConverter` rewrites Japanese kanji.** With the default
  Traditional script, ICU `Hans-Hant` turned 国 into 國, 数 into 數 and 参 into 參
  in 35–42 of 60 delivered Japanese outputs, adding about 2 CER points to every
  model (Delivered against Model output). Converting the FLEURS Japanese
  references alone changes 190 of 321 sentences. AD-083 skips the conversion for
  text that contains kana.
- **Parakeet Japanese drops whole sentences.** In 3 of 60 two-sentence clips
  (9–15 s) it returned only one sentence. On ja-2000 (15.06 s) the 15-second
  window split left a tail of about 0.06 s, decoded alone as `ハッハッハッハッハッハ`;
  `AudioChunker.transcribeAsync` uses `minTailSeconds: 0`. The joined windows are
  also separated by a space, which Japanese does not use.
- **Qwen3-ASR under Auto is weaker than with the explicit language** in Japanese
  and Korean (1.7–1.8 points). Under Auto it sometimes writes a name in Hangul or
  Latin inside Japanese (`ダン디大学`, `Pamela Farragson 教授`).
- English and Auto are indistinguishable for every English model.
- Whisper Large v3 is not better than Turbo in any language and is 3–4× slower.
- Parakeet TDT v3 (sherpa-onnx) returned no text for one English clip
  (en-1872), which the pipeline then discarded.

## Decision

- **English: Parakeet TDT v2 (Core ML), on every Mac.** It is statistically tied
  with Qwen3-ASR 1.7B (3.5% against 3.0% WER, Δ −0.5 pt, CI −1.5…+0.6) and
  better than Whisper Turbo, at 68 ms instead of 530 ms and a 464 MB download.
  It recognizes English only, so Qwen3-ASR 1.7B is the multilingual
  alternative.
- **Japanese and Korean: Qwen3-ASR 1.7B**, with Whisper Large v3 Turbo as the
  lower-memory alternative. Under Auto the three best candidates overlap
  (Qwen3-ASR 1.7B, Parakeet Japanese, Whisper Turbo); Qwen3-ASR has the lowest
  point estimates under Auto, is significantly better than Turbo with an explicit
  Korean setting on the clean subset, lost no sentence, is faster than Turbo and
  has no long first load. It needs about 3 GB of memory.
- **Japanese and Korean on Macs with 8 GB or less: Whisper Large v3 Turbo**, the
  same memory rule as Chinese. It lost no sentence and needs little process
  memory; its first load can take more than a minute. Parakeet Japanese is
  faster and smaller but drops sentences, and the shipped SenseVoice is unusable.
- **The shipped SenseVoice is no longer recommended or shortlisted** for these
  languages. Chinese and all other languages keep their AD-074 rules.

## Caveats

- FLEURS is read Wikipedia text, not dictation: longer sentences, many proper
  nouns and numbers, few fillers or self-corrections. Speaker mix is unknown
  (FLEURS has no speaker IDs); gender is capped at 60%.
- 60 utterances per language give wide CIs; Japanese and Korean candidates under
  Auto are not separable.
- Numbers and kana/kanji spelling are not normalized. Korean references contain
  bracketed glosses; the clean subset is the fairer comparison there.
- One M4 Pro under concurrent builds (load average median 5.9). Lower-memory
  Macs were not measured. Peak memory for Core ML models excludes Neural Engine
  memory outside the process.
- Cohere was not downloaded in this study (APFS clone), so it stays Experimental.

## Reproduce

```sh
APP="$HOME/Library/Developer/Xcode/DerivedData/<airdraft-…>/Build/Products/Debug/Airdraft Debug.app"
W=/tmp/airdraft-wave/ad083
python3 -I eval/eja-asr/prepare_corpus.py --work "$W"
# Models: APFS-clone installed models into $W/models (LocalModels layout), or install with
# "$APP/Contents/MacOS/Airdraft Debug" --e2e-local "$W/sessions/dl" --e2e-action download --e2e-model coreml:parakeet-v2
# and AIRDRAFT_E2E_MODEL_ROOT="$W/models".
python3 -I eval/eja-asr/run_matrix.py --app "$APP" --work "$W"
python3 -I eval/eja-asr/run_matrix.py --app "$APP" --work "$W" --sensevoice-2024   # needs $W/models-sv2024
python3 -I eval/eja-asr/score.py --work "$W"
```

`run_matrix.py` skips runs that already have a result file.
