# Local feature verification

This workflow exercises the app without API credentials. The test runner uses an
explicit allowlist: cloud-provider contracts and all credential tests are excluded,
including tests that use fake API keys. It does not discover, read or enter API keys.

The updater verifier uses separate disposable app identities for tampered-download
rejection and successful installation, so a failed installer helper cannot affect
the next scenario. Both scenarios retain feed, archive and signing checks.

## Repeatable regression checks

```sh
python3 scripts/test-local-e2e.py --output /tmp/airdraft-local-tests
python3 scripts/verify-native-behaviors.py
python3 scripts/verify-model-lifecycle.py
python3 scripts/verify-download-progress.py --output /tmp/airdraft-download-progress
python3 scripts/verify-native-ui-controls.py --output /tmp/airdraft-ui-controls
python3 -B scripts/test-release.py -v
python3 -B scripts/test-swiftpm-lock.py -v
python3 -B scripts/test-licensing.py -v
python3 -B scripts/test-prompt-gate.py -v
```

The Xcode runner writes its exact command, log and xcresult to a fresh output
directory. It uses the normal DerivedData tree and disables parallel test execution.
`pnpm test:local` runs the same allowlist through Moon's serialized Xcode task.
The selection also runs the whole `AirdraftAppTests` target: logic tests for
App-only code (menu title fitting, layout constants, Settings search state,
setup readiness and the frontmost-app label). That bundle compiles the App
sources itself instead of using the app as a test host, so no test launches
Airdraft, starts hotkeys, reads the user's preferences or history, or touches
Keychain items; readiness tests use a disposable container with injected
permissions and a dictation boundary that refuses to record. The runner requires
at least one executed App case and no unsuccessful ones (`app-tests.json`).
Before accepting a successful Xcode exit, it checks the actual xcresult with
`verify-insertion-regressions.py`. All 71 mandatory insertion cases must be present
and Passed, including the production capture-to-paste and context-off pipeline
fixtures. Ignored/partial/unobservable pastes into a field with a caret must
retain recovery text without reporting delivery; delayed reads, cancellation,
newer clipboard ownership and editor-normalized line endings, quotes and
non-breaking spaces are covered too. A paste into a validated editor that draws
its own text (Warp, Zed and the other allowlisted terminals) is sent unverified:
no error, the HUD finishes, History records the separate status and the user's
clipboard returns unless something newer replaced it. Other caretless apps
(Finder, an Electron app without a caret) keep the recovery outcome; retries of
caretless recordings copy only; Try It delivers through its practice channel.
Missing, skipped and failed cases stop validation. The JSON evidence is
saved as `insertion-regressions.json`; release preparation runs the same gate for
both test scopes before building the release artifact.
Onboarding, license state and public Polar endpoint fixtures are included; they
use disposable storage and intercepted responses, without API keys or purchases.
Package downloads use Xcode's `netrc` authorization provider to avoid Keychain
prompts for the project's public dependencies.
The shared selector rejects known credential/provider-key suites, including
`SonioxMediaTests` and the separately scoped `CredentialRemovalTests`, whether
selected as a whole class or an individual case. Marker-only transport and URL
minimization tests exercise privacy boundaries without keys or provider calls.
The Xcode process group has a 30-minute deadline; override with `--timeout` seconds
when a clean toolchain build requires longer.
Pass `--parakeet-model /absolute/path/to/installed/parakeet` to enable the real
official-sample, reload and 45-second transcription test. Installed CLI integration
tests stay opt-in; fixture executable tests always run.

`verify-native-behaviors.py` compiles the real Carbon shortcut controller,
microphone selection helper and HUD controller against small fixture dependencies.
HUD panels run outside all connected screens by default, including synthetic HTTP
429 errors. Native layout, animation, timeout and disposable-pasteboard checks still
run. Use `--show-hud` only for an intentional on-screen visual check, or `--skip-hud`
to omit those checks. Notices must expose no copy button, leave copied dictation
untouched, and keep their text vertically centered; errors retain a centered copy
button with complete diagnostics.
`verify-model-lifecycle.py` compiles the real lifecycle source with controllable
local-server responses. These are targeted native regression checks, not substitutes
for live UI or hardware acceptance.

