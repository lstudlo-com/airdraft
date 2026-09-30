# Local feature verification

This workflow exercises the app without API credentials. The test runner uses an
explicit allowlist: cloud-provider contracts and all credential tests are excluded,
including tests that use fake API keys. It does not discover, read or enter API keys.

## Repeatable regression checks

```sh
python3 scripts/test-local-e2e.py --output /tmp/airdraft-local-tests
python3 scripts/verify-native-behaviors.py
python3 scripts/verify-model-lifecycle.py
python3 -B scripts/test-release.py -v
python3 -B scripts/test-licensing.py -v
python3 -B scripts/test-prompt-gate.py -v
```

The Xcode runner writes its exact command, log and xcresult to a fresh output
directory. It uses the normal DerivedData tree and disables parallel test execution.
`pnpm test:local` runs the same allowlist through Moon's serialized Xcode task.
Before accepting a successful Xcode exit, it checks the actual xcresult with
`verify-insertion-regressions.py`. All 27 mandatory insertion cases must be present
and Passed, including the production capture-to-paste and context-off pipeline
fixtures. Missing, skipped and failed cases stop validation. The JSON evidence is
saved as `insertion-regressions.json`; release preparation runs the same gate for
both test scopes before building the release artifact.
Onboarding, license state and public Polar endpoint fixtures are included; they
use disposable storage and intercepted responses, without API keys or purchases.
Package downloads use Xcode's `netrc` authorization provider to avoid Keychain
prompts for the project's public dependencies.
The Xcode process group has a 30-minute deadline; override with `--timeout` seconds
when a clean toolchain build requires longer.
Pass `--parakeet-model /absolute/path/to/installed/parakeet` to enable the real
official-sample, reload and 45-second transcription test. Installed CLI integration
tests stay opt-in; fixture executable tests always run.

`verify-native-behaviors.py` compiles the real Carbon shortcut controller,
microphone selection helper and HUD controller against small fixture dependencies.
`verify-model-lifecycle.py` compiles the real lifecycle source with controllable
local-server responses. These are targeted native regression checks, not substitutes
for live UI or hardware acceptance.

## Isolated Debug app

`LocalE2E` exists only in Debug builds. Launch the executable explicitly:

```sh
env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
  AIRDRAFT_E2E_MODEL_ROOT=/tmp/airdraft-e2e/models \
  "$APP/Contents/MacOS/Airdraft Debug" \
  --e2e-local /tmp/airdraft-e2e/session \
  --e2e-seed --e2e-audio /absolute/path/to/fixture.wav
```

Keep the minimal launch environment so API-key environment variables are not
inherited by test subprocesses. Use a separate data directory for each independent
scenario. The directory's SHA-256 identifies its preferences suite. History, vocabulary, profiles and audio
belong to that directory; downloaded models default to its `Models` subdirectory.
An absolute model-root override can share disposable model files between scenarios.
A reused directory rejects cloud speech selections and remote refinement
endpoints. The engine factory's credential reader always returns nil. Key controls,
remote catalog discovery and key-requiring provider actions are disabled or hidden.
Recording preflight also uses a nil credential reader and rejects unsupported
providers before checking live permissions/devices. Automatic updater startup is skipped.

For GUI automation, copy the Debug app and give that copy a bundle identifier
ending in `.e2e`, preserving the approved development signing identity. Such a
bundle exits with status 64 if relaunched without `--e2e-local`; it must never fall
back to normal user data after a crash. Check the fixture process before each UI
operation because browser/computer-control tools may relaunch an exited app.
Add `--e2e-menu` to open a Debug window containing the actual `MenuView` controls
when the automation tool cannot reach the menu-bar item. This verifies callbacks
and state, not the native menu-bar presentation.

Available `--e2e-action` values:

| Action | Behavior |
|---|---|
| `inventory` | Local model installation paths and on-device refinement availability |
| `insert` | Production capture/insertion against an explicitly prepared disposable field in another app; verifies the actual resulting field value |
| `download` | Explicit anonymous installation of `--e2e-model` into the isolated root |
| `transcribe` | Real pipeline, local ASR, dictionary/conversion, SQLite and retained WAV; insertion disabled |
| `preview` | Real Apple Speech preview, provisional text and callback cancellation |
| `microphones` | Existing repeated hardware capture/reconfiguration self-test |
| `automation` | Real Start/Cancel/Start/Stop intents, microphone capture and a disposable script receiver |

Transcription accepts `--e2e-audio`, `--e2e-locale` and `--e2e-model` using catalogue
IDs (`apple`, `qwen3:0.6b`, `qwen3:1.7b`, `cohere`, `sherpa:senseVoice`,
`sherpa:fireRed`, `sherpa:parakeet`, `whisper:turbo`). `--e2e-cancel-ms` checks that
cancellation produces no outcome or history and waits for model cleanup.
Add `--e2e-prepare` to load an already installed engine before starting the
recording fixture; cancellation evidence then includes the actual processing
state and elapsed time, distinguishing inference from startup.
`--e2e-expect-silence` asserts no outcome/history for a silent fixture.
`--e2e-profile` selects a built-in or fixture profile by name.

