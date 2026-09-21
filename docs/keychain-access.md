# API-key access

Opening Home or Models, switching providers, refreshing a model list and starting
background work must never display a Keychain password dialog. Provider badges
query metadata only. Selected-key reads are noninteractive and preserve the
difference between a missing key and a saved key that requires authorization.

On Models, **Allow access** explicitly requests access to the selected provider's
saved key. Save and removal are also explicit actions. Rejected writes stay
visible as failures; an unread blank field cannot remove a saved credential.
The app never grants itself access, broadens an item's access list, or resets the
user's Keychain. A key protected for an old ad-hoc build or a different Debug app
may need the user's approval once for the stable release identity.

## Implementation rules

- `Keychain.read` is silent by default. Only an Allow access action passes
  `allowInteraction: true`. Runtime errors propagate as access errors before any
  unauthenticated provider call; refinement still falls back to raw text.
- `Keychain.presence` requests attributes, never password data. UI code performs
  Security calls off the main actor through `CredentialEditor` or a background
  task. An inaccessible item is not represented as absent.
- Legacy lookup happens only after `errSecItemNotFound`. Passive reads never
  write. Explicit migration uses add-only semantics and re-reads the current
  item if another writer created it. Existing current values always win.
- Remove legacy first, then current. If legacy removal fails, keep current so a
  later read cannot resurrect the stale value.
- Both key editors share failure, cancellation and provider-switch behavior.
  Successful changes notify the selected model list to refresh. Late responses
  cannot replace the next provider's key or model.
- Offscreen renders use no saved credentials and do not query provider model
  APIs. `AIRDRAFT_RENDER_KEYCHAIN=locked` renders a synthetic recovery state.

## macOS constraint

The existing items are in the file-based login Keychain. Apple's data-protection
Keychain is a different implementation with entitlement and provisioning rules;
changing to it would be a separate migration. The SecItem/LAContext no-UI options
do not reliably suppress file-based Keychain dialogs. Chromium documents this
as FB16959400 and uses `SecKeychainSetUserInteractionAllowed` with restoration.
AirDraft scopes that switch under one lock shared by its credential operations,
restores the previous setting even on failure, and fails closed if it cannot set
it. The deprecated API is intentional for these existing items.

`python3 scripts/verify-keychain.py` creates eight disposable fixture entries with
one certificate-signed app, reads them with a rebuilt app sharing its identity,
and queries them from another identity. The successor must read them silently;
the other identity must get authorization-required errors without dialogs.
Only the fixture entries are removed. This check runs in the local release gate.
It does not prove permission continuity on a different Mac.

## Evidence

- [Apple: macOS Keychain implementations](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)
- [Apple DTS: SecItem pitfalls and best practices](https://developer.apple.com/forums/thread/724013)
- [Apple: Keychain code-signing identity](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)
- [Chromium: scoped file-Keychain interaction control](https://chromium.googlesource.com/chromium/src/crypto/+/refs/heads/main/apple/scoped_keychain_user_interaction_allowed.cc)
