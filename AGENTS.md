# Airdraft

Personal macOS menu-bar dictation app: speech ▸ LLM refinement ▸ insert at cursor.
Not a Printage company repository; the workspace `dev-guidelines` skill does not apply here.

## Product goals

`docs/PRODUCT.md` lists the goals the mature app must meet (quality UI, independent
local/remote engines, preset-driven setup, editable and resettable refinement
profiles). Read it before touching UI, settings, or prompt handling, and keep its
status table current.

## Structure

- Moon is a small task runner around the existing Xcode layout. `.prototools` pins
  moon; `.moon/workspace.yml` maps one `airdraft` project; `moon.yml` defines
  `prepare` (once after clone), `generate`, `build`, and `test`. Use
  `moon run airdraft:build` / `moon run airdraft:test` for routine validation.
  Keep Xcode tasks uncached in moon and serialized by the shared mutex.
- `project.yml` is the source of truth for the Xcode project. After changing it run
  `xcodegen generate`. `airdraft.xcodeproj` is generated and git-ignored.
- `Packages/AirdraftCore` holds all engine-agnostic logic and is the only place with tests.
  Run the tests (see Validation) before finishing any change there.
- `Sources/App` is the SwiftUI shell: `App/` (entry point, `AppContainer`, `ModelLifecycle`),
  `Hotkeys/`, `HUD/`, `Views/` (one file per page, shared components in `Theme.swift`),
  `Debug/` (offscreen renders, self-tests).
- The app icon is code: edit `scripts/render-app-icon.swift` (neumorphic bar with a waveform
  ending in a text caret) and run `swift scripts/render-app-icon.swift` from the repo root; it
  rewrites every PNG in `Sources/App/Assets.xcassets/AppIcon.appiconset`. Do not hand-edit the PNGs.

## Rules

- Interface consistency is a product requirement. Native section cards must have
  equal top, bottom, leading and trailing insets: `Theme.cardPadding` (16 pt).
  Use `PageSection` and `SettingsCard` for settings sections, including Configuration
  and Models. The card owns the outer padding; rows inside it must not add another
  vertical inset. Use shared spacing tokens instead of page-specific values.
  Read the interface consistency rules in `docs/PRODUCT.md` and inspect light/dark
  renders, including lower sections. For a released UI fix, verify the app built
  from the committed release sources, not only the dirty workspace.
- Both stages are provider-agnostic. New engines implement `Transcriber` or `Refiner`,
  get a `*ProviderKind` case, and are wired in `EngineFactory`. Never hard-code a provider
  in the pipeline or views.
- `ASRConfig.engineID` must equal the `id` of the transcriber `EngineFactory` builds for it
  (`EngineFactoryTests` checks this); the UI looks up load state by it.
- Local engines load only from `LocalModels` folders and never download on their own.
  Downloads go through `ModelDownloader` (Models page). The Models table is data in
  `ModelCatalogue`; installed, loaded, download and delete all derive from each entry's `select`.
- Refinement providers are native, not shims: `LLMProviderKind` carries the endpoint, Keychain
  key ref, default model and `wire` (OpenAI chat, Anthropic messages, Gemini generateContent),
  and `EngineFactory.refiner` switches on the wire. A new provider is a new case plus, for a new
  wire, a `Refiner` and a request-shape test in `RefinerWireTests` (a wrong field name otherwise
  only shows up as a 400 mid-dictation). Cloud keys live under `llm.<provider>` in the Keychain.
- Every provider speaks a different contract; the differences that have bitten us are:
  OpenAI-compatible (`Authorization: Bearer`, system as `messages[0]`, `reasoning_effort`),
  Anthropic (`x-api-key` + `anthropic-version`, top-level `system`, required `max_tokens`,
  `output_config.effort`, and **no `temperature`**: Claude 4.7+ reject it with a 400),
  Gemini (`x-goog-api-key`, `systemInstruction`, `generationConfig.thinkingConfig`).
  Every refiner retries a 400 once with a minimal, spec-core body, so a provider that rejects
  an optional field costs a little latency instead of the user's dictation. Keep that fallback.
- `ThinkingEffort` is one setting mapped per provider (`reasoning_effort`, `output_config.effort`,
  `thinkingBudget`, `--effort`, `model_reasoning_effort`). Cleanup needs none; `off` is the default.
