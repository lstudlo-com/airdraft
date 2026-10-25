# AD-098: local speech models for seven more system languages

Question: which local speech model should first-run setup and Models recommend
to a user whose system language is Spanish, French, Portuguese, Russian, Arabic,
Hindi or Indonesian? Through 0.13.0 all seven got Whisper Large v3 Turbo, the
unmeasured default, with no alternative.

Measured 2026-10-25 from source commit `5161b58` (`claude/intl-all-phases`) on an
Apple M4 Pro (48 GB, macOS 27.0.1). `results/environment.json` lists the
hardware, artifacts and digests; `results/summary.json` and
`results/utterances.csv` hold every score and output.

## Method

Same route, normalization and statistics as `eval/eja-asr` (AD-083), so the
numbers are comparable with its English, Japanese and Korean tables.

**Route.** Each utterance runs once through the Debug app's production pipeline,
`LocalE2E --e2e-action transcribe --e2e-prepare`, with one `--e2e-local` data
directory per configuration and `AIRDRAFT_E2E_MODEL_ROOT=<work>/models`.
Refinement and app context are off, insertion is disabled and the dictionary is
empty. Each language runs as a user of that system language (`-AppleLanguages
(es-419|fr-FR|pt-BR|ru-RU|ar-EG|hi-IN|id-ID)`), which sets the output guards'
expected languages. Utterances form the outer loop and configurations the inner
loop. Nothing opened a microphone, a window, the Keychain or real preferences.

**Settings.** Every local model whose `SpeechLanguagePolicy` supports the
language, with the explicit language; Whisper and Qwen3-ASR also under Auto.
Models whose language setting is not applied (Parakeet, Orukeet, GigaAM,
Moonshine, Fun-ASR, Voxtral) run once and are shown as "(n/a)". Cohere, Canary,
Granite and Cohere Transcribe Arabic have no Auto.

**Models.** Qwen3-ASR 1.7B, Whisper Large v3 Turbo, Parakeet TDT v3 (Core ML) and
Cohere Transcribe are APFS clones of the user's installed copies; their files
match `local-pinned-models.json` and `local-coreml-models.json`. Whisper Large v3,
Orukeet and the GGUF models (Canary 1B v2, GigaAM v3 CTC and E2E RNN-T, Cohere
Transcribe Arabic, Moonshine Base Arabic, Fun-ASR Nano Multilingual, Voxtral Mini
4B Realtime, Granite Speech 4.1 2B) were installed with the app's hash-verified
`--e2e-action download`; each GGUF file equals its catalogue SHA-256.

**Not run.** Apple Speech (needs OS language assets). Qwen3-ASR 0.6B (never a
recommendation, AD-074). The Parakeet TDT v3 ONNX build (`sherpa:parakeet`, the
same model as the Core ML build, weaker in AD-083) and the Parakeet v3 variants
(INT4, Ultra, Redux). GGUF copies of models already run natively (Qwen3-ASR,
Whisper, Parakeet v3, Cohere). Whisper Medium/Small/Base/Tiny (smaller versions
of Whisper, which already lost to Qwen3-ASR). Nemotron Streaming 3.5 (its policy
lists none of these languages). Voxtral Small 24B (17 GB). Granite 4.1 2B NAR
and Plus and Granite 4.0 1B (one Granite variant was enough to place the family).
Moonshine Tiny Arabic (Base was run). Canary 1B v2 has no Arabic, Hindi or
Indonesian; Cohere has no Russian, Hindi or Indonesian.

