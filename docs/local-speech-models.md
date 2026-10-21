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

## Recommendations and tiers in Models

`LocalSpeechRecommendation` (Core) picks the first-run model from the primary
system language and physical memory (AD-074). Chinese gets Qwen3-ASR 1.7B, with
SenseVoice as the smaller alternative. On 8 GB or less the order reverses.
English, Japanese and Korean get SenseVoice; other languages get Whisper Large v3
Turbo. Qwen3-ASR 0.6B is never the lighter default because it can loop until its
token cap and spike memory. Onboarding's Speech step and the Models table use the
same rule.

The local table opens with "Recommended for your language", then Verified and
built-in models, then a collapsed "Experimental models (N)" disclosure (AD-071).
Searching includes Experimental rows without a click. Rows show the tier as a
symbol and word before their tags; Qwen3-ASR 1.7B also shows "Best for mixed
Chinese and English". `ModelCatalogue.verificationEvidence` lists the Verified
IDs with their sources: the 18 choices that were actually downloaded, loaded and
used for transcription in the 2026-10-12 local coverage verification, plus
SenseVoice, FireRedASR2, Qwen3-ASR 1.7B/0.6B and Whisper Large v3 Turbo from
`eval/mixed-asr/`. Promote a model only with the same kind of evidence. The
`models-performance` fixture rejects IDs that are not in the catalogue. Renders accept
`AIRDRAFT_RENDER_SYSTEM_LANGUAGE`, `AIRDRAFT_RENDER_MEMORY_GB` and
`AIRDRAFT_RENDER_SHOW_EXPERIMENTAL=1`.