`verify-download-progress.py` compiles the shared SwiftUI download view and its
production progress value into a disposable window. Compositor captures verify
intermediate fill positions, network pauses, stage changes and both appearances.
It injects the read-only Reduce Motion input to check that branch without changing
system preferences. It does not download a model; `ModelDownloadProgressTests`
separately exercise actual loopback transfers, byte counts and cancellation.

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
| `accessibility` | Non-prompting `AXIsProcessTrusted` result, bundle path, binary hashes and the compiled `selfDrawingEditorBundlePrefixes` |
| `architecture` | Actual AppContainer cleanup, journal recovery, single-writer and onboarding resolution with disposable stores and an injected remote-cleanup operation; no capture, credentials or provider calls |
| `insert` | Production capture/insertion against an explicitly prepared disposable field in another app; verifies the actual resulting field value |
| `download` | Explicit anonymous installation of `--e2e-model` into the isolated root |
| `transcribe` | Real pipeline, local ASR, dictionary/conversion, SQLite and retained WAV; insertion disabled |
| `preview` | Real Apple Speech preview, provisional text and callback cancellation |
| `model-preview` | Selected-model live text (AD-084) on `--e2e-audio` in real-time 100 ms chunks through the factory's display-only lease: decode cadence and window bounds, callback stop, and the final transcript compared without preview, after preview and while a preview decode holds the lease |
| `microphones` | Existing repeated hardware capture/reconfiguration self-test |
| `automation` | Real Start/Cancel/Start/Stop intents, microphone capture and a disposable script receiver |
| `capture-latency` | Real default-input `AudioRecorder` first-buffer time and production `pressToCaptureMs`, only when microphone access is already authorized |

`capture-latency` reads `AVCaptureDevice.authorizationStatus` before any audio
API and reports `unverified` with the reason unless it is `authorized`; it never
requests access or changes the input device. It runs `--e2e-trials` (default 5)
recorder trials, then the same number of production pipeline startups held for
`--e2e-recording-ms` (default 600). Speech is a fixture that ignores the samples,
history is absent and insertion is off, so no audio or speech content is kept.
The report names the default input and whether it is Bluetooth. Launch the app
with `open -n` so TCC attributes access to the Debug identity, not the shell.

`architecture` exercises all cleanup scopes, old version-1 journals, remote-cleanup
failure and retry, the lifetime data lease and practice configuration. Remote
resources are harmless identifiers handled by an injected operation; no keys or
provider requests are used. Run it with a fresh data directory.

`--render-window native-ui <output>` exercises production views and callbacks with
fake microphone monitors: busy-state fencing, model/language readiness, practice
restoration, the six-step onboarding walk (real key events lighting the
shortcut caps, typed text rejected, a practice dictation through the real pipeline
with fake capture and speech completing setup, Ready and replay),
notice actions and the failed-cleanup repair disclosure. Credential
controls remain disabled and no credential operations run. Its absolute
`AIRDRAFT_E2E_MODEL_ROOT` must be a fresh child of the supplied `--e2e-local` directory.
The fixture creates model presence markers there without loading a model.
`--render-window meeting-controls <output>` opens the production meeting sheet
and app chooser at the minimum main-window height. It checks row, viewport,
popup and screen containment; delayed loading, 0/1/8/40 sources, refresh,
errors, scrolling and selection; and both meeting meters in light/dark. It also
checks cancelled source requests and saves geometry JSON plus native-view PNGs.
Popover PNGs omit the system material backdrop; inspect the live popup as well.
For interactive checks, `--e2e-meetings --e2e-meeting-apps 40
--e2e-meeting-app-delay-ms 8000` supplies a delayed fake app list. Close/reopen
the real popup during loading to complement the stale-request regression.
These fixtures never open audio devices, play audio or request permissions.
`--render-window models-performance <output>` measures production Home-to-Models
layout at 784 × 600 and 784 × 1000 in both appearances, using disposable data.
It records layout milliseconds and materialized local rows for five visits per
case, checks empty/short/capped table heights and the uncapped compact set, and
saves JSON/PNGs. Models opens with its compact recommended set (AD-071): the
fixture requires only the shortlist and in-use rows on navigation, Verified
shortlist models for every language and memory case, the selected and downloading
Experimental models in both the compact set and a collapsed Experimental group,
search over the whole catalogue and a remembered Show All Models choice. Set
`AIRDRAFT_RENDER_VERIFY_MODEL_LAZINESS=1` to measure the full list and require
bounded initial row creation.
Verify table scrolling and provider/search filters in the live window as well. No models are loaded,
cloud calls made or credentials read.
`verify-native-ui-controls.py` separately exercises the production slider and
History progress consumer in silent windows, including keyboard, pointer and
accessibility adjustment in both appearances; its playback object has no player.