**Corpus** (`manifest.json`, built by `prepare_corpus.py`; audio stays under the
work directory). [Google FLEURS](https://huggingface.co/datasets/google/fleurs)
test split (Conneau et al., SLT 2022; CC BY 4.0) for `es_419`, `fr_fr`, `pt_br`,
`ru_ru`, `ar_eg`, `hi_in` and `id_id`, Hub revision `70bb2e8` (the AD-083
revision), parquet digests checked. Per language: recordings of 2–20 s; one
recording per sentence; sentences ordered by SHA-256 of `lang/id`; the first 40,
at most 60% of one gender. The `pt_br`, `ar_eg` and `id_id` test splits carry a
single gender value, so the cap cannot apply there and is lifted (recorded in the
manifest). FLEURS publishes no speaker IDs. 40 utterances per language, 3,140 s
of audio (es 468 s, fr 402, pt 483, ru 462, ar 437, hi 445, id 445). The
references are the cased, punctuated `raw_transcription`. The manifest
reproduces them under CC BY 4.0 with this attribution. `ar_eg` is Egyptian
speakers reading Modern Standard Arabic text.

**Normalization** (`score.py`, identical for reference and hypothesis): NFKC;
lowercase; Arabic tashkeel (U+064B–U+065F), superscript alef and tatweel removed;
Hindi nukta removed after NFKC decomposes the precomposed nukta letters;
apostrophes dropped; every other Unicode punctuation or symbol becomes a space
(danda and Arabic comma included). All seven languages are scored as **WER** over
whitespace words. Numbers are not converted, and alef/hamza spellings are not
unified.

**Metrics.** As AD-083: model output after Airdraft's output guards (the
delivered text was identical for every configuration here); 95% CIs from 2000
bootstrap resamples of utterances (seed 98), paired deltas on the same
utterances; clean subset = references with no digit and no bracket; lost speech
= outputs with under 70% of the reference's words; a failed or empty run counts
as a full deletion. **RTF** = `asrMs` / audio duration (median), after
`--e2e-prepare` loaded the model. **Memory** = peak footprint from
`/usr/bin/time -l`, classed light (< 1 GB), medium (1–2 GB), large (2–4 GB),
very large (≥ 4 GB) at p95; Core ML (Whisper, Parakeet) memory partly lives
outside the process, so their class is a lower bound.

## Results

Spanish (es_419), 40 utterances, WER:

| Model | Setting | WER (95% CI) | Clean subset (n) | Failed / lost | asrMs p50 / p90 | RTF p50 | Peak MB p50 / p95 | Memory |
|---|---|---|---|---|---|---|---|---|
| Voxtral Mini 4B Realtime (GGUF) | (n/a) | 1.5% (0.7–2.5) | 1.2% (30) | 0 / 0 | 2880 / 3922 | 0.256 | 4879 / 4897 | very large |
| Qwen3-ASR 1.7B | auto | 1.7% (1.1–2.4) | 1.5% (30) | 0 / 0 | 714 / 1547 | 0.065 | 2923 / 3267 | large |
| Canary 1B v2 (GGUF) | es | 1.9% (1.0–2.9) | 1.3% (30) | 0 / 0 | 209 / 285 | 0.018 | 1024 / 1030 | medium |
| Qwen3-ASR 1.7B | es | 2.0% (1.3–2.7) | 1.9% (30) | 0 / 0 | 716 / 1575 | 0.066 | 2952 / 3301 | large |
| Whisper Large v3 | es | 2.5% (1.6–3.6) | 2.1% (30) | 0 / 0 | 3013 / 4573 | 0.269 | 337 / 340 | light |
| Orukeet | (n/a) | 2.8% (1.7–4.0) | 2.1% (30) | 0 / 0 | 204 / 292 | 0.018 | 1912 / 1963 | medium |
| Whisper Large v3 | auto | 2.8% (1.7–4.0) | 2.3% (30) | 0 / 0 | 3158 / 5484 | 0.284 | 336 / 341 | light |
| Parakeet TDT v3 (Core ML) | (n/a) | 2.9% (1.8–4.1) | 2.5% (30) | 0 / 0 | 121 / 183 | 0.011 | 60 / 66 | light |
| Cohere Transcribe | es | 3.0% (1.8–4.3) | 2.3% (30) | 0 / 0 | 930 / 1275 | 0.080 | 2514 / 2637 | large |
| Whisper v3 Turbo | es | 3.6% (2.2–5.5) | 2.9% (30) | 0 / 0 | 769 / 1272 | 0.073 | 229 / 235 | light |
| Whisper v3 Turbo | auto | 4.3% (2.7–6.2) | 3.5% (30) | 0 / 0 | 865 / 2027 | 0.084 | 230 / 237 | light |
| Granite Speech 4.1 2B (GGUF) | es | 4.7% (2.8–7.0) | 2.3% (30) | 0 / 0 | 638 / 889 | 0.056 | 2592 / 2602 | large |

French (fr_fr), 40 utterances, WER:

