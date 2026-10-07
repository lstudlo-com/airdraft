# Accessibility access

macOS grants access to a particular app identity. Two switches labelled Airdraft
do not prove that the currently running binary is trusted. Airdraft checks
`AXIsProcessTrusted()` for its own process; it must never treat an earlier prompt
or a saved preference as permission.

## Recover an existing installation

On the affected Mac:

1. Quit all running copies of Airdraft, including development builds.
2. Install the GitHub release in Applications and eject its DMG.
3. In System Settings → Privacy & Security → Accessibility, turn off the old
   Airdraft entries and remove them using the minus button.
4. Use the plus button to add the installed copy in Applications and enable it.
5. Open that same app. Home should show Accessibility granted and the shortcut
   should become active. Hold the actual dictation key to verify capture and
   insertion in another app.

Removing an Accessibility entry does not remove application settings, models,
credentials, or history. Do not reset all apps' permissions or modify TCC.db.
On a managed work Mac, an organization policy may control the setting; involve
the administrator if it is locked or the above recovery fails.

## Reset permissions and remove local app copies

From the repository root, preview the exact bundles first:

```sh
swift scripts/purge-airdraft-apps.swift --dry-run
```

Then run `swift scripts/purge-airdraft-apps.swift` to quit running copies, reset
Accessibility for the release and Debug bundle IDs, and remove verified Airdraft
app bundles. It also handles the legacy Transcribar identity when that app is
still installed. The script searches Applications, Xcode build products, and
Spotlight results, and removes local copies under this user's home directory or
`/Applications`. It does not touch models, history, settings, credentials,
cloud storage, or other users' Accessibility permissions. An app in
`/Applications` may also be used by other accounts. Run the script as the normal
user, without `sudo`.

Apple's per-bundle `tccutil` reset may not remove an older path-based entry from
the Accessibility list. Remove any such entry manually in System Settings with
the minus button. Do not edit TCC.db or reset other apps' permissions.

Home and Settings expose a setup sheet with the running app's location,
Show in Finder, a live recheck, and Copy Diagnostics. Diagnostics include only
OS/app versions, bundle ID, signing identity, permission status, and paths of
running Airdraft copies. Copying is user initiated and uploads nothing.

## Build identities

| Build | Bundle ID | Display name | Public updater |
|---|---|---|---|
| Release | `com.lstudlo.app.airdraft` | Airdraft | Enabled |
| Debug | `com.lstudlo.app.airdraft.debug` | Airdraft Debug | Disabled |

Debug now has its own UserDefaults domain and asks for its own permissions.
The existing shared model/history directory and Keychain service are unchanged.
Debug does not install official updates. Publishing or rebuilding while it is
running leaves the old core and UI libraries in memory. For a repeated bug,
run `scripts/verify-running-app.py --app <intended-app>` before treating an on-disk
version or a successful build as proof of the running code. The read-only check
rejects duplicate copies and mismatched loaded library UUIDs. Quit normally and
relaunch the intended copy; verify its own Accessibility status after restart.
Older debug copies with the release or legacy bundle ID must be quit and their
stale Accessibility entries removed once. The app cannot transfer their grants.

Releases through 0.1.4 were ad-hoc signed. Their designated requirement was a
`cdhash`, so a changed binary did not match the previous build's identity. This
caused the enabled-but-untrusted state after Sparkle updates; UI refreshes and a
separate Debug bundle ID could not fix it.

Starting with 0.1.5, the local release workflow signs with the pinned Apple
Development certificate and verifies its default designated requirement, team,
bundle ID, certificate and validity before packaging and again inside the DMG.
An absent certificate or incompatible signature blocks the release. Existing
ad-hoc permissions cannot be transferred by the app: use the recovery steps above
when moving from 0.1.4 or earlier, and approve Microphone again if requested.
Subsequent compatible certificate-signed updates retain the same signing identity.

Apple Development is the available personal-use option on this Mac. It is not a
substitute for Developer ID signing and notarization for public distribution.
The certificate expires March 15, 2027; the release gate stops 30 days before
expiry. Renewal or migration to Developer ID must explicitly verify compatibility
with the previous designated requirement, or document the permission migration.

Sparkle's Ed25519 signature authenticates updates but does not establish macOS
permission identity. Never use an identifier-only designated requirement to try
to preserve grants; that would discard the signer binding. Never edit TCC.db or
silently reset all permissions as part of an update.

## Insertion warnings with permission granted

"Destination changed" means the captured app, window, field or selection no
longer matches. "Couldn't identify the destination app" means no frontmost app
could be captured when recording began. Both preserve the text on the clipboard
for manual paste.