- Subscription CLIs (Claude Code, Codex) are refinement providers too: `CLIRefiner` runs them
  non-interactively in a temp directory. Keep Claude Code's `--tools ""  --restricted
  --strict-mcp-config --disable-slash-commands`: without them the CLI ships its tool schemas,
  skills and user settings on every call (15k tokens of subscription usage instead of ~400).
  `--bare` is not an option: it disables OAuth, which is the whole point.
  Claude Code is started while the user is still speaking (`CLIWarmPool`, streaming stdin), which
  hides its ~1.3 s session setup behind recording and ASR. Codex `exec` has no streaming input and
  always runs cold.
- The LLM is best-effort. Any change to `DictationPipeline` must keep the fallback:
  LLM error or timeout still inserts the raw transcript.
- `DictionaryPostProcessor.apply` runs last, after the LLM. Do not move it.
- Secrets go in `Keychain` (service `com.lstudlo.app.airdraft`), never in UserDefaults,
  files, or logs.
- The bundle ID and Keychain service are `com.lstudlo.app.airdraft`. Import legacy
  `com.lightiichen.transcribar` preferences and credentials without overwriting current
  values. Keep `Application Support/Transcribar` for existing models and history.
- Swift language mode is 5 on a Swift 6 compiler; keep `@MainActor` on UI-facing
  classes and `Sendable` on protocol types.
- Prompt changes bump `PromptBuilder.version` so history records stay comparable, and must be
  scored with `eval/run_correction_eval.py` on both `correction_cases.json` and the held-out
  `holdout_cases.json` (LM Studio running). Do not ship a prompt that loses a held-out case.
- Quitting must go through `ModelLifecycle.shutdown()` (unloads speech engines and the LM Studio
  instances the app used). Never return `.terminateLater` from the app delegate: it deadlocks.
- LLM behaviours are `RefinementProfile`s in `ProfileStore`, never hard-coded modes.
  Built-ins have stable ids and must stay resettable to `RefinementProfile.defaults`.
- Setup stays preset-driven: providers come from `EndpointPreset`, models from
  `ModelCatalog`. Do not add UI that requires typing a prompt to get a good result.

## Local releases

Run `moon run airdraft:release-setup` once per release Mac. The installed pre-push
hook builds committed sources locally for every origin/main push. The GitHub
workflow publishes the verified draft after the push succeeds. See `docs/updates.md`.

## Validation

- Tests: `xcodebuild -project airdraft.xcodeproj -scheme airdraft -configuration Debug -skipPackagePluginValidation -skipMacroValidation test`
  (runs `AirdraftCoreTests` inside the app's DerivedData). `cd Packages/AirdraftCore && swift test` also
  works but builds a second ~6 GB tree in `Packages/AirdraftCore/.build`.
- Build: the same command with `build`. Do not pass `-derivedDataPath`: a build tree inside the
  repo duplicates Xcode's and is how the repo grew to 10 GB.
- UI: `airdraft --render-window all <dir>` and `--render-hud <png>`, then look at the PNGs.
- Pipeline: launch with `AIRDRAFT_SELFTEST=<wav>` (or `mic`, `lifecycle`, `window`), optionally
  `AIRDRAFT_SELFTEST_ASR=<ASRProviderKind raw value>[:model]` (e.g. `senseVoice`, `qwen3:<id>`), and read
  `/usr/bin/log show --predicate 'subsystem == "com.lightiichen.airdraft"'`.
  Synthetic key events and screenshots from this shell do not work (no Accessibility /
  Screen Recording); do not rely on them. The user presses the real shortcut.
- Use `/usr/bin/log`, not `log`: zsh has a `log` builtin.
- `AVAudioEngineConfigurationChange` is not proof of a disconnected microphone:
  output changes can trigger it too. Check the actual input route and format,
  recover the same input without clearing captured samples, and leave the Core
  Audio notification queue before engine operations. The microphone self-test
  must check interruption callbacks and resumed capture, not sample count alone.
- Keep `DEVELOPMENT_TEAM` in `project.yml`; ad-hoc signing breaks Accessibility on every rebuild.
- MLX (Qwen3-ASR, Cohere) only works in Xcode-built products; `swift build` has no Metal library.
- sherpa-onnx (FireRedASR2, SenseVoice) is linked through `Packages/SherpaOnnxKit`, whose
  `Vendor/` xcframeworks are generated by `scripts/make-sherpa-xcframeworks.sh` (run once after
  clone; git-ignored). Do not depend on the upstream sherpa-onnx package directly: its static
  `.framework` bundles get embedded by Xcode and break code signing. `SherpaTranscriber` calls
  the C API directly; do not re-add the 2,300-line upstream Swift wrapper.
- speech-swift has no releases and is pinned to a revision in `Packages/AirdraftCore/Package.swift`.
  Move the pin deliberately and re-run the Qwen3 and Cohere self-tests.
- Speech engines kept on purpose: Qwen3-ASR 1.7B/0.6B, FireRedASR2-AED, Cohere Transcribe 2B,
  SenseVoice-small, Whisper Large v3 Turbo, Apple SpeechAnalyzer, OpenAI, Groq, ElevenLabs Scribe.
  Do not re-add the removed Whisper variants or Voxtral without a reason.