| Model | Setting | WER (95% CI) | Clean subset (n) | Failed / lost | asrMs p50 / p90 | RTF p50 | Peak MB p50 / p95 | Memory |
|---|---|---|---|---|---|---|---|---|
| Qwen3-ASR 1.7B | fr | 5.8% (3.5–8.2) | 4.7% (30) | 0 / 0 | 700 / 1113 | 0.076 | 2888 / 3250 | large |
| Qwen3-ASR 1.7B | auto | 6.0% (3.7–8.4) | 5.0% (30) | 0 / 0 | 704 / 1101 | 0.075 | 2898 / 3244 | large |
| Canary 1B v2 (GGUF) | fr | 6.8% (4.0–10.4) | 4.9% (30) | 0 / 0 | 212 / 288 | 0.021 | 1021 / 1029 | medium |
| Cohere Transcribe | fr | 6.9% (4.0–10.5) | 4.0% (30) | 0 / 0 | 900 / 1300 | 0.097 | 2485 / 2608 | large |
| Parakeet TDT v3 (Core ML) | (n/a) | 7.3% (5.0–10.0) | 6.3% (30) | 0 / 0 | 96 / 138 | 0.010 | 59 / 64 | light |
| Whisper Large v3 | auto | 8.2% (5.6–11.0) | 6.6% (30) | 0 / 0 | 3244 / 4729 | 0.345 | 336 / 340 | light |
| Granite Speech 4.1 2B (GGUF) | fr | 8.5% (5.3–12.2) | 5.1% (30) | 0 / 0 | 648 / 875 | 0.066 | 2590 / 2599 | large |
| Voxtral Mini 4B Realtime (GGUF) | (n/a) | 8.5% (5.5–11.9) | 6.0% (30) | 0 / 0 | 2646 / 3608 | 0.265 | 4873 / 4890 | very large |
| Whisper Large v3 | fr | 9.0% (5.9–12.6) | 7.8% (30) | 0 / 0 | 2977 / 4425 | 0.331 | 336 / 340 | light |
| Whisper v3 Turbo | auto | 9.1% (6.2–12.3) | 7.4% (30) | 0 / 0 | 867 / 1452 | 0.094 | 230 / 235 | light |
| Whisper v3 Turbo | fr | 10.4% (7.0–14.1) | 8.1% (30) | 0 / 0 | 798 / 1341 | 0.085 | 227 / 234 | light |
| Orukeet | (n/a) | 11.2% (7.2–15.4) | 8.1% (30) | 0 / 0 | 188 / 292 | 0.018 | 1896 / 1952 | medium |

Portuguese, Brazil (pt_br), 40 utterances, WER:

| Model | Setting | WER (95% CI) | Clean subset (n) | Failed / lost | asrMs p50 / p90 | RTF p50 | Peak MB p50 / p95 | Memory |
|---|---|---|---|---|---|---|---|---|
| Voxtral Mini 4B Realtime (GGUF) | (n/a) | 3.9% (2.6–5.3) | 3.5% (28) | 0 / 0 | 2840 / 4152 | 0.252 | 4878 / 4901 | very large |
| Canary 1B v2 (GGUF) | pt | 4.4% (2.9–6.0) | 3.4% (28) | 0 / 0 | 200 / 287 | 0.018 | 1023 / 1033 | medium |
| Qwen3-ASR 1.7B | auto | 4.8% (3.3–6.4) | 4.0% (28) | 0 / 0 | 680 / 1564 | 0.064 | 2891 / 3283 | large |
| Qwen3-ASR 1.7B | pt | 5.0% (3.3–6.9) | 4.4% (28) | 0 / 0 | 687 / 1564 | 0.063 | 2893 / 3322 | large |
| Parakeet TDT v3 (Core ML) | (n/a) | 5.8% (3.8–7.8) | 4.0% (28) | 0 / 0 | 89 / 151 | 0.009 | 60 / 66 | light |
| Whisper v3 Turbo | auto | 5.9% (4.0–8.0) | 4.7% (28) | 0 / 0 | 820 / 1968 | 0.082 | 229 / 236 | light |
| Whisper v3 Turbo | pt | 5.9% (4.1–7.8) | 4.5% (28) | 0 / 0 | 750 / 1269 | 0.070 | 230 / 237 | light |
| Cohere Transcribe | pt | 6.2% (4.2–8.5) | 3.5% (28) | 0 / 0 | 824 / 1142 | 0.072 | 2511 / 2679 | large |
| Whisper Large v3 | pt | 6.2% (4.1–8.9) | 3.9% (28) | 0 / 0 | 2710 / 5295 | 0.254 | 336 / 341 | light |
| Whisper Large v3 | auto | 6.4% (4.3–9.1) | 4.2% (28) | 0 / 0 | 2890 / 5910 | 0.271 | 336 / 341 | light |
| Orukeet | (n/a) | 6.5% (4.3–9.1) | 4.0% (28) | 0 / 0 | 206 / 316 | 0.018 | 1915 / 1980 | medium |
| Granite Speech 4.1 2B (GGUF) | pt | 11.9% (8.4–15.7) | 6.5% (28) | 0 / 0 | 608 / 841 | 0.052 | 2592 / 2601 | large |
| Fun-ASR Nano Multilingual (GGUF) | (n/a) | 35.6% (29.0–43.3) | 36.9% (28) | 1 / 2 | 309 / 452 | 0.027 | 1612 / 1616 | medium |

