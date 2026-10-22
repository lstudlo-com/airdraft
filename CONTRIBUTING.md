# Contributing to Airdraft

Thank you for helping. Bug reports, fixes and focused improvements are welcome.
For a larger feature or redesign, open an issue first so we can agree on the
approach before you spend time on it.

By contributing, you agree that your contribution is licensed under the
project's [GPL-3.0-only license](LICENSE). Everyone taking part follows the
[Code of Conduct](CODE_OF_CONDUCT.md). Report security problems privately as
described in [SECURITY.md](SECURITY.md), not in a public issue.

## Setup

Follow [Build from source](README.md#build-from-source). In short, from a fresh
clone:

```sh
bash scripts/make-sherpa-xcframeworks.sh            # once: pinned native libraries
python3 scripts/generate-project.py --install-xcodegen
xcodebuild -project airdraft.xcodeproj -scheme airdraft -configuration Debug \
  -skipPackagePluginValidation -skipMacroValidation \
  -packageAuthorizationProvider netrc -onlyUsePackageVersionsFromResolvedFile build
```

- `project.yml` is the source of truth for the Xcode project. Regenerate with
  `python3 scripts/generate-project.py` after changing it; do not run bare
  `xcodegen`, which can drift the Swift package pins. `airdraft.xcodeproj` is
  generated and ignored by Git.
- The root `Package.resolved` is the reviewed Swift package graph. Builds use
  `-onlyUsePackageVersionsFromResolvedFile`; do not pass `-derivedDataPath`.
- Builds are signed ad-hoc unless `Config/Local.xcconfig` names your team (see
  `Config/Local.xcconfig.example`). With a stable team, macOS keeps Microphone
  and Accessibility permissions across rebuilds. Ad-hoc builds are
  development-only and run without Hardened Runtime; team-signed builds keep it.
  `python3 scripts/verify-adhoc-launch.py` builds and launches a fresh ad-hoc clone.

## Tests

Run the credential-free suite before opening a pull request:

```sh
python3 scripts/test-local-e2e.py      # or: pnpm test:local
```

It must finish with no failures, including the mandatory insertion regressions
it checks in the test results. It never uses API keys or cloud services. The
complete `AirdraftCoreTests` suite (`xcodebuild ... test`) also contains
credential and cloud-provider tests.

Run the script tests that match your change:

| Change | Command |
|---|---|
| Release, signing or project scripts | `python3 -B scripts/test-release.py` |
| Swift package pins or third-party files | `python3 scripts/acknowledgements.py generate`, then `python3 -B scripts/test-acknowledgements.py` |
| Native library inputs | `python3 -B scripts/test-native-inputs.py` |
| Prompts | see "Prompt changes" in `CLAUDE.md`; prompts are scored with `eval/run_correction_eval.py` |
| Website (`apps/marketing`) | `pnpm check:marketing` and `pnpm build:marketing` |

Interface changes need a look at the real result. Debug builds can render pages
into PNG files with isolated, disposable data:

```sh
APP="<path to Airdraft Debug.app>/Contents/MacOS/Airdraft Debug"
"$APP" --e2e-local /tmp/airdraft-render --render-window all /tmp/airdraft-render/out
```

Check light and dark appearances. [docs/local-e2e.md](docs/local-e2e.md)
describes the other local fixtures. Never point them at your real app data.

## Dependencies and third-party notices

The app bundles `Sources/App/Resources/Acknowledgements.txt`, generated from the
resolved Swift packages, binary targets, the pinned native libraries and the
model brand assets. After changing `Package.resolved`, a package manifest, the
native inputs or the brand assets, build once so Swift Package Manager resolves
its checkouts, then run:

```sh
python3 scripts/acknowledgements.py generate
```

The generator fails on a new dependency, license file or unrecognized license
until you review it in `ThirdParty/acknowledgements.json`. Texts for components
without a Swift package checkout live in `ThirdParty/licenses/` with their pinned
source URL and SHA-256. CI and release preparation fail when the notices are stale.

## Coding contract

[`CLAUDE.md`](CLAUDE.md) (identical to [`AGENTS.md`](AGENTS.md)) is the detailed
engineering contract for this repository, for people and coding agents alike.
Read the parts that cover your change. The essentials:

- `Packages/AirdraftCore` holds the engine-agnostic logic and all tests;
  `Sources/App` is the SwiftUI shell.
- Speech and refinement are provider-agnostic: a new engine implements
  `Transcriber` or `Refiner`, gets a provider-kind case and is wired in
  `EngineFactory`. Never hard-code a provider in the pipeline or views.
- Refinement is best-effort: an error or timeout must still deliver the raw
  transcript.
- Secrets go in the Keychain, never in preferences, files or logs.
- Follow the interface rules in [docs/PRODUCT.md](docs/PRODUCT.md) and reuse the
  shared components in `Theme.swift` and `SoftControls.swift`.
- Swift language mode 5 on a Swift 6 compiler; keep `@MainActor` on UI-facing
  types and `Sendable` on protocols.
- Keep each `AGENTS.md` and its `CLAUDE.md` byte-for-byte identical when you
  change guidance.

## Localization

The app ships in English and Traditional Chinese (Taiwan). New user-facing text
must be localizable (`String(localized:)` or a SwiftUI string literal). After a
Debug build:

```sh
python3 scripts/localization.py sync     # add new keys to the string catalogs
# translate the reported keys in Sources/App/Localizable.xcstrings (zh-Hant)
python3 scripts/localization.py check    # must report every key translated
```

Use Taiwan vocabulary and the terms already in the catalog.

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org/):
  `fix(history): keep the timeline in sync after deletion`,
  `feat(models): …`, `docs: …`, `test: …`.
- Keep each pull request to one change, with tests and any documentation it
  affects. Do not commit generated build output, models, API keys or personal
  configuration such as `Config/Local.xcconfig`.
- Describe how you verified the change, including the macOS version and
  whether you checked the running app.

## Headless harness

`airdraft-cli` runs the same engines without the app, for evaluation and
debugging. It builds a separate SwiftPM tree in `Packages/AirdraftCore/.build`
(several gigabytes, ignored by Git):

```sh
cd Packages/AirdraftCore && swift build --product airdraft-cli
.build/debug/airdraft-cli prompt --mode summary --family email   # print the exact prompt
.build/debug/airdraft-cli run clip.wav --sensevoice               # transcribe, then refine
```

Subcommands are `transcribe`, `refine`, `run` and `prompt`; see
`Packages/AirdraftCore/Sources/airdraft-cli` for their options.

MLX models (Qwen3-ASR, Cohere) need Xcode-built products; `swift build` does not
compile the Metal library. Pass API keys through `AIRDRAFT_ASR_KEY` and
`AIRDRAFT_LLM_KEY` rather than command-line flags.