Transcription accepts `--e2e-audio`, `--e2e-locale` and `--e2e-model` using catalogue
IDs (`apple`, `qwen3:0.6b`, `qwen3:1.7b`, `cohere`, `sherpa:senseVoice`,
`sherpa:fireRed`, `sherpa:parakeet`, `whisper:turbo`). `--e2e-cancel-ms` checks that
cancellation produces no outcome or history and waits for model cleanup.
Use `--e2e-language auto` or an explicit language code to exercise the production
language policy independently of the Apple locale. Unsupported combinations must
fail before loading a model; the retained recording remains available for retry.
Add `--e2e-prepare` to load an already installed engine before starting the
recording fixture; cancellation evidence then includes the actual processing
state and elapsed time, distinguishing inference from startup.
`--e2e-expect-silence` asserts no outcome/history for a silent fixture.
`--e2e-profile` selects a built-in or fixture profile by name.
`--e2e-vocabulary-bias on|off` sets Settings > Behavior > Vocabulary in speech
recognition; the fixture's `dictionary.json` in the `--e2e-local` directory
supplies the terms. `eval/vocab-bias/run_eval.py` uses it to compare both states.

Add `--e2e-recording-ms 3000` to replay the same file through recording startup,
allow refinement preparation to overlap that lead time, then stop through the
production grace period. The recorder retains file PCM without opening a device
or playing audio. App context must be off; live preview must be off unless
`--e2e-live-preview` turns on Selected speech model preview, which receives the
file in real-time 100 ms chunks and reports the published text under
`livePreview` (Apple Speech preview is never used here). This uses the same
real local speech/refinement engines and history with insertion disabled, and
accepts a lead time from 0 to 120000 ms below the configured recording limit.
Its `recordingReplay.stopToOutcomeMs` includes the grace period, processing and
history; it is not proof of cursor insertion. Both replay and ordinary file
transcription report `timings` for setup, model preparation, CLI warmup, prompt prefix,
remaining preparation wait, refinement request, postprocessing, delivery,
history and total processing. `stopToDeliveryMs` is null when output is disabled.
`pressToCaptureMs` runs from recording start (shortcut acceptance after any Trigger
Delay, or an automation start) to the first captured buffer; the replay stands in
the file's first chunk for that buffer, and file transcription reports null.

Optional refinement accepts only `codex`, `claudeCode`, `appleIntelligence` or
`openAICompatible`; the last requires a loopback `--e2e-endpoint` and optional
`--e2e-llm-model`. Subscription CLI login must already exist. Do not inspect auth
files or perform login as part of credential-free verification.
For an identified local LM Studio server, recording preparation can evaluate the
captured system prompt before speech recognition finishes, allowing the final
request to reuse its prefix. The speculative request contains no audio or raw
transcript and its output is discarded; it is never delivered or saved. Generic
compatible endpoints and cloud providers do not receive this extra inference.
The final request cancels unfinished prefix work and proceeds without waiting;
an optional warmup failure does not consume its final refinement budget.

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
`--e2e-insertion-field` selects how the field is identified: `exact` (default,
the release gate) requires the field to hold only the marker; `suffix` accepts
earlier text before the marker, ignores trailing blank rows and requires that
text to stay unchanged (a terminal showing the prompt-less receiver); `none` is
the only mode, and the default, for an app in `selfDrawingEditorBundlePrefixes`.
There the fixture reads no field and passes only on the documented outcome: one
paste reported as sent unverified (or confirmed, for a self-drawing editor that
publishes a caret, such as Ghostty 1.3), one delivery callback and no notice.
`--e2e-insertion-place-caret` (exact mode only) moves the caret after the marker
before the production capture, standing in for the operator's click in a
document that opened with its caret at the start. It is a selection change on
the disposable field, never a text write. Every
mode waits for the displaced clipboard to return before the fixture exits.

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