Russian (ru_ru), 40 utterances, WER:

| Model | Setting | WER (95% CI) | Clean subset (n) | Failed / lost | asrMs p50 / p90 | RTF p50 | Peak MB p50 / p95 | Memory |
|---|---|---|---|---|---|---|---|---|
| Qwen3-ASR 1.7B | auto | 5.8% (3.6–8.1) | 4.6% (30) | 0 / 0 | 808 / 1404 | 0.073 | 3015 / 3551 | large |
| Voxtral Mini 4B Realtime (GGUF) | (n/a) | 5.9% (4.0–8.0) | 4.6% (30) | 0 / 0 | 2966 / 3814 | 0.264 | 4878 / 4905 | very large |
| Qwen3-ASR 1.7B | ru | 5.9% (3.8–8.2) | 4.6% (30) | 0 / 0 | 804 / 1425 | 0.074 | 2982 / 3440 | large |
| GigaAM v3 E2E RNN-T (GGUF) | (n/a) | 6.4% (3.9–9.3) | 3.8% (30) | 0 / 0 | 62 / 78 | 0.005 | 428 / 432 | light |
| Whisper Large v3 | auto | 8.1% (5.7–11.1) | 6.9% (30) | 0 / 0 | 3677 / 5375 | 0.337 | 336 / 339 | light |
| Parakeet TDT v3 (Core ML) | (n/a) | 8.2% (5.6–11.4) | 6.5% (30) | 0 / 0 | 96 / 139 | 0.009 | 60 / 65 | light |
| GigaAM v3 CTC (GGUF) | (n/a) | 8.2% (4.9–12.1) | 3.8% (30) | 0 / 0 | 58 / 78 | 0.005 | 417 / 419 | light |
| Whisper Large v3 | ru | 8.3% (5.9–11.4) | 7.2% (30) | 0 / 0 | 3538 / 5048 | 0.310 | 336 / 341 | light |
| Canary 1B v2 (GGUF) | ru | 8.9% (6.1–12.4) | 6.0% (30) | 0 / 0 | 218 / 288 | 0.019 | 1023 / 1032 | medium |
| Whisper v3 Turbo | auto | 10.0% (7.2–13.3) | 8.4% (30) | 0 / 0 | 952 / 1916 | 0.100 | 229 / 234 | light |
| Whisper v3 Turbo | ru | 10.3% (7.5–13.4) | 8.8% (30) | 0 / 0 | 863 / 1320 | 0.086 | 229 / 235 | light |
| Orukeet | (n/a) | 10.9% (7.8–14.5) | 8.4% (30) | 0 / 0 | 202 / 282 | 0.018 | 1915 / 1987 | medium |

Arabic (ar_eg), 40 utterances, WER:

| Model | Setting | WER (95% CI) | Clean subset (n) | Failed / lost | asrMs p50 / p90 | RTF p50 | Peak MB p50 / p95 | Memory |
|---|---|---|---|---|---|---|---|---|
| Cohere Transcribe Arabic (GGUF) | ar | 6.0% (3.1–9.1) | 4.7% (32) | 0 / 0 | 305 / 424 | 0.029 | 1925 / 1931 | medium |
| Cohere Transcribe | ar | 10.2% (6.4–14.2) | 10.1% (32) | 0 / 0 | 1094 / 1610 | 0.106 | 2493 / 2649 | large |
| Qwen3-ASR 1.7B | auto | 10.8% (7.7–13.8) | 10.0% (32) | 0 / 0 | 690 / 1439 | 0.066 | 2846 / 3241 | large |
| Qwen3-ASR 1.7B | ar | 11.5% (8.3–14.6) | 10.9% (32) | 0 / 0 | 669 / 1499 | 0.067 | 2840 / 3287 | large |
| Voxtral Mini 4B Realtime (GGUF) | (n/a) | 11.7% (8.8–14.9) | 10.9% (32) | 0 / 0 | 2644 / 3661 | 0.252 | 4876 / 4897 | very large |
| Whisper Large v3 | auto | 11.7% (8.5–15.3) | 11.6% (32) | 0 / 0 | 3768 / 7537 | 0.382 | 337 / 342 | light |
| Whisper Large v3 | ar | 12.0% (9.0–15.3) | 12.0% (32) | 0 / 0 | 3514 / 5711 | 0.366 | 337 / 341 | light |
| Whisper v3 Turbo | auto | 14.2% (10.6–18.5) | 14.1% (32) | 0 / 0 | 1082 / 2022 | 0.099 | 231 / 237 | light |
| Whisper v3 Turbo | ar | 15.1% (11.4–19.0) | 15.4% (32) | 0 / 0 | 954 / 1573 | 0.089 | 228 / 236 | light |
| Moonshine Base Arabic (GGUF) | (n/a) | 15.8% (12.3–19.7) | 15.6% (32) | 0 / 0 | 362 / 590 | 0.037 | 280 / 292 | light |
| Fun-ASR Nano Multilingual (GGUF) | (n/a) | 22.6% (18.3–27.3) | 21.9% (32) | 0 / 0 | 310 / 416 | 0.029 | 1613 / 1615 | medium |

Hindi (hi_in), 40 utterances, WER:

| Model | Setting | WER (95% CI) | Clean subset (n) | Failed / lost | asrMs p50 / p90 | RTF p50 | Peak MB p50 / p95 | Memory |
|---|---|---|---|---|---|---|---|---|
| Qwen3-ASR 1.7B | hi | 17.8% (12.7–23.5) | 16.8% (33) | 0 / 0 | 1559 / 3482 | 0.159 | 3331 / 4096 | very large |
| Qwen3-ASR 1.7B | auto | 18.8% (13.0–25.1) | 17.9% (33) | 0 / 0 | 1500 / 3266 | 0.159 | 3275 / 4064 | large |
| Voxtral Mini 4B Realtime (GGUF) | (n/a) | 24.1% (19.6–29.3) | 23.4% (33) | 1 / 1 | 3038 / 4157 | 0.275 | 4875 / 4906 | very large |
| Whisper v3 Turbo | hi | 32.4% (28.1–37.3) | 32.7% (33) | 0 / 0 | 1406 / 8593 | 0.169 | 229 / 234 | light |
| Whisper Large v3 | auto | 32.9% (27.3–38.6) | 34.1% (33) | 0 / 3 | 8456 / 46523 | 0.909 | 338 / 411 | light |
| Whisper v3 Turbo | auto | 34.3% (29.9–39.6) | 34.9% (33) | 0 / 0 | 1938 / 9412 | 0.254 | 231 / 239 | light |
| Whisper Large v3 | hi | 34.4% (27.6–42.1) | 35.1% (33) | 1 / 2 | 6828 / 52383 | 0.742 | 337 / 341 | light |
| Fun-ASR Nano Multilingual (GGUF) | (n/a) | 54.6% (42.0–67.5) | 52.9% (33) | 1 / 7 | 481 / 866 | 0.052 | 1613 / 1615 | medium |

Indonesian (id_id), 40 utterances, WER:

