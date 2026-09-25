# Production repairs — 2026-09-25

The audit's application defects have local repairs and regression coverage. Public
distribution remains blocked by the available signing identity. These checks cover
the workspace build, not a deployed update or an untested second Mac.

| Finding | Repair | Evidence / limit |
|---|---|---|
| F01 | Recording generations own timers, callbacks and results; late work cannot reset a new session. | Cancellation/restart and stale microphone callback tests. |
| F02 | Verify the actual Accessibility replacement, including UTF-16 ranges; never paste again after an uncertain write. | Equal-length and emoji replacement tests; cross-app acceptance still needed. |
| F03 | Capture insertion identity independently of optional app context, then verify the original app, field and selection. | Source checks; changed or unverifiable destinations copy with a persistent notice. |
| F04 | Reject truncated, refused or missing completion reasons; preserve the original transcript. | OpenAI, Claude and Gemini response fixtures. |
| F05 | Keep failed/interrupted speech audio for Retry Transcription, Change Provider or Discard. | Provider recovery test; retained audio is in memory, not crash recovery. Quit warns before discarding it. |
| F06 | Show save/read/delete errors, retain unsaved history and drafts, and offer retry. Preserve unreadable files; block writes if backup fails. | Storage failure/recovery tests and corruption fixtures. |
| F07 | Restore full fidelity rules, add general Chinese proofreading guidance, and bind release evaluation to the shipped sources. | Prompt evaluation status below. |
| F08 | Require Hardened Runtime on the signed artifact; add a separate Developer ID/notarization/Gatekeeper gate. | Personal Release signature passes; public gate correctly rejects the current Apple Development identity. |
| F09 | Bound provider discovery, model loading, retries and refinement with one deadline. | An uncooperative-worker test verifies timely fallback. CLI's 60-second minimum is disclosed. |
| F10 | Remember cancellation before a CLI continuation attaches; never launch a pre-cancelled process. | No-process-launch regression test. |
| F11 | Serialize model loading, inference and unloading; cancel obsolete loads and suppress stale status updates. | Engine-switch-during-inference test. Shutdown has a five-second bound. |
| F12 | Own downloads above the page, reject duplicates, retain Cancel/progress, and reject incomplete installations. | Cancellation, duplicate-start, incomplete-files and tokenizer tests. |
| F13 | Give locked-key approval its own row. | Light/dark locked-key renders at 784-point width. |
| F14 | Check permissions, input/channel, required keys, endpoint, model installation and actual readiness **before capture**. | Fault-injection tests prove zero recorder starts. Hidden/temporary Core Audio bridge devices are excluded from choices. A blocked attempt opens Home even with the HUD hidden. |
| F15 | Remove only the selected alias; keep the canonical term and sibling aliases; offer undo. | Alias removal/restoration test. |
| F16 | Paginate beyond the old history cap; reveal text based on rendered truncation. | 305-entry pagination test and history renders. |
| F17 | Keep recovery notices on Home and in the menu after transient HUD state clears. | Blocked-first-run render; speech failures open recovery. |
| F18 | Hide ineffective temperature controls and show Gemini's actual Off/Automatic choices. | Configuration/refinement source and renders. |
| F19 | Compile sample account/subscription UI only into Debug. | Release source and artifact checks. |
| F20 | Clamp Groq recording duration to fit the 25 MB attachment ceiling and reject oversized bypass inputs. | Sample-count/duration boundary tests. |
| F21 | Name settings controls, hide background accessibility elements during overlays, and manage modal focus. | Live Account and Microphone checks: focus enters the modal, Tab stays inside, Escape returns to its trigger. |
| F22 | Calculate Today from the local calendar day. | Day-boundary/DST test. |

## Recording prerequisites

Missing or inaccessible credentials and other known setup failures stop the attempt
before microphone capture and CLI prewarming. Required refinement credentials are
checked when refinement is enabled; Off/Verbatim needs none. An unexpected service
failure can still occur after setup succeeds: speech audio remains available for
retry, and refinement failures preserve the raw transcript. A locally readable key
is not proof of provider billing, transcription permissions or future availability.

## Validation

- Core: **195 tests, 3 existing skips, 0 failures**.
- Release scripts: **12 signing/release tests and 5 prompt-gate fault tests**.
- Signed Keychain fixture: same-identity reads, silent denied access and fixture cleanup passed.
- Real isolated pipeline: Apple Speech → denied-key raw fallback → dictionary → history passed.
- UI: all six pages in light/dark at 784 × 600 and 784 × 1600; locked-key and blocked-first-run states inspected.
- Debug/Release builds and strict signature checks passed. Public distribution is blocked.
- Prompt p9: **30/30 correction and 31/36 holdout checks**, with no per-case regression against p5. Homophone deployment spelling passed 1/3 and SwiftUI spelling 0/3, matching their earlier floors. The default is longer than p6; correctness takes priority over its unvalidated token reduction. Saved custom prompts remain unchanged. These checks establish non-regression, not perfect language quality; failed p7/p8 candidates remain recorded.

## Remaining acceptance work

Obtain Developer ID and explicitly review the privacy/Keychain identity migration
before notarizing the final app and DMG. Test the committed release on the second
Mac and exercise the physical shortcut, microphone recovery, and insertion in real
destination apps. Local fixtures do not certify those results.

Application repairs overlap substantial pre-existing uncommitted provider, CLI and
UI changes. The repair patch is preserved separately; do not stage that earlier work
wholesale merely to produce a commit. Release safeguards and prompt evidence are committed as `6e0aaff`; the temporary-input filter is `74d3148`. Nothing is pushed or published by this repair pass.

References: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Claude stop reasons](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons),
[OpenAI completion reasons](https://developers.openai.com/api/reference/resources/chat),
[Gemini completion reasons](https://ai.google.dev/api/generate-content),
[Groq speech limits](https://console.groq.com/docs/speech-to-text).
