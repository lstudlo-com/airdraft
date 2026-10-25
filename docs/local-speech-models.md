# Local speech model catalogue

`WhisperModelVariant` owns the seven v3 / distilled Core ML choices. `GGUFModelCatalog`
owns the 69 GGUF variants from the reviewed Handy catalogue and transcribe.cpp
v0.2.4. The bundled resource includes one quantization per variant, exact file
bytes, immutable Hugging Face revision, SHA-256, languages, creator and license.
Models, Profiles and Meetings resolve the same exact entry; unavailable stored
IDs require setup rather than substituting a different model. Rows show the runtime
and quantization, and profile choices include their creator/runtime.

GGUF models load from `LocalModels.root/gguf/<catalogue-id>/`. Installation is an
explicit `ModelDownloader` action. The transaction keeps an incomplete marker
until every byte and digest is verified. A same-size corrupt cache is replaced
only after its replacement is verified. Native inference never accesses the Hub.
Pinned Qwen3-ASR and WhisperKit choices download file by file in manifest order;
besides the same incomplete marker, they count as installed only when every
pinned file is a nonempty regular file, so a download interrupted after the
loader's key files (for example before `generation_config.json`) is not installed.
The runtime is the official, checksum-pinned macOS XCFramework in
`Packages/TranscribeCppKit`; ARM uses its embedded Metal backend and Intel CPU.
No remote Swift package mirror or build-time native source compilation is needed.

The actor loads on a worker, retains its model across cancellation/unload, and
serializes native compute per model. Every session copies borrowed results before
freeing itself. The abort callback bridges task cancellation; an aborted or
truncated prefix is rejected. Audio is cut at quiet points to at most 25 seconds,
or the artifact's smaller hard cap. Exact digital silence skips decode.

Language coverage comes from the exact model, not the runtime family. Canary,
Cohere and multilingual Granite require explicit source language. Monolingual
models accept Auto as their fixed language; joint decoders validate the preference
without sending an ineffective forcing flag. Mandarin, Cantonese and script stay
separate. No competitor scores are presented as Airdraft measurements.

Meetings uses measured segment timing for GGUF and the existing SpeakerKit path
for optional speaker identification. Streaming/diarization/translation in an
upstream model name does not advertise those tasks in dictation.