| Model | Setting | WER (95% CI) | Clean subset (n) | Failed / lost | asrMs p50 / p90 | RTF p50 | Peak MB p50 / p95 | Memory |
|---|---|---|---|---|---|---|---|---|
| Qwen3-ASR 1.7B | id | 5.1% (2.6–8.3) | 4.2% (33) | 0 / 0 | 654 / 1555 | 0.064 | 2802 / 3253 | large |
| Qwen3-ASR 1.7B | auto | 5.2% (2.8–8.4) | 4.4% (33) | 0 / 0 | 662 / 1575 | 0.063 | 2831 / 3257 | large |
| Whisper Large v3 | auto | 7.5% (4.4–11.4) | 6.7% (33) | 0 / 0 | 3168 / 7187 | 0.312 | 336 / 340 | light |
| Whisper v3 Turbo | id | 7.8% (4.9–11.1) | 7.4% (33) | 0 / 0 | 751 / 1372 | 0.080 | 228 / 236 | light |
| Whisper Large v3 | id | 7.9% (5.4–11.0) | 7.4% (33) | 0 / 0 | 3062 / 4939 | 0.288 | 336 / 341 | light |
| Whisper v3 Turbo | auto | 7.9% (5.1–11.2) | 7.6% (33) | 0 / 0 | 850 / 2046 | 0.093 | 229 / 235 | light |
| Fun-ASR Nano Multilingual (GGUF) | (n/a) | 8.2% (5.1–12.0) | 6.9% (33) | 0 / 1 | 295 / 413 | 0.028 | 1611 / 1614 | medium |

Failed runs (counted as full deletions): Whisper Large v3 `hi` on hi-1896
(19.4 s; the pipeline returned to idle with no text after 44 s) and Voxtral on
hi-1939 (same outcome); Fun-ASR Nano on hi-1896 and pt-1955 (decoder hit its
generation cap; Airdraft rejected the truncated output).

Paired differences (`results/summary.json` `decision_pairs`; model output, same
utterances; second minus first, negative = the second model has fewer errors):

| Language | First → second | Δ WER (95% CI) | Clean subset |
|---|---|---|---|
| es | Qwen3-ASR Auto → Whisper Turbo Auto | +2.6 pt (+1.2…+4.6) | +2.0 pt (+0.9…+3.2) |
| fr | Qwen3-ASR Auto → Whisper Turbo Auto | +3.1 pt (+0.9…+5.4) | +2.4 pt (−0.1…+5.2) |
| pt | Qwen3-ASR Auto → Whisper Turbo Auto | +1.1 pt (−0.5…+2.6) | +0.7 pt (−1.3…+2.4) |
| ru | Qwen3-ASR Auto → Whisper Turbo Auto | +4.2 pt (+1.6…+6.8) | +3.8 pt (+1.0…+6.5) |
| ar | Qwen3-ASR Auto → Whisper Turbo Auto | +3.5 pt (+0.3…+7.2) | +4.2 pt (+0.6…+8.5) |
| hi | Qwen3-ASR Auto → Whisper Turbo Auto | +15.5 pt (+9.5…+21.2) | +17.0 pt (+10.4…+23.2) |
| id | Qwen3-ASR Auto → Whisper Turbo Auto | +2.7 pt (+0.3…+5.0) | +3.3 pt (+1.2…+5.4) |
| es | Qwen3-ASR Auto → Parakeet TDT v3 | +1.2 pt (+0.1…+2.5) | +1.1 pt (−0.1…+2.4) |
| fr | Qwen3-ASR Auto → Parakeet TDT v3 | +1.3 pt (−0.7…+3.5) | +1.3 pt (−0.9…+3.5) |
| pt | Qwen3-ASR Auto → Parakeet TDT v3 | +1.0 pt (−0.8…+2.7) | 0.0 pt (−1.6…+1.6) |
| es | Whisper Turbo Auto → Parakeet TDT v3 | −1.4 pt (−3.4…+0.4) | −0.9 pt (−2.4…+0.6) |
| fr | Whisper Turbo Auto → Parakeet TDT v3 | −1.8 pt (−4.0…+0.2) | −1.1 pt (−3.5…+1.1) |
| pt | Whisper Turbo Auto → Parakeet TDT v3 | −0.1 pt (−2.2…+1.8) | −0.7 pt (−2.6…+1.5) |
| ru | Qwen3-ASR Auto → GigaAM v3 E2E RNN-T | +0.6 pt (−1.9…+3.3) | −0.9 pt (−3.0…+1.3) |
| ru | GigaAM v3 E2E RNN-T → Parakeet TDT v3 | +1.8 pt (−0.3…+3.9) | +2.8 pt (+0.8…+4.7) |
| ru | GigaAM v3 E2E RNN-T → Whisper Turbo Auto | +3.6 pt (+1.4…+5.9) | +4.6 pt (+2.3…+7.2) |
| ar | Qwen3-ASR Auto → Cohere Transcribe Arabic (ar) | −4.8 pt (−6.8…−2.7) | −5.3 pt (−7.4…−3.2) |
| ar | Whisper Turbo Auto → Whisper Large v3 Auto | −2.5 pt (−4.3…−0.9) | −2.5 pt (−4.8…−0.5) |
| ar | Whisper Turbo Auto → Moonshine Base Arabic | +1.5 pt (−1.6…+5.1) | +1.5 pt (−2.1…+5.7) |
| es | Qwen3-ASR Auto → Voxtral Mini 4B | −0.2 pt (−1.0…+0.8) | −0.3 pt (−0.9…+0.4) |
| pt | Qwen3-ASR Auto → Voxtral Mini 4B | −0.9 pt (−2.2…+0.2) | −0.5 pt (−2.0…+0.7) |
| pt | Qwen3-ASR Auto → Canary 1B v2 (pt) | −0.3 pt (−1.8…+1.3) | −0.7 pt (−2.1…+0.6) |
| hi | Qwen3-ASR Auto → Voxtral Mini 4B | +5.3 pt (−0.3…+10.6) | +5.5 pt (−0.5…+11.3) |
| id | Whisper Turbo Auto → Fun-ASR Nano | +0.3 pt (−2.6…+3.2) | −0.7 pt (−3.8…+2.5) |

