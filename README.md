# Airdraft

Airdraft is a macOS menu-bar dictation app. Hold a shortcut, speak and release:
Airdraft transcribes your speech, optionally cleans it up with a language model
and inserts the text at the cursor in the app you are using.

Speech recognition and refinement are chosen independently. Each can run on your
Mac or use a cloud service with your own API key. If refinement fails or times
out, Airdraft inserts the raw transcript instead of losing your dictation.

The interface is available in English, Spanish, Japanese, Simplified Chinese and
Traditional Chinese (Taiwan). It follows your macOS language unless you choose one
in Settings > Appearance > Language.

## Features

- **Dictation anywhere.** Hold-to-talk or toggle shortcuts, an optional hold
  delay, a recording window with several visual styles, and verified insertion
  at the cursor. When an app does not accept the text, it stays on the clipboard
  with a recovery notice.
- **Local speech models.** Whisper (WhisperKit, Core ML), Parakeet (sherpa-onnx
  and Core ML), Qwen3-ASR and Cohere Transcribe (MLX), SenseVoice and FireRedASR2
  (sherpa-onnx), GGUF models through transcribe.cpp, and Apple SpeechAnalyzer on
  macOS 26. **Models** opens with a short recommendation for your language and
  Mac, with every model one click away; models download only when you choose them.
- **Cloud speech services.** Soniox, Groq, ElevenLabs, OpenAI, Deepgram,
  AssemblyAI, Cartesia, Speechmatics, xAI, Mistral, Google Gemini and OpenRouter,
  each through its own transcription API, plus any OpenAI-compatible server.
- **Refinement.** Apple Intelligence (on-device, macOS 26), LM Studio, Ollama,
  llama-server or any OpenAI-compatible server, the Claude Code and Codex CLIs on
  your own subscription, and OpenAI, Anthropic, Google Gemini, OpenRouter,
  Groq and Cerebras with your own key.
- **Profiles.** Every refinement behavior is an editable profile that can be
  reset to its defaults. A profile can also choose its own speech model, and
  optional rules pick a profile by the app you dictate into.
- **Vocabulary.** Custom terms and replacements applied to every dictation. Your
  spellings can also guide on-device models that support it (Qwen3-ASR,
  Parakeet and Orukeet).
- **Live text.** Optionally see words while you speak, from Apple Speech or the
  selected local model (Parakeet, SenseVoice or Orukeet). The final transcript
  is unchanged.
- **History.** Searchable local history, optional saved recordings with playback
  and retranscription, and recovery for failed dictations.
- **Transcribe.** Record one app's audio or all apps' audio, with your microphone
  if you like (calls, interviews, lectures), or import audio and video files,
  then transcribe locally or in the cloud with speaker labels, remembered
  speaker names, transcript versions and summaries in several formats (brief
  summary, action items, decisions, minutes).
- **Automation.** Start, stop and cancel dictation from Apple Shortcuts, or send
  the final text to your own script instead of the cursor.

Data stays on your Mac unless you choose a cloud provider. API keys are stored in
the macOS Keychain.

## Editions

Airdraft is free software under the [GNU General Public License v3.0 only](LICENSE).

- **Built from source (free).** Every feature is unlocked and nothing expires.
  Self-built copies update from source; they do not install official builds.
