# Development guide

A short map of Airdraft's code and the rules most changes touch. Start with
[CONTRIBUTING.md](../CONTRIBUTING.md) for setup, tests and pull requests. The
complete contract, including every interface measurement, is
[`CLAUDE.md`](../CLAUDE.md); when this guide and that file disagree, that file wins.

## Layout

| Path | Contents |
|---|---|
| `Packages/AirdraftCore` | Engine-agnostic logic: speech and refinement providers, the dictation pipeline, insertion, history, settings, media and licensing. All unit tests live in its `Tests/`. |
| `Sources/App` | The SwiftUI shell: `App/` (entry point, `AppContainer`, `ModelLifecycle`), `Hotkeys/`, `HUD/` (recording window), `Views/` (one file per page; shared components in `Theme.swift` and `SoftControls.swift`) and `Debug/` (renders and fixtures, compiled only into Debug builds). |
| `apps/marketing` | The Astro website; read its `PRODUCT.md` and `DESIGN.md` first. |
| `eval/` | Prompt and speech-model evaluations with their datasets and results. |
| `scripts/` | Project generation, release, fixtures and their tests. |
| `docs/` | Product goals, design notes and implementation contracts. |

A dictation flows through `DictationPipeline`: capture, speech recognition
(`Transcriber`), optional refinement (`Refiner`), dictionary post-processing,
then delivery at the cursor or to a script, and finally history.

## Architectural rules

- **Provider-agnostic engines.** A new speech or refinement engine implements
  `Transcriber` or `Refiner`, gets an `ASRProviderKind` or `LLMProviderKind` case
  and is wired in `EngineFactory`. Never hard-code a provider in the pipeline or
  views. `ASRConfig.engineID` must equal the `id` of the transcriber the factory
  builds (`EngineFactoryTests` checks this). Each cloud provider uses its own
  native API contract; a new refinement wire needs a request-shape test in
  `RefinerWireTests`.
- **Refinement is best-effort.** Any refinement error, timeout, incomplete
  response or fidelity failure must still deliver the raw transcript. Keep the
  one-time minimal-body retry after a provider rejects an optional field.
  `DictionaryPostProcessor.apply` runs last, after refinement.
- **Local models never download by themselves.** They load only from the app's
  model folders. Downloads go through `ModelDownloader` from the Models page or
  onboarding, and every pinned file is checked by size and SHA-256 before it is
  installed. Unpinned models are refused.
- **Secrets stay in the Keychain** (service `com.lstudlo.app.airdraft`), never in
  preferences, files or logs. Passive access never prompts: use
  `Keychain.presence` for badges and `CredentialEditor` for key fields. Provider
  requests go through `ProviderTransport` (no cache, cookies or cross-host
  redirects). Logs carry durations and identifiers, never audio, text or keys.
- **Concurrency.** AirdraftCore builds in Swift 6 language mode, so data races are
  compile errors; the app target stays in Swift 5 mode. Keep `@MainActor` on
  UI-facing classes and `Sendable` on protocol types, and prefer actors, `Mutex`
  and `sending` to locks. Every `@unchecked Sendable` or `nonisolated(unsafe)`
  names the lock or queue that confines its state.
- **Sessions own their work.** Each dictation captures its profile, speech
  model, refinement and output settings when recording starts and uses that
  snapshot throughout. Stale asynchronous work must never change a newer session
  or insert text.
- **Insertion pastes once and verifies.** Both insertion settings paste exactly
  once into the captured field and confirm by reading the text back; never retry
  a posted paste or probe an editor with an Accessibility text write. A receiver
  that cannot confirm keeps the transcript on the clipboard with a recovery
  notice, except the self-drawing editors listed in
  `TextInserter.selfDrawingEditorBundlePrefixes`, which are recorded as sent
  unverified. `TextDeliveryRegressionTests` covers these paths; keep it passing.
- **Profiles, not modes.** Refinement behaviors are `RefinementProfile`s in
  `ProfileStore`. Built-ins keep stable IDs and stay resettable. Setup stays
  preset-driven: users never have to write a prompt to get a good result.