Qwen3-ASR under Auto against the explicit language differed by at most about one
point in every language, with every CI touching or including zero (Japanese and
Korean in AD-083 lost 1.7–1.8 points under Auto; these seven do not).

First load from a new model path (wall time of the first run minus the median):
Whisper Turbo 77 s, Whisper Large v3 26 s, Parakeet TDT v3 14 s, every GGUF and
MLX model under 3 s.

### Findings

- **Qwen3-ASR 1.7B is the best or tied-best model that detects the language,
  in all seven languages**, and is significantly better than Whisper Large v3
  Turbo in six (all but Portuguese). It needs about 3 GB (Hindi p95 4.0 GB).
- **Hindi: every Whisper model is unusable** (WER 32–34%, twice Qwen3-ASR's
  18–19%), with occasional output in another script and a 52 s p90 for
  Whisper Large v3. Voxtral Mini 4B (24%) and Fun-ASR (55%, wrong script in 17
  of 40) are also worse. No light model was acceptable.
- **Parakeet TDT v3 (Core ML) is the light choice for Spanish, French and
  Portuguese**: within 1.0–1.3 points of Qwen3-ASR, slightly ahead of Turbo, at
  RTF 0.01 (about 100 ms) and about 60 MB of process memory. For Russian it is
  2.4 points behind Qwen3-ASR.
- **GigaAM v3 E2E RNN-T is the light choice for Russian**: tied with Qwen3-ASR
  (6.4% against 5.8%; clean subset 3.8% against 4.6%) at 60 ms, 430 MB and a
  274 MB download, and better than Parakeet TDT v3 and Turbo. It recognizes
  Russian only. Its CTC sibling is 1.8 points worse.
- **Arabic: Cohere Transcribe Arabic (GGUF) is clearly best** (6.0% against
  10.8% for Qwen3-ASR, −4.8 pt, CI excludes 0) at 300 ms and 1.9 GB, but it needs
  an explicit speech language. Among Auto-capable models Qwen3-ASR leads;
  Whisper Large v3 beats Turbo by 2.5 points but is about 3.5 times slower.
- **Indonesian** follows the Japanese/Korean pattern: Qwen3-ASR 5.2%, Whisper
  Large v3 7.5%, Turbo 7.9%, Fun-ASR 8.2%.
- **Explicit-language models tie or win in Romance languages**: Canary 1B v2
  (GGUF) 1.9% es, 6.8% fr, 4.4% pt at RTF 0.02 and 1 GB, but 8.9% ru; Cohere
  Transcribe is tied but slower and larger. Neither works under Auto.
- **Voxtral Mini 4B** ties Qwen3-ASR in es/pt/ru/ar at 4.9 GB, RTF 0.26 and a
  3.3 GB download; not a reasonable default.
