# Permission and Keychain audit

Scope: native app startup, Home/Models/Configuration, provider switching, model
queries, runtime credential reads, legacy migration, recording permission,
Debug/release identity, update gates and verification tools. Examined `a0fa0e7`
and the existing uncommitted workspace. Marketing and unrelated model/audio
changes are outside this audit. This report does not imply a published release.

## Action-item ledger

- [x] Implemented: metadata-only provider badges; all passive credential reads
  prohibit system dialogs, including legacy login-Keychain items.
- [x] Implemented: denied/current-item errors stop legacy fallback. Passive reads
  never migrate; explicit import cannot overwrite an existing current item.
- [x] Implemented: shared key editor reports rejected writes, prevents deletion
  from an unread blank field, and discards stale provider-switch results.
- [x] Implemented: Security calls leave the UI thread; credential changes refresh
  model lists, whose results are cancelled/guarded across provider changes. Connection tests
  are also cancelled on provider/configuration/key changes or page exit.
- [x] Implemented: offscreen renders no longer read keys or query cloud models.
- [x] Implemented: speech/refinement return actionable credential errors before
  making requests with inaccessible keys. The raw-transcript fallback remains.
- [x] Implemented: pending recording requests are deduplicated and cancelled by
  shortcut release/cancel. Configuration and dictation share one microphone prompt.
- [x] Implemented: real cross-identity Keychain fixture test added to release gate.
- [x] Already resolved: release signature is pinned; live Accessibility status is
  queried without prompting. Debug has a distinct app identity.
- [ ] External verification: the M5's existing item ACLs and actual post-update
  Accessibility/microphone grants cannot be verified from this M4. Recovery may
  require one explicit approval for an item created by an old app identity.

## Findings and corrections

| Priority | Evidence and failure | Correction and verification |
|---|---|---|
| P1 | `RefinementSettings.refreshKeys`, `APIKeyField`, `ModelField`, `ModelCatalog` used prompting secret reads on page load. Seven provider keys plus selected-key reads can produce the reported dialog sequence. | Attribute-only badges; scoped noninteractive reads. Real eight-key fixture verifies denial without dialogs. |
| P1 | `Keychain.get` treated every Security failure as missing, read the legacy key, then used update-or-add migration. A denied current item could lead to a stale value and another prompt. | Fall through only on not-found; import only explicitly with add-only semantics. Tests cover denied/cancelled/malformed results and a racing current value. |
| P1 | `APIKeyField` ignored `Keychain.set`'s result and showed Saved; failed reads became empty editable values. Deletion removed current before attempting legacy. | Shared editor retains unsaved input on failure, disables unchanged/unknown blank saves; delete legacy first. Regression tests cover these failures. |
| P2 | Home computed key readiness by decrypting credentials in `body`; key fields read on the main actor. | Background reads and cached metadata; shared editor keeps authorization work off the main actor. |
| P2 | `ModelField` did not reject late results; refinement refresh identity omitted the key reference. | Task identity includes endpoint/key; cancellation and request guards discard stale results. Connection tests cancel on config/key changes and page exit. Credential updates trigger refresh. |
| P2 | Rendered refinement controls accessed real keys and endpoints. | Render guards and a synthetic locked-key state. |
| P1 | `DictationPipeline.startRecording` did not own/cancel its permission-awaiting task. Releasing the shortcut while the system prompt was open could start recording after grant. | Pending-request ownership, cancellation checks and shared microphone authorization. Tests cover rapid starts, release/cancel before grant, and known permission states. |
| P2 | Earlier release checks covered code identity but not actual Keychain ACL behavior. | Signed writer/successor/foreign-reader test runs before every local release build. |

The code mechanisms above are verified. Whether the M5's specific saved keys are
protected for an older build or another copy is unverified. Stable code signing
does not retroactively rewrite those old access controls.

## Verification

- `moon run airdraft:test`: 132 workspace tests, 3 opt-in CLI tests skipped,
  zero failures. The committed release subset also passed 88 tests, 3 skipped, zero failures
  before the final connection-test cancellation fix; pre-push reruns that gate.
- `moon run airdraft:build`: passed. All six pages rendered in light/dark;
  synthetic locked-key recovery also inspected in both appearances.
- `python3 scripts/test-release.py`: 11 checks passed.
- `python3 scripts/verify-keychain.py`: eight saved keys remained accessible to
  the rebuilt same-identity app; all eight foreign-identity reads returned an
  authorization error without dialogs. Metadata inspection succeeded and the
  process interaction setting was restored. Fixture entries were removed.
- `AIRDRAFT_SELFTEST_ISOLATED=1 AIRDRAFT_SELFTEST=<generated-speech.wav>`:
  Apple speech transcription succeeded, a deliberately denied LLM credential
  preserved the raw transcript, and temporary history contained the final text.
- Tests used fixture keys and isolated settings; no user credentials were printed
  or deleted. Existing unrelated workspace work is excluded from the release.

Primary evidence and the macOS implementation choice are linked in
[API-key access](../keychain-access.md).
