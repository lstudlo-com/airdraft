# Airdraft

Personal, macOS-only voice dictation with LLM refinement. Hold a hotkey, speak,
release; polished text lands at your cursor in whatever app is frontmost.

Both engines are pluggable and switchable at runtime in Settings:

| Stage | Local | Remote |
|---|---|---|
| Speech recognition | Qwen3-ASR 1.7B / 0.6B (MLX), FireRedASR2-AED and SenseVoice-small (sherpa-onnx), Cohere Transcribe 2B (MLX), Whisper Large v3 Turbo (Core ML), Apple SpeechAnalyzer (macOS 26) | Soniox v5, Groq Whisper v3 Turbo, ElevenLabs Scribe v2, OpenAI GPT-Transcribe, Deepgram Nova-3 |
| Refinement | LM Studio / Ollama / llama-server / any OpenAI-compatible server; Claude Code and Codex CLIs on your own subscription | OpenAI, Anthropic, Google Gemini, OpenRouter — each through its own native API and key |

The LLM is best-effort: a timeout or error inserts the raw transcript instead of blocking.

## App

Menu-bar app with a Superwhisper-style main window (Home, Profiles, Vocabulary,
Configuration, Models, History). Hold **⌃ ⌥** (Control + Option, default) to dictate; the
recording pill appears at the bottom centre of the screen.

- Shortcuts: key combinations register through Carbon and need no permission.
  Modifier-only keys (Right ⌥, fn) use a CGEventTap and need Accessibility.
- Models: the Models page downloads every local model anonymously into
  `~/Library/Application Support/Transcribar/Models/`; local engines load only from there.
  Nothing needs to be typed.
- Profiles: every LLM behaviour is an editable, resettable profile.
- CLI refinement: model lists come from the installed Codex or Claude Code CLI,
  including resolved Claude model IDs and hidden Codex entries. Refresh after a
  CLI update; the pencil button accepts any other supported model ID or alias.
  Thinking effort sits beside the model and lists that model's supported levels,
  including Extra high and Max where available. A saved unsupported level
  uses the nearest lower supported level; Off uses the minimum when required.

Local model research is recorded in `docs/model-atlas.html`. The five current cloud APIs, their purposes, pricing and contracts are documented in [Cloud transcription](docs/transcription-apis.md).

## Pipeline

```
hotkey ▸ record 16 kHz ▸ ASR ▸ context (app, cursor text, selection)
       ▸ LLM refine (mode + app family + dictionary) ▸ dictionary post-pass
       ▸ insert (Accessibility, else paste) ▸ SQLite history
```

Modes: `clean` (default), `concise`, `summary`, `verbatim` (no LLM).
Selected text turns the utterance into an edit instruction for that text.

## Requirements

- macOS 15+, Apple Silicon (Qwen3-ASR runs on MLX). Xcode 16+ with the Metal
  toolchain (built with Xcode 26). On the first Xcode build, accept the
  "Trust & Enable" prompt for the mlx-swift build plug-in.
- `brew install xcodegen`
- For local refinement: LM Studio with the server running (`lms server start`)
  and a model loaded, or Ollama.

## Build

