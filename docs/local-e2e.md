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