- **Official builds.** The maintainer publishes signed builds on
  [GitHub Releases](https://github.com/lstudlo-com/airdraft/releases) with
  automatic updates. Official builds offer a full-feature trial followed by a
  paid license. Licenses are not on sale yet.

Builds from source never send usage data or crash reports. Official builds ask
once whether to share anonymous usage counts and crash reports, send nothing
unless you agree and never include your words, audio or app content; change the
choice in Settings > Behavior. See [docs/telemetry.md](docs/telemetry.md) and the
[privacy page](https://airdraft.app/privacy/#app-telemetry).

Official builds are signed with the maintainer's Apple Development certificate
and are **not notarized**. On first launch macOS may ask you to approve the app in
System Settings > Privacy & Security.

## Requirements

- An Apple Silicon Mac with macOS 15 or later. Apple SpeechAnalyzer, Apple
  Intelligence refinement and Apple Speech live text require macOS 26.
- Microphone access, and Accessibility access to insert text at the cursor.
- For local refinement: LM Studio, Ollama or another OpenAI-compatible server,
  or Apple Intelligence on a supported Mac.

## Build from source

You need Xcode 27 or later with its Metal toolchain, Python 3.12 or later and
Git. Node.js and pnpm are optional (see below).

```sh
git clone https://github.com/lstudlo-com/airdraft.git
cd airdraft

# Once: install the Metal toolchain if Xcode does not have it yet.
xcodebuild -showComponent MetalToolchain | grep -q 'Status: installed' \
  || xcodebuild -downloadComponent MetalToolchain

# Once: download and verify the pinned sherpa-onnx and ONNX Runtime libraries.
bash scripts/make-sherpa-xcframeworks.sh

# Generate the Xcode project. Without Homebrew's XcodeGen (brew install xcodegen),
# --install-xcodegen downloads the pinned, checksum-verified release into dist/tools.
python3 scripts/generate-project.py --install-xcodegen

# Build the Debug app.
xcodebuild -project airdraft.xcodeproj -scheme airdraft -configuration Debug \
  -skipPackagePluginValidation -skipMacroValidation \
  -packageAuthorizationProvider netrc -onlyUsePackageVersionsFromResolvedFile build
```

The first build resolves Swift packages and compiles MLX, so it takes a while.
Open the result with:

```sh
open "$(xcodebuild -project airdraft.xcodeproj -scheme airdraft -configuration Debug \
  -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/Airdraft Debug.app"
```

The Debug app is named **Airdraft Debug** and uses its own bundle identifier, so
it does not replace an installed official build. You can also open
`airdraft.xcodeproj` in Xcode and run the `airdraft` scheme.

### Code signing

Builds from source are signed to run locally (ad-hoc) and need no Apple
developer account. macOS ties Microphone and Accessibility permissions to the
code signature, and an ad-hoc signature changes with every build, so you may need
to grant Accessibility again after rebuilding. To keep permissions, sign with
your own team (a free personal team works):

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then set DEVELOPMENT_TEAM
python3 scripts/generate-project.py
```

`Config/Local.xcconfig` is ignored by Git. Release builds never use it.
Ad-hoc builds are for development only: they run without Hardened Runtime,
because its library validation rejects frameworks that carry no Team ID.
Team-signed builds and releases keep Hardened Runtime.

### Tests

```sh
python3 scripts/test-local-e2e.py
```

This runs the credential-free regression suite: no API keys or cloud services
are used. See [CONTRIBUTING.md](CONTRIBUTING.md) for the other checks.

### Optional: moon and pnpm

The repository uses [moon](https://moonrepo.dev) as a small task runner around
the same commands. With Node.js 24 and pnpm 10 (or [proto](https://moonrepo.dev/proto)
and `proto install`), run `pnpm install` once, then:

```sh
pnpm build:app      # moon run airdraft:build: regenerates the project and builds
pnpm test:local     # moon run airdraft:test-local: the credential-free suite
```

## First run

1. Follow the setup guide, or open **Models** and download a speech model.
2. Grant Microphone access when asked, and Accessibility access in System
   Settings > Privacy & Security > Accessibility.
3. Hold Control and Option (the default shortcut), speak, and release. Change the
   shortcut in Settings > Keyboard shortcuts.
4. Optionally choose a refinement provider in **Models** > Refinement.

App data lives in `~/Library/Application Support/Transcribar/`. The folder keeps
the app's earlier name so existing models and history stay in place.

## Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md): how to contribute, tests and pull requests
- [docs/development.md](docs/development.md): architecture rules, interface
  conventions and the localization workflow
- [SECURITY.md](SECURITY.md): reporting a vulnerability
- [docs/](docs/): design and implementation notes, for example
  [cloud transcription](docs/transcription-apis.md),
  [local speech models](docs/local-speech-models.md),
  [meeting recording](docs/meeting-recording.md),
  [automation](docs/automation.md) and [updates and releases](docs/updates.md)
- `apps/marketing`: the source of the website at airdraft.app, currently a
  private preview

## License

Unless a file states otherwise, Airdraft's code, documentation and assets are
licensed under [GPL-3.0-only](LICENSE): GPL version 3, without the "or later"
option. Third-party components keep their own licenses. The app lists them under
Settings > Updates > Acknowledgements; the bundled file,
`Sources/App/Resources/Acknowledgements.txt`, is generated by
`scripts/acknowledgements.py`. Speech and language models you download are not
part of Airdraft and keep their own licenses.