The repository uses [moon](https://moonrepo.dev/docs/setup-workspace) as a small
task runner around Xcode. Install [proto](https://moonrepo.dev/docs/proto/install)
once, then run these commands from the repository root:

```sh
proto install                # installs pinned moon, Node, and pnpm
moon run airdraft:prepare     # once after cloning: prepare native speech libraries
moon run airdraft:build       # regenerates the Xcode project, then builds
moon run airdraft:test        # regenerates the project, then runs core tests
```

`moon tasks` lists the native and marketing tasks. `.moon/workspace.yml` maps
`airdraft` to the repository root and `marketing` to `apps/marketing`;
each project's `moon.yml` defines its commands and dependencies. Xcode keeps
its own incremental build cache in DerivedData. Moon caching is disabled for
these tasks because the signed products live outside the repository; build
and test also share a mutex so they cannot write to that build tree concurrently.

### Microphone selection

Choose a microphone from the window toolbar, menu bar, or Configuration →
Microphone. Your choice becomes Airdraft's saved default. System default follows
macOS; a specific device stays selected across restarts and reconnects. If it is
unavailable, reconnect it or choose another input. Airdraft never silently
substitutes another microphone. Finish dictation before switching devices.

### App updates

Airdraft uses Sparkle for **Check for Updates…**, daily background checks, and
optional automatic downloads that install on quit. These controls are in
Configuration → Updates. Releases use a signed GitHub-hosted update feed; it
is published with each release. Run `moon run airdraft:release-setup` once on the
release Mac. Every push to `origin/main` then tests committed sources, builds the
DMG locally, and uploads a draft. GitHub publishes it after the push succeeds.

See [the update release procedure](docs/updates.md) for signing keys, Release
builds, DMG packaging, and validation without a paid Apple developer membership.

### Marketing website

The Astro website lives in [`apps/marketing`](apps/marketing/README.md), initialized
from Cloudflare's official Astro Framework Starter and served as static assets by
Cloudflare Workers. It shares this Git repository and one pnpm workspace/lockfile;
the native app retains its existing Xcode and Swift package layout.

```sh
pnpm install
pnpm dev:marketing            # http://localhost:4321
pnpm check:marketing          # types and formatting
pnpm build:marketing          # static production build
pnpm preview:marketing        # build + local Cloudflare runtime
```

Website commands do not run Xcode. The website README documents the original C3
command, local preview, production URL setting, and Cloudflare monorepo deployment.
The GitHub workflow validates the website without publishing it.
The private preview is deployed at [airdraft.app](https://airdraft.app), protected
by Cloudflare Access using the existing L Studio Google login and owner allowlist.

### Direct Xcode commands

Direct Xcode commands remain available:

```sh
scripts/make-sherpa-xcframeworks.sh   # once: repackages sherpa-onnx + onnxruntime static libs
xcodegen generate          # regenerates airdraft.xcodeproj from project.yml
open airdraft.xcodeproj     # pick your team under Signing, then Run
```

Command line (uses Xcode's own DerivedData, so there is one build tree):

```sh
xcodebuild -project airdraft.xcodeproj -scheme airdraft -configuration Debug -skipPackagePluginValidation -skipMacroValidation build
xcodebuild -project airdraft.xcodeproj -scheme airdraft -configuration Debug -skipPackagePluginValidation -skipMacroValidation test   # AirdraftCoreTests
```

### Xcode Canvas previews

Open `HomePage.swift` or `HomeHero.swift` with the `airdraft` scheme and Debug
configuration, then show the Canvas. Keep **Editor → Canvas → Use Legacy Previews
Execution** off. Legacy preview builds can miss the installed Metal toolchain
required by MLX on Xcode 27.

`AirdraftCore` is a dynamic library, keeping the engine dependencies and native
Sherpa archives out of the preview linker. This avoids duplicate native symbols
and slow preview launches. Preview declarations use sample data from
`Debug/PreviewData.swift`.

## Headless harness

`airdraft-cli` runs the same engines without the app, for evaluation and debugging
(`eval/*.py` call it). It builds a separate SwiftPM tree in `Packages/AirdraftCore/.build`
(~6 GB, git-ignored); delete it when you are done evaluating.

```sh
cd Packages/AirdraftCore && swift build --product airdraft-cli
.build/debug/airdraft-cli refine "嗯 那個 我們今天要討論三件事 第一 專案進度 第二 預算問題" --family workChat
.build/debug/airdraft-cli run clip.wav --sensevoice --dict "Floze=flows,flow's"
.build/debug/airdraft-cli prompt --mode summary --family email      # print the exact prompt
```

Speech: `--whisper [VARIANT]` (default), `--qwen3 [ID]`, `--cohere [ID]`, `--sensevoice`, `--firered`,
`--apple [LOCALE]`, `--elevenlabs [MODEL]`, or `--url/--model` for an OpenAI-compatible API.
Refinement: `--llm-url/--llm-model`, `--mode clean|concise|summary`,
`--family email|workChat|personalChat|document|code|terminal|general`, `--script traditional|simplified|auto`.
Context: `--app`, `--window`, `--page-url`, `--before`, `--after`, `--selected` (edit mode), `--recent "a||b"`.
Keys: set `AIRDRAFT_ASR_KEY` and `AIRDRAFT_LLM_KEY` rather than passing `--key`/`--llm-key`,
which other processes and your shell history can see.

## Verification without a GUI

Renders and self-tests exist only in Debug builds; Release builds ignore these
arguments and variables.

```sh
APP=$(xcodebuild -project airdraft.xcodeproj -scheme airdraft -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/airdraft.app/Contents/MacOS/airdraft
$APP --render-hud out.png                 # HUD in recording / processing / error states
$APP --render-window all ./render         # every page, dark and light, as PNG
AIRDRAFT_SELFTEST=clip.wav AIRDRAFT_SELFTEST_ASR=senseVoice $APP   # any ASRProviderKind raw value[:model]
AIRDRAFT_SELFTEST=mic $APP                     # 3 s from the microphone
AIRDRAFT_SELFTEST=lifecycle $APP               # load/unload speech + LLM, quit must unload
AIRDRAFT_SELFTEST=window $APP                  # open window = regular app with menu bar; close = menu-bar only
/usr/bin/log show --last 5m --predicate 'subsystem == "com.lightiichen.airdraft"' --style compact
```

The self-test drives the real pipeline (HUD, engines, dictionary, history) and
skips only the final insertion. Logs are at notice level so `log show` sees them.

CLI integration checks are opt-in. The wire harness sends requests to a local
test server, checks that refinement instructions replace coding instructions,
and rejects any tool schemas. It does not use paid inference:

```sh
TEST_RUNNER_AIRDRAFT_TEST_INSTALLED_CLIS=1 \
TEST_RUNNER_AIRDRAFT_CLI_WIRE_HARNESS="$PWD/scripts/verify-cli-requests.py" \
xcodebuild -project airdraft.xcodeproj -scheme airdraft -configuration Debug -skipPackagePluginValidation -skipMacroValidation test
```

Add `TEST_RUNNER_AIRDRAFT_TEST_LIVE_CLI=1` to also run one real cleanup through
each signed-in CLI. For isolated UI renders, set `AIRDRAFT_RENDER_LLM=codex` or
`claudeCode`, optionally `AIRDRAFT_RENDER_MODEL` and `AIRDRAFT_RENDER_EFFORT`,
then run `--render-window all <dir> 1800`.

Claude calls use `--system-prompt`, `--tools ""`, `--safe-mode`, `--restricted`
and `--strict-mcp-config`; authentication stays enabled. Codex uses a temporary
`model_instructions_file` and a model catalogue configured without tools, plus
disabled skills, plugins, hooks, and environment/coding context. The installed
Codex 0.153.4 still adds the user's global `AGENTS.md` despite
`project_doc_max_bytes=0`; its built-in coding prompt and tool schemas are removed.
The app does not alter the user's global CLI files or login.
Codex Ultra and Claude Ultracode orchestrate workflows rather than selecting
single-call thinking effort, so tool-free dictation does not offer them.

## Known issues

- **`swift build` cannot run MLX.** The Metal library is only compiled by Xcode, so
  `airdraft-cli` built with `swift build` fails with "Failed to load the default metallib"
  when using `--qwen3`. Use the app self-test (`AIRDRAFT_SELFTEST_ASR=qwen3:<modelId>`)
  or build the CLI scheme with `xcodebuild`.
- **Signing must be stable for Accessibility to stick.** Ad-hoc builds get a
  cdhash-based code requirement, so every rebuild invalidates the grant even though
  the toggle stays on. `project.yml` pins `DEVELOPMENT_TEAM`; after changing signing
  run `tccutil reset Accessibility com.lstudlo.app.airdraft` and grant once more.
- **Stale Hugging Face tokens.** A revoked `HF_TOKEN` or `~/.cache/huggingface/token`
  turns public Hub downloads into 401s. The app's downloader never sends a token, so this
  only affects other tools.
- **Reasoning models think for seconds.** Gemma 4 / Qwen3 in LM Studio spend
  10 to 60 s reasoning before a one-line cleanup. The refiner sends
  `reasoning_effort: "none"` (and `chat_template_kwargs.enable_thinking=false`) and
  retries without them on a 400, so keep "Disable model thinking" on.
- **Whisper defaults to Simplified Chinese.** Models ▸ Speech options ▸ Chinese script
  (default 繁體) biases the Whisper prompt, instructs the LLM to use Taiwan
  vocabulary, and runs an ICU character conversion as a last pass.

## First run

1. Grant Microphone when prompted.
2. Grant Accessibility (System Settings ▸ Privacy & Security ▸ Accessibility).
   Needed to insert text and read context. Re-grant after re-signing the app.
3. Models: download a speech model (Qwen3-ASR 1.7B for mixed Chinese and English).
   The first dictation after a download compiles the model for the Neural Engine and
   can take a minute; the pill shows "Loading model".
4. Models ▸ Refinement: preset "LM Studio (local)", pick the model from the list
   (`lms server start` first). Press "Test".
5. Hold ⌃ ⌥ (Control + Option, default), speak, release. Change the key under Configuration ▸
   Keyboard Shortcuts ▸ "Record shortcut" and press the key or combination. A modifier
   on its own (Right ⌥, fn) also works but needs Accessibility; for fn set System
   Settings ▸ Keyboard ▸ "Press 🌐 key to" to "Do Nothing".

## Layout

```
project.yml                     XcodeGen spec (app target, test scheme, Info.plist, entitlements)
.moon/workspace.yml              moon workspace, one Airdraft project
moon.yml                        prepare, generate, build and test tasks
.prototools                      pinned moon version
Sources/App/
  App/          AirdraftApp, AppContainer (object graph), ModelLifecycle (what is in memory)
  Hotkeys/      HotkeyService ▸ CarbonHotkey (combos) or EventTapHotkey (modifier-only)
  HUD/          Recording pill
  Views/        One file per page, ModelCatalogue, RefinementSettings (provider tiles), Theme
  Debug/        Offscreen renders, self-tests
  Assets.xcassets/AppIcon.appiconset   generated by scripts/render-app-icon.swift
Packages/AirdraftCore/               Engine-agnostic core (SwiftPM)
  Sources/AirdraftCore/
    Audio/        AudioRecorder (16 kHz mono), AudioChunker, WAVEncoder, AudioFile
    ASR/          Local engines, five cloud APIs and custom endpoint support
    LLM/          Refiner protocol, PromptBuilder, profiles, LM Studio control,
                  OpenAI-compatible / Anthropic / Gemini / CLI (Claude Code, Codex) refiners
    Providers/    Configs and presets, EngineFactory, LocalModels, ModelDownloader, Keychain
    Context/      AppContext, AppFamily, AppContextReader (Accessibility)
    Insertion/    TextInserter (AX, paste fallback with clipboard restore)
    Dictionary/   DictionaryStore (JSON), DictionaryPostProcessor, ChineseScriptConverter
    History/      HistoryStore (GRDB / SQLite)
    Pipeline/     DictationPipeline (state machine)
    Settings/     AppSettings (UserDefaults; secrets in Keychain), Hotkey
  Sources/airdraft-cli/
  Tests/AirdraftCoreTests/
Packages/SherpaOnnxKit/         Link-only wrapper around the repackaged sherpa-onnx static libraries
eval/                           Prompt correction eval, LLM benchmarks, results
```

Data lives in `~/Library/Application Support/Transcribar/` (`history.sqlite`,
`dictionary.json`). API keys are stored in the login Keychain under the
service `com.lstudlo.app.airdraft`.

The app bundle identifier and Keychain service are `com.lstudlo.app.airdraft`.
Legacy preferences and API keys migrate from `com.lightiichen.transcribar`; the
data directory stays in place for existing models and history. macOS requires
new Microphone and Accessibility grants after the identifier changes. The project, scheme and app are `airdraft`; the Swift module is `AirdraftCore`.
Logs use `com.lightiichen.airdraft`, and self-tests use `AIRDRAFT_SELFTEST` and
`AIRDRAFT_SELFTEST_ASR`. Evaluation fixtures retain their original sample text.

## Adding a provider

Implement `Transcriber` or `Refiner`, add a case to `ASRProviderKind` /
`LLMProviderKind`, wire it in `EngineFactory`, and add a preset in
`EndpointPreset`. Nothing else needs to change.

## Roadmap

- Streaming preview while speaking (WhisperKit streaming API)
- Auto-learn dictionary entries from user edits after insertion
- Apple Foundation Models refiner (macOS 26)
- Native Anthropic Messages API refiner
- LoRA fine-tune of a small local model on own history (raw ▸ final pairs)