### Live insertion matrix

`verify-insertion-matrix.py` repeats that fixture for every installed target
among TextEdit, Chrome, Safari, Notes, VS Code, Slack, Warp, Zed, Ghostty,
Terminal and iTerm2, once per saved insertion method:

```sh
python3 scripts/verify-insertion-matrix.py --app "$APP" --list
python3 scripts/verify-insertion-matrix.py --app "$APP" --output /tmp/airdraft-insertion-matrix
```

Targets are detected by bundle ID in the application folders; nothing is
installed. Each case gets a fresh UUID marker and its own `--e2e-local` directory.
The Debug app is started through LaunchServices (`open -W -n -g`), so its own
Accessibility grant applies and the fixture app stays frontmost; `--launch direct`
runs the executable as a child process, whose permission belongs to the calling
terminal. The script first runs `--e2e-action accessibility`. When that report
says the Debug app is untrusted, or comes from another build, every case is
UNVERIFIED and nothing is opened. Grant access once: System Settings > Privacy &
Security > Accessibility, turn on Airdraft Debug (use + and choose the printed app
path if it is missing), then rerun. The script never requests, grants or resets a
permission, and uses no AppleScript, System Events or synthetic input.

Fields are prepared as follows; the operator then clicks into the field, and the
script waits until LaunchServices reports that app frontmost for one second. It
reads both the older `lsappinfo` output and the macOS 27 format:

| Target | Preparation | Expected outcome |
|---|---|---|
| TextEdit, VS Code | `open -a` a temporary text file holding the marker; click into it, and the fixture places the caret after the marker | Actual field text |
| Chrome, Safari | `open -a` a local page whose field focuses itself with the caret at the end | Actual field text |
| Notes, Slack | Printed steps: a new note, or your own DM's message box (never press Return), holding only the marker | Actual field text |
| Terminal | `open -a` a receiver script | Actual text (suffix mode) and receiver evidence |
| iTerm2 | Run the printed receiver command in a new window | Actual text (suffix mode) and receiver evidence |
| Warp | Run the printed receiver command in a new window | Sent unverified and receiver evidence |
| Ghostty | `open -n` a new window running the receiver | Sent unverified, or confirmed because Ghostty 1.3 publishes a caret, and receiver evidence |
| Zed | `open -a` a temporary text file; click at its end | Sent unverified; no readable text |

The expected outcome comes from the build's own `selfDrawingEditorBundlePrefixes`.
The terminal receiver clears the screen, prints only the marker, enables bracketed
paste and focus reports, echoes each paste and writes `evidence.json`. A pass
requires exactly one bracketed paste containing the inserted text. When the
harness runs inside the target terminal app, the case also waits for the
receiver's focus report; click another window and then the receiver. Close every
fixture window without saving afterwards, and delete the Notes note or Slack draft.

A case passes only with the build's binary hashes, its own token, one delivery,
no notice and the expected field mode. A fixture error is always raised before
any paste and is recorded as UNVERIFIED with its reason (for example a field that
exposes no readable value); wrong text, extra deliveries, notices or recovery
copies fail. `matrix.json` records every case. The exit status is 0 when all
passed, 1 when any failed and 2 when the matrix is incomplete. `--no-launch
REASON` records every planned case as UNVERIFIED without starting anything.
Release prepare runs it only with `--insertion-matrix`, writing the TextEdit and
Chrome cases into `insertion-e2e/` for the unchanged mandatory gate. Earlier
attempts stay there; a failed earlier report still fails that gate.

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