Some editors draw their own text and expose no caret through Accessibility:
Zed, Warp and other GPU-rendered terminals report no focused element, a
container without selection attributes, or a text role without a readable
range. Until October 2026 capture required a field and caret for every app, so
these editors always got the old "Couldn't verify the destination's cursor"
notice; waiting longer could not help because the caret never appears. Such
destinations are now verified at the app level: the same process must be
frontmost, keyboard focus must not belong to another process, and the focused
window must match when the app reports one. Then they receive the same single
paste. Capture logs `capture: app window` with the focused role, selection
status, window availability and web attribute result, never field contents.

Target capture also checks system-wide focus, verifying that the field belongs
to the original process, and accepts one valid `AXSelectedTextRanges` entry when
the singular attribute is unsupported or has no value. Missing, malformed,
multiple or changed selections cannot authorize insertion. If the editor is not
exposed, capture requests [Electron's documented `AXManualAccessibility`
attribute](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md)
and keeps waiting, within the 1.5-second capture deadline, for its field and
caret. Native editors also get a readiness wait when they reject that web
attribute, but once their caretless focus stays unchanged for 250 ms capture
accepts the app-level target so recording is not delayed. Before delivery, wait
for the original destination even if the app is already frontmost. Individual
AX calls retain their 300 ms timeout.

Cursor insertion uses one normal paste command after checking the captured app
and, when the editor exposes them, its field and selection. Both old `auto` and `paste` preferences use this path;
Settings no longer offers an AX-write mode. Airdraft does not attempt an
`AXSelectedText` write before pasting. Some editors advertise that attribute as
writable but cannot verify a replacement; trying it first caused the repeated
“Check the destination before pasting” recovery notice and blocked normal paste.

A posted command does not confirm delivery. Airdraft waits up to one second
for the expected replacement text in the original field, using its full value
or the inserted UTF-16 range and resulting caret. These read-only checks remain
local and do not supply refinement context. Only confirmation reports success,
starts the HUD fade and permits restoration of the previous clipboard after
the one-second handoff delay. Confirmation and handoff survive cancellation.

Ignored, partial, slow or unobservable pastes keep the dictated text on the
clipboard and show "Paste couldn't be confirmed" with a reminder to check the
destination before pasting again. Caretless terminals still receive one paste;
the lack of read-back prevents false success, not the initial attempt. History
retains the final text and diagnostic without marking delivery successful.
There is never a second automatic paste. Newer clipboard contents are preserved;
the notice then directs recovery to History. A failed clipboard write never
claims that text was copied.

`TextDeliveryRegressionTests` calls production `captureTarget()` and `insert()`
together through an injected OS boundary and private pasteboard. Cases cover
both saved insertion preferences, unavailable AX values, native/web focus,
changed destinations, dropped/partial/delayed paste, cancellation, clipboard
ownership and context-off/refined pipeline delivery to History.
The retired AX-write verifier and its tests were removed with that delivery path.

Both `pnpm test:local` and release preparation inspect the actual xcresult with
`verify-insertion-regressions.py`. All 49 current insertion cases must execute
and pass; missing, skipped and failed cases block the run. From 0.4.2, release
preparation also requires live TextEdit and Chrome insertion for both persisted
preferences. `verify-live-insertion.py` requires the actual resulting text, one
callback, no warning and binary hashes matching the exact committed Debug build.
A new or changed build needs new evidence. The release manifest records this
acceptance; publication rejects missing evidence. See `docs/local-e2e.md`.

## Implementation and evidence

`SystemPermissions` publishes live Accessibility and microphone state. It polls
without prompting, refreshes on activation and wake, and refreshes after an
explicit request. A prompt is asynchronous, not a successful grant. The hotkey
service retries after a grant and stops its monitor after revocation. A trusted
process with a failed event tap gets a shortcut error, not a permission error.
Text insertion and context reading retain their checks at the point of use.

The September 21 M5 screenshot shows enabled switches while the app reports
untrusted. Locally inspected 0.1.3 and 0.1.4 releases have different hash-based requirements;
0.1.4 fails validation against 0.1.3’s requirement. Development signatures differ too:
the release uses a binary hash, development uses an Apple Development certificate,
and both previously used the release bundle ID. These are verified identity
differences; which stale entry the M5 matched remains unverified without diagnostics
from that Mac. No permissions on the personal M4 were reset to test this.

Tests cover changes without hotkey activity, revocation, asynchronous prompts,
observable view invalidation, and fresh-process state. M4 tests cannot establish
that M5 TCC recovery succeeded. Release validation must include an actual update
and permission/shortcut/insertion check on the affected second Mac.

References:

- [Apple requirements and privilege continuity](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Apple code-signing identity and designated requirements](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)
- [Apple DTS on ad-hoc signing and TCC](https://developer.apple.com/forums/thread/125438)
- [Apple Developer ID distribution](https://developer.apple.com/developer-id/)
- [Rectangle's Accessibility recovery procedure](https://github.com/rxhanson/Rectangle#try-resetting-the-macos-accessibility-permissions-for-rectangle)
