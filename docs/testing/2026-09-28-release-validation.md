# Build and local E2E validation, 2026-09-28

Debug and Apple Silicon Release builds pass. The local E2E suite passes after
fixing an Apple Speech cancellation hang. The prompt release gate blocks
publication because one held-out case scored below its recorded baseline.

## Results

| Check | Result |
|---|---|
| Local core suite | 243 tests: 239 passed, 4 opt-in tests skipped, zero failures |
| Built app | 14 isolated actions passed: inventory, Apple transcription, silence with all 8 provider selections, Apple cancellation at 3 timings, and live preview |
| Retained audio | Matching transcript/history, insertion disabled, and a WAV with the source frame count and 16 kHz sample rate |
| Cancellation | The original 20 ms cancellation exceeded the 120-second process deadline. After the fix, cancellations at 20, 50 and 150 ms released the engine lease in 39, 45 and 5 ms, with no outcome or history |
| Native fixtures | Shortcut, microphone selection and HUD checks passed; all 13 model-lifecycle checks passed |
| Rendering | Inspected 48 renders: 6 pages, both appearances, 784-point width, 600/1000-point heights, expanded/collapsed sidebar |
| Shared materials | 8 shadow checks and the header radius-mask/compositor-availability fixture passed |
| Release artifact | arm64 app and core framework, pinned Apple Development identity, strict signature and Hardened Runtime checks passed; Debug/E2E entry-point strings absent |
| Release tooling | 14 release tests and 5 prompt-gate tests passed |
| Prompt p9 | Correction 30/30; holdout 30/36. `deploy-homophone` scored 0/3 against the recorded baseline's 1/3, so the production gate fails |

The four skipped tests require installed subscription CLI integrations or the
downloaded Parakeet model. Silence checks exit before model loading; they do not
establish recognition accuracy for the seven downloaded model choices.
API-key workflows, physical microphone capture, cross-application insertion,
live header appearance, notarization and another Mac's permission continuity
were not verified in this run.

## Changes

- Apple Speech now checks cancellation around asynchronous analysis, cancels its
  result collector and explicitly finishes the analyzer. Apple's
  [`cancelAndFinishNow()`](https://developer.apple.com/documentation/speech/speechanalyzer/cancelandfinishnow%28%29)
  ends pending analysis, including before input starts. A new core regression
  test checks that cancelled requests stop before language-asset lookup.
- E2E and release runners select Xcode's `netrc` package authorization provider.
  The first build was waiting for Keychain authorization for public dependency
  archives. No `.netrc` file was present on this Mac. Xcode also needed a clean
  after recovery of the interrupted artifact download.
- The feature release version is 0.3.0. Fresh p9 reports bind the current
  dictionary implementation to both datasets and preserve all three runs.

## Evidence

Tracked reports are `eval/results/p9-20260928-correction.json`,
`eval/results/p9-20260928-holdout.json` and `eval/results/prompt-validation.json`.
`python3 scripts/verify-prompt.py` reproduces the held-out gate failure.

Local logs, xcresults, synthetic audio, runtime results, renders and signing proof
are under `/tmp/airdraft-validation-20260928/`. The final core run is
`local-e2e-cancellation-fixed/tests.xcresult`; runtime evidence is in `runtime/`,
`runtime-fixed.log` and `runtime-summary.json`. The three cancellation result
directories are `apple-cancel`, `apple-cancel-50ms` and `apple-cancel-150ms`.
Temporary evidence can be removed by system cleanup.