- **Debug-only test paths.** Renders, self-tests and `--e2e-local` fixtures
  compile only into Debug builds and use disposable data directories. Views read
  `RenderMode`, never process arguments or environment variables directly.

## Interface conventions

Interface consistency is a product requirement. Read the Interface consistency
section of [PRODUCT.md](PRODUCT.md) before a UI change. The essentials:

- Text uses the `TextStyle` tokens through `.appFont(_:)`, never a fixed
  `.system(size:)`, so Settings > Appearance > Text size scales it. At Larger,
  text wraps rather than truncates in the fixed 784-point window.
- Settings and Models sections use `PageSection` and `SettingsCard`, with 16 pt
  card insets and 18 pt corners from `Theme`. Rows inside a card add no extra
  vertical padding; use the shared spacing tokens.
- Controls come from `SoftControls.swift` and `Theme.swift`: `SoftButtonStyle`, `.primaryButtonStyle()`
  for the one primary action, `SoftPicker`, `SoftSegmentedPicker`,
  `.toggleStyle(.softSwitch)`, `SoftSlider`, `.softField()` and
  `SettingsNumberStepper`. Reuse `StatusDot`, `RefreshButton`, `OverlayPanel`,
  `NoticeRow`, `InlineNotice` and `APIKeyField` instead of page-specific variants.
- Neumorphic light always comes from the top left in both appearances. Use
  `SurfaceShadows` for outer shadows.
- Buttons and menu items use title case; section headings use sentence case.
  Keep descriptions to one short phrase that helps a decision.
- Every control has a VoiceOver name and state, section titles are headings,
  and spatial animation has a Reduce Motion branch; see
  [accessibility.md](accessibility.md).

Check light and dark renders at the 784-point width, at minimum and taller
heights and at Larger text, in English and both Chinese interfaces.

## Localization

The app ships English, Simplified Chinese (zh-Hans) and Traditional Chinese
(Taiwan, zh-Hant) through the String Catalogs `Sources/App/Localizable.xcstrings`,
`Sources/App/InfoPlist.xcstrings`, `Sources/App/AppShortcuts.xcstrings` and
AirdraftCore's `Resources/Localizable.xcstrings`.

- Write copy as localizable literals: SwiftUI `Text` and `Button` literals,
  `String(localized:)` in the app and `String(localized:, bundle: .module)` in
  AirdraftCore. Pass runtime text through the `String` or `.verbatim(_:)`
  overloads.
- Write both branches of a ternary as explicit localized values; the compiler
  extracts only the first branch of a `LocalizedStringResource` ternary.
- Native menus resolve SwiftUI keys without the app's locale, so their titles
  and items must be `String(localized:)` values.
- Never localize prompts, identifiers, saved values, model or provider names, or
  key names, and never compare against displayed text. App Shortcut phrases keep
  `${applicationName}` in every language.
- After a Debug build, run `python3 scripts/localization.py sync`, translate the
  new keys into zh-Hans and zh-Hant, and run `check`. `audit` lists literals that
  bypass localization. `LocalizationCatalogTests` fails on missing, stale or
  placeholder-mismatched entries.

## Prompts

Refinement prompts are assembled by `PromptBuilder`. A prompt change bumps
`PromptBuilder.version` and is scored with `eval/run_correction_eval.py` on
`eval/correction_cases.json` and the held-out `eval/holdout_cases.json` (and
`eval/context_correction_cases.json` for correction rules), with LM Studio running.
Do not ship a prompt that loses a held-out case.

## Further reading

- [PRODUCT.md](PRODUCT.md): product goals, implemented behavior and interface rules
- [local-e2e.md](local-e2e.md): credential-free fixtures and live checks
- [transcription-apis.md](transcription-apis.md) and
  [refinement-providers.md](refinement-providers.md): provider contracts
- [local-speech-models.md](local-speech-models.md): local models, pins and downloads
- [keychain-access.md](keychain-access.md): credential access rules
- [media-transcription.md](media-transcription.md) and
  [meeting-recording.md](meeting-recording.md): audio recording in Transcribe
- [automation.md](automation.md): Shortcuts and script output
- [updates.md](updates.md): versions, signing and releases
