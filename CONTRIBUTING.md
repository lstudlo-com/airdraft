# Contributing to Airdraft

Thank you for helping. Bug reports, fixes and focused improvements are welcome.
For a larger feature or redesign, open an issue first so we can agree on the
approach before you spend time on it.

By contributing, you agree that your contribution is licensed under the
project's [GPL-3.0-only license](LICENSE). Everyone taking part follows the
[Code of Conduct](CODE_OF_CONDUCT.md). Report security problems privately as
described in [SECURITY.md](SECURITY.md), not in a public issue.

This guide covers the workflow. [docs/development.md](docs/development.md)
summarizes the architecture and interface rules you need for most changes.
[`CLAUDE.md`](CLAUDE.md) (identical to [`AGENTS.md`](AGENTS.md)) is the complete
engineering contract used by the maintainer and coding agents; read the parts
that cover your change and ignore its Maintainer environment section.

## Setup

You need an Apple silicon Mac, Xcode 27 or later with its Metal toolchain,
Python 3.12 or later and Git. Follow [Build from source](README.md#build-from-source)
for the full commands. In short, from a fresh clone:

```sh
bash scripts/make-sherpa-xcframeworks.sh            # once: pinned native libraries
python3 scripts/generate-project.py --install-xcodegen
xcodebuild -project airdraft.xcodeproj -scheme airdraft -configuration Debug \
  -skipPackagePluginValidation -skipMacroValidation \
  -packageAuthorizationProvider netrc -onlyUsePackageVersionsFromResolvedFile build
```

With Node.js and pnpm, `pnpm build:app` and `pnpm test:local` run the same steps
through the pinned [moon](https://moonrepo.dev) task runner.

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
- The Debug app is named **Airdraft Debug** and uses its own bundle identifier,
  so it never replaces an installed official build. Debug builds run
  `scripts/check-checkout.py` as a build phase; on a contributor clone it only
  warns.

## Tests

Run the credential-free suite before opening a pull request:

```sh
python3 scripts/test-local-e2e.py      # or: pnpm test:local
```

It must finish with no failures, including the mandatory insertion regressions
it checks in the test results and the `AirdraftAppTests` logic tests for App
code. It never uses API keys or cloud services. The
complete `AirdraftCoreTests` suite (`xcodebuild ... test`) also contains
credential and cloud-provider tests. All unit tests live in
`Packages/AirdraftCore/Tests`; add new tests there, and add a new test class to
the allowlist in `scripts/test-local-e2e.py` when it needs no credentials.

Run the script tests that match your change:

| Change | Command |
|---|---|
| Release, signing or project scripts | `python3 -B scripts/test-release.py` |
| Insertion fixtures or their scripts | `python3 -B scripts/test-insertion-regressions.py` and `python3 -B scripts/test-live-insertion.py` |
| Swift package pins or third-party files | `python3 scripts/acknowledgements.py generate`, then `python3 -B scripts/test-acknowledgements.py` |
| Native library inputs | `python3 -B scripts/test-native-inputs.py` |
| User-facing text | `python3 scripts/localization.py check` (see below) |
| Prompts | score with `eval/run_correction_eval.py`; see [docs/development.md](docs/development.md#prompts) |
| Website (`apps/marketing`) | `pnpm check:marketing` and `pnpm build:marketing`, then look at desktop and mobile widths |

Interface changes need a look at the real result. Debug builds render pages
into PNG files with isolated, disposable data:

```sh
APP="<path to Airdraft Debug.app>/Contents/MacOS/Airdraft Debug"
"$APP" --e2e-local /tmp/airdraft-render --render-window all /tmp/airdraft-render/out
```

Check light and dark appearances, Default and Larger text sizes
(`AIRDRAFT_RENDER_TEXT_SIZE=larger`) and both Chinese interfaces. For accessibility,
`--render-window a11y-audit <out>` walks the real accessibility tree of every
page. [docs/local-e2e.md](docs/local-e2e.md) describes the other local fixtures.
Never point them at your real app data, and do not use live insertion or
microphone fixtures unless you mean to test on your own Mac.

## Localization

The app ships in English, Simplified Chinese (zh-Hans) and Traditional Chinese
(Taiwan, zh-Hant). New user-facing text must be localizable: a SwiftUI string
literal, `String(localized:)` in the app or `String(localized:, bundle: .module)`
in AirdraftCore. After a Debug build:

```sh
python3 scripts/localization.py sync     # add new keys to the string catalogs
# translate the reported keys into zh-Hans and zh-Hant
python3 scripts/localization.py check    # must report every key translated
```

Translate zh-Hans directly with Mainland interface terms and zh-Hant with Taiwan
terms; never convert one into the other. Reuse the terms already in the
catalogs. Do not localize prompts, identifiers, saved values, model or provider
names, or key names. To render a language, pass
`-AppleLanguages '(zh-Hans)' -AppleLocale zh_CN` (or `'(zh-Hant)'` and `zh_TW`)
before `--e2e-local`. [docs/development.md](docs/development.md#localization)
lists the remaining rules.

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
Never hand-edit the generated files.

## Privacy and telemetry

Source builds, Debug builds and tests never send telemetry: the PostHog client
exists only in official Release builds after the user agrees. Tests use the fake
client in `TelemetryTests`; never point a build or test at a real PostHog project.
A new event changes the closed `TelemetryEvent` enum, the `TelemetrySanitizer`
allowlist, its tests, [docs/telemetry.md](docs/telemetry.md) and the website
privacy page together, and must never carry free text, content or identifiers.

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org/):
  `fix(history): keep the timeline in sync after deletion`,
  `feat(models): …`, `docs: …`, `test: …`.
- Keep each pull request to one change, with tests and any documentation it
  affects. Do not commit generated build output, models, API keys or personal
  configuration such as `Config/Local.xcconfig`.
- Fill in the pull request template: describe how you verified the change,
  including the macOS version, the commands you ran and whether you checked the
  running app. Say what you could not verify.
- When you change behavior described in `docs/PRODUCT.md`, `docs/*.md`,
  `CLAUDE.md` or `AGENTS.md`, update them in the same pull request. `CLAUDE.md` and
  `AGENTS.md` must stay byte-for-byte identical (`cmp CLAUDE.md AGENTS.md`).
- CI builds an unsigned app and runs the credential-free suite and script tests
  on macOS with Xcode 27. A pull request is ready when CI passes.

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