- **Granite Speech 4.1 2B** is worse than Qwen3-ASR in es/fr/pt (+2.5 to
  +7.2 pt). **Orukeet** is worse than Parakeet TDT v3 except in Spanish and uses
  1.9 GB. **Moonshine Base Arabic** is close to Turbo (+1.5 pt, n.s.) at 77 MB.

## Decision

Implemented as data in `LocalSpeechRecommendation.rules` (shared by onboarding
and the Models shortlist):

| Language | Above 8 GB (alternative) | 8 GB or less (alternative) | Models extra | "Most accurate" copy |
|---|---|---|---|---|
| es, fr, pt | Qwen3-ASR 1.7B (Parakeet TDT v3, "Smaller and faster") | Parakeet TDT v3 (Qwen3-ASR, "More accurate") | none | fr only |
| ru | Qwen3-ASR 1.7B (GigaAM v3 E2E RNN-T, "Uses less memory") | GigaAM v3 E2E RNN-T (Qwen3-ASR) | Parakeet TDT v3, "More languages" | yes |
| ar | Qwen3-ASR 1.7B (Whisper Turbo, "Uses less memory") | Whisper Turbo (Qwen3-ASR) | Whisper Large v3, "Full-size" (above 8 GB) | no |
| id | Qwen3-ASR 1.7B (Whisper Turbo) | Whisper Turbo (Qwen3-ASR) | none | yes |
| hi | Qwen3-ASR 1.7B (Whisper Turbo) on every Mac | same | none | yes |

- Models needing an explicit speech language (Canary, Cohere, Cohere Transcribe
  Arabic) are not first-run choices: a new install's language is Auto and
  onboarding would block on a language error.
- "Most accurate for <language> in Airdraft's tests" appears only where the
  recommendation had the lowest measured error of every model run: not for
  Spanish (Voxtral 1.5%), Portuguese (Canary 4.4%, Voxtral 3.9%) or Arabic
  (Cohere Transcribe Arabic). Those show Qwen3-ASR's catalogue note instead.
- GigaAM v3 E2E RNN-T becomes Verified (downloaded, loaded and measured here).
- Hindi keeps Qwen3-ASR on 8 GB Macs because the lighter models doubled the
  errors; it uses about 3.3 GB (p95 4.0 GB).
- Every other language keeps the documented default: Whisper Large v3 Turbo,
  with Parakeet TDT v3 and Whisper Large v3 in Models for European languages.

## Caveats

- FLEURS is read Wikipedia text, not dictation. Speaker mix is unknown; `pt_br`,
  `ar_eg` and `id_id` have a single gender value, so their results may not
  generalize across voices.
- 40 utterances per language give wide CIs; several alternatives are statistically
  tied with the recommendation, which also holds for AD-083's Japanese/Korean
  "More accurate" copy.
- One M4 Pro under concurrent builds (load average median 4.1, p90 10.7).
  Lower-memory Macs were not measured; the 8 GB choices are judged by measured
  process memory, which excludes Core ML/Neural Engine memory.
- Numbers and Arabic alef/hamza spelling are not normalized.
- Qwen3-ASR, Whisper Turbo, Parakeet TDT v3 and Cohere were APFS clones, not
  downloaded in this study (their tiers come from earlier evidence).

## Reproduce

```sh
APP="$HOME/Library/Developer/Xcode/DerivedData/<airdraft-…>/Build/Products/Debug/Airdraft Debug.app"
W=dist/intl-asr-work
python3 -I eval/intl-asr/prepare_corpus.py --work "$W"
# Models: APFS-clone installed models into $W/models (LocalModels layout), or install with
# "$APP/Contents/MacOS/Airdraft Debug" --e2e-local "$W/sessions/dl" --e2e-action download --e2e-model gguf:canary-1b-v2
# and AIRDRAFT_E2E_MODEL_ROOT="$PWD/$W/models".
python3 -I eval/intl-asr/run_matrix.py --app "$APP" --work "$W"            # phase 1: about 2.3 h
python3 -I eval/intl-asr/run_matrix.py --app "$APP" --work "$W" --phase 2  # Voxtral and Granite: about 40 min
python3 -I eval/intl-asr/score.py --work "$W"
```

`run_matrix.py` skips runs that already have a result file and configurations
whose model is not installed.