Optional refinement accepts only `codex`, `claudeCode`, `appleIntelligence` or
`openAICompatible`; the last requires a loopback `--e2e-endpoint` and optional
`--e2e-llm-model`. Subscription CLI login must already exist. Do not inspect auth
files or perform login as part of credential-free verification.

After building, run `python3 scripts/verify-local-e2e-errors.py --app "$APP"`
to assert failure exits for invalid selectors, missing audio and an unwritable report.
Every asynchronous action exits nonzero when verification fails, including a
missing result write. Unknown profile and refiner selections are rejected.
For transcription, `pipelineStatus` records successful text/history processing,
while `refinementStatus` distinguishes actual refinement from raw-text fallback.
A requested refiner's fallback fails the overall action; inspect both fields.
Audio-file transcription and preview do not play sound. Speaker/microphone
playback and History playback are separate, audible checks and may be omitted
when silent testing is required.

For live insertion, first prepare a disposable field in the target app containing
exactly `Airdraft insertion fixture <UPPERCASE-UUID>` with its caret at the end.
Run `--e2e-action insert --e2e-target-bundle <bundle-id>
--e2e-insertion-token <UUID> --e2e-insertion-method auto` and repeat in a fresh
field with `paste`. The target must be frontmost and the Debug app must already
have Accessibility access. Missing arguments, a different field value, a moved
caret or a different app stop the fixture before delivery. The fixture requires
the actual field value to match the expected insertion, one delivery callback
and no notice. Posting a key event alone is not a pass. A failed fixture restores
its recovery clipboard text only while it still owns that clipboard change.
Never use an existing user draft or reset permissions to run this check.

Release preparation checks four live cases: TextEdit and Chrome, each with
`auto` and `paste`, using fresh fixture tokens. Run each candidate Debug action
with `--e2e-local dist/releases/<tag>/insertion-e2e/<case>` (absolute path). The
fixture writes hashes of its executable, core and UI library. Prepare prints the
candidate Debug path. `verify-live-insertion.py` validates the matrix against that
build, and `release.json` carries its summary tied to the commit. If live acceptance
cannot be completed, the user's push-and-release policy applies: pass
`--unverified-live-insertion REASON` to prepare and record the incomplete check
instead of blocking publication. Report it after release. The original failed
report remains intact. Unit tests or posted key events cannot replace live results.

Before calling a locally reproduced bug fixed, verify the running build:

```sh
python3 scripts/verify-running-app.py --app "$APP" --report /tmp/airdraft-running-build.json
```

This requires one running Airdraft copy at the requested path and compares the
loaded executable, core framework and Debug UI library UUIDs against that bundle.
For Debug, the adjacent Xcode PackageFrameworks copy is also an allowed load path,
but its loaded UUID must still match the embedded framework.
Rebuilding a file or reading its Info.plist does not prove an old process loaded
it. Quit obsolete copies normally, preserving recovery prompts, then relaunch
the intended app and repeat. A published release does not update a running Debug
process. Permission and actual external-editor coverage must be reported separately
from the controlled OS fixtures in the core suite.

For automation, wait for the scenario's `ready-for-playback` file, then play the
fixture through a speaker near the selected microphone. The receiver uses literal
UTF-8 stdin. Every action needs an external process deadline as a second boundary
around native inference. Each writes `result.json`; nonempty text alone does not
prove recognition accuracy. Compare content, silence behavior, history, delivery,
cancellation and cleanup separately.

## Updater fixture

```sh
python3 scripts/verify-updater.py --sparkle "$SPARKLE_DISTRIBUTION" --ephemeral-key
python3 scripts/verify-updater.py --sparkle "$SPARKLE_DISTRIBUTION" --ephemeral-key --legacy-source
```

The ephemeral option generates a disposable Ed25519 seed inside the temporary
fixture and passes it directly to Sparkle's tools. It never reads the production
Sparkle signing item. Code signing still uses the pinned development identity.
The localhost fixture checks valid and tampered feeds, tampered archives, actual
download/install on quit, cleanup, designated-requirement continuity and restart.
Only its temporary app is replaced. This does not certify notarization, a public
feed or permission continuity on another Mac.

Long Whisper regression can be repeated with an installed local model and speech
containing a distinct phrase after the first 30 seconds:

```sh
python3 scripts/verify-whisper-long.py --app "$APP" --models /tmp/airdraft-e2e/models \
  --audio /absolute/path/to/long.wav --tail 'purple elephant'
```

The script checks the transcript tail, full saved duration, one matching history
record, retained audio and disabled insertion, with an external 90-second deadline.
Use `--allow-short --tail Hello` with a sub-second recording to check that the
SDK does not skip speech shorter than its default one-second tail clipping.

## 2026-09-26 audit

The feature ledger and final measured results are in
[`testing/2026-09-26-local-e2e.md`](testing/2026-09-26-local-e2e.md).

The [2026-09-28 build and E2E validation](testing/2026-09-28-release-validation.md)
records the Apple cancellation repair, current build checks and prompt release blocker.
