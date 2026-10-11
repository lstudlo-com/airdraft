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