Source contracts: [transcribe.cpp v0.2.4](https://github.com/handy-computer/transcribe.cpp/tree/v0.2.4),
[official Swift distribution](https://github.com/handy-computer/transcribe.cpp/blob/v0.2.4/bindings/swift/README.md).
Research and verification records belong to the Airdraft vault, under AD-051.

`CoreMLSpeechModelCatalog` adds eight FluidAudio variants: Parakeet v2, v3 INT8,
v3 INT4, Ultra, Redux, Phonon-2, 110M and Japanese. Every required component,
including metadata/vocabulary, is pinned and SHA-256 verified. `AsrModels.loadLocal`
loads only that directory; automatic SDK download/recovery is never invoked.
Redux's encoder uses the upstream CPU/GPU path to avoid its lengthy first ANE
compile; other variants keep the SDK's default compute units.
Decoding uses silence-bound 15-second windows. Cancellation rejects the result
and unloading retains any model still borrowed by an active decoder.

Distil-Whisper variants are English-only, including Auto (resolved to English).
Their `distil-whisper_` folders differ from OpenAI's; all share the v3 tokenizer
and native word timing. Orukeet uses its fixed upstream INT8 archive through the
existing sherpa-onnx transducer, retaining the same European-language limitation.

## Pinned Qwen3-ASR and Whisper downloads

`PinnedHubModelCatalog` reads `local-pinned-models.json`: Qwen3-ASR 1.7B MLX 5-bit
and 0.6B MLX 4-bit, all seven WhisperKit variants, and the shared
`openai/whisper-large-v3` tokenizer files. Each entry has an immutable revision and
every file's byte size and SHA-256. `ModelDownloader` installs them file by file
through `ModelDownloadTransfer`, which checks size and digest before a file enters
the model folder. Qwen no longer uses speech-swift's `fromPretrained` downloader,
which fetched from Hub `main` and loaded the model just to download it. Loading
still calls `fromPretrained(offlineMode: true)`. An ID without a pin is refused.

Existing installs remain valid. `LocalModels` still judges completeness by required
files, without hashing gigabytes at every check. A repeated download keeps each
file that already matches its size and digest. A file with different bytes is
replaced only after verified bytes arrive. Download size labels come from the
manifest bytes (decimal units).

`scripts/pin-hub-models.py` regenerates the manifest. LFS digests come from the
Hub's LFS pointers. Small Git files are downloaded at the pinned revision, checked
against their Git blob IDs and then hashed. `--installed <Models folder>` compares
an existing installation read-only. The 2026-10-22 pins equal Hub `main` on that
date and match the installed copies measured in `eval/mixed-asr/`: Qwen 1.7B
`1645ca9`, Qwen 0.6B `bc441bd`, WhisperKit `0f63a78` (Turbo and tokenizer
compared byte for byte), tokenizer `06f233f`. Other Whisper variants were pinned
from Hub metadata and have not been downloaded. Moving a pin is deliberate:
rerun the script, review the diff and repeat the Qwen3/Whisper self-tests.
Cohere Transcribe and SpeakerKit still download from Hub `main`.

## SenseVoice artifacts

Two sherpa-onnx SenseVoice archives exist, each pinned by URL, exact bytes and
SHA-256 in `SherpaTranscriber.Model` and checked before unpacking:

- **SenseVoice** (`senseVoiceMultilingual`, catalogue `sherpa:senseVoiceMultilingual`,
  engine `sherpa-onnx:senseVoiceMultilingual`): the original FunAudioLLM
  SenseVoiceSmall, `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17`,
  163,002,883 bytes. Mandarin, Cantonese, English, Japanese and Korean.
- **SenseVoice Cantonese** (`senseVoice`, catalogue `sherpa:senseVoice`, engine
  `sherpa-onnx:senseVoice`): `…-int8-2025-09-09`, converted from ASLP-lab WSYue-ASR
  `sensevoice_small_yue`, a Cantonese fine-tune, 165,783,878 bytes. Through 0.11.0
  this was the only SenseVoice, so its raw values, engine ID, folder and Meetings
  `LocalModel` raw value are unchanged: existing app defaults, profile bindings,
  history engine IDs and saved documents keep the same model and files. Its
  language policy offers Cantonese, Mandarin and English; Japanese and Korean are
  rejected with a Models recovery message (AD-083: no kana, CER 76% and 77%).
  It is retired: Models, Profiles, onboarding and Meetings list it only while it
  is in use (app default, profile binding, installed or downloading).

The AD-083 follow-up (`eval/eja-asr/` and `eval/mixed-asr/`, 2026-10-24) measured
both through the app. The fine-tune was under one point better on FLEURS
Cantonese and worse on Mandarin, English, Japanese and Korean. Preparation builds
the SenseVoice recognizer for the language the recording will use
(`SherpaTranscriber.anticipate`), so an explicit language does not rebuild it on
the first dictation and live preview finds it warm; a later language change
still rebuilds it.

Offline decoders split long audio with `AudioChunker`: windows never exceed the
engine's limit, the last window keeps at least 3 s (the previous cut moves
earlier instead), and windows meeting between Han or kana characters are joined
without a space; Latin, Hangul and digits keep one space.

## Recommendations and tiers in Models

`LocalSpeechRecommendation` (Core) picks the first-run model from the primary
system language and physical memory (AD-074). The choice is data:
`LocalSpeechRecommendation.rules` holds one measured rule per language (the
choice above the memory threshold, the choice at or below it, each alternative's
Models label, curated shortlist extras, whether the recommendation measured as
the most accurate, and its evidence); `unmeasuredRule(for:)` is the default for
every other language. Chinese gets Qwen3-ASR 1.7B, with
SenseVoice as the smaller alternative. On 8 GB or less the order reverses.
English gets Parakeet TDT v2 (Core ML) on every Mac, with Qwen3-ASR 1.7B as the
multilingual alternative. Japanese and Korean get Qwen3-ASR 1.7B with Whisper
Large v3 Turbo as the lower-memory alternative; on 8 GB or less the order
reverses. These come from AD-083 (`eval/eja-asr/`, FLEURS read speech).
AD-098 (`eval/intl-asr/`, FLEURS) gives Spanish, French, Portuguese, Russian,
Arabic, Hindi and Indonesian Qwen3-ASR 1.7B. On 8 GB or less, Spanish, French and
Portuguese get Parakeet TDT v3 (Core ML), Russian GigaAM v3 E2E RNN-T (GGUF) and
Arabic and Indonesian Whisper Large v3 Turbo, each with Qwen3-ASR as the
alternative; Hindi keeps Qwen3-ASR on every Mac because every Whisper model
doubled its errors. Models that need an explicit speech language (Canary,
Cohere, Cohere Transcribe Arabic) are never first-run choices. Other languages
get Whisper Large v3 Turbo, with Parakeet TDT v3 (European languages) and Whisper
Large v3 in Models. Qwen3-ASR 0.6B is
never the lighter default because it can loop until its token cap and spike
memory. Onboarding's Speech step and the Models table use the same rule; each
onboarding choice shows its download size and a one-line trade-off that depends
on the label its rule gives it; "Most accurate for <language> in Airdraft's tests"
appears only where the rule records that measurement.

By default the local table shows a compact set (AD-071): "Recommended for your
language" lists `LocalModelShortlist` for the system language and memory (the
`LocalSpeechRecommendation` model first, then at most two curated Verified
alternatives that differ by size, speed or language reach), followed by "Your
models": the app default, the active profile's speech model, installed models and
running downloads the set does not already show. "Show All Models (N)" below the
table reveals the full list with the provider filter and is remembered in
`AppSettings.showsAllLocalModels` (key `models.showsAllLocalModels`, outside the
`settings.` keys). The compact set shows all of its rows without an inner scroll
unless it exceeds six rows. Searching always searches the whole catalogue,
including language names.
The full list opens with the same "Recommended for your language" rows, then
Verified and built-in models, then a collapsed "Experimental models (N)"
disclosure. Searching includes Experimental rows without a click. While collapsed,
the group still lists the Experimental models the user relies on, so a selected
or downloaded model never disappears behind the disclosure. Each row shows one
strength label (the recommendation reason or the alternative's role, such as
"Smaller and faster", "Uses less memory" or "More accurate, uses more memory";
Qwen3-ASR 1.7B elsewhere shows "Best for mixed Chinese and English"), then the tier as a symbol and word, the languages by full name (the
user's language and English first, up to two names and a count) and runtime
tags. The tooltip lists every supported language. `ModelCatalogue.verificationEvidence` lists the Verified
IDs with their sources: the 18 choices that were actually downloaded, loaded and
used for transcription in the 2026-10-12 local coverage verification, plus
SenseVoice Cantonese, FireRedASR2, Qwen3-ASR 1.7B/0.6B and Whisper Large v3 Turbo from
`eval/mixed-asr/`; Parakeet TDT v2, Parakeet Japanese and Whisper Large v3 now
cite `eval/eja-asr/`, where they were downloaded and measured again, and the
multilingual SenseVoice cites the 2026-10-24 follow-up in both studies, and
GigaAM v3 E2E RNN-T cites `eval/intl-asr/`. Promote a model only with the same kind of evidence. The
`models-performance` fixture rejects IDs that are not in the catalogue and
shortlist models that are not Verified. Renders accept
`AIRDRAFT_RENDER_SYSTEM_LANGUAGE`, `AIRDRAFT_RENDER_MEMORY_GB`,
`AIRDRAFT_RENDER_SHOW_ALL_MODELS=1` and `AIRDRAFT_RENDER_SHOW_EXPERIMENTAL=1`
(which also shows all models).
