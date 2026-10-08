# Data cleanup and reset

Settings has four independent actions with a native confirmation. A preview
shows record counts and estimated managed bytes before confirmation. A failed
preview retries the preview, never the deletion. Cancel is the default action.
Shortening dictation retention also asks before removing older audio.

| Action | Deletes | Preserves |
|---|---|---|
| Remove History | Text, context, statistics and pending text saves | Independent recording assets, settings and models |
| Remove Audio Files | Managed audio and in-memory recovery samples | Saved and pending text, settings and models |
| Remove History and Audio Files | Both preceding scopes | Settings, profiles, vocabulary, keys, models and permissions |
| Reset App | Both scopes, app files/models/caches, preferences, profiles, vocabulary, provider keys and current app permission decisions | License/trial records, installed app, external originals and exported copies |

Reset targets the shared Transcribar app-data directory. It clears preferences for
Airdraft, Debug and legacy Transcribar and marks legacy import complete, so old
preferences cannot return. Provider credential removal enumerates attributes only
and deletes current/legacy provider accounts without reading secret values. Accounts
with the reserved `license.` prefix remain. Keychain interaction is disabled; refusal
is a partial failure with Retry, never a success claim. External model services and
user-owned source media are not filesystem deletion targets.

`DataCleanupCoordinator` records a fixed scope and completed steps in `cleanup.json`.
The file is private, atomically replaced and synchronized. Each step is idempotent;
Retry skips completed steps, including after relaunch. Malformed journals fail
closed. SQLite, files, Keychain and TCC are separate effects, not one rollbackable
transaction. Errors name the remaining work and preserve the journal.

Before deleting data, media preparation clears remote jobs and uploads while their
recovery IDs still exist, then removes staging files. It runs again on a journaled
retry while History is open: older journals do not prove that preparation completed.
Cleared IDs make this idempotent, and completed destructive phases stay skipped.
A failed fresh preparation preserves documents and IDs and leaves Settings
available. A failed journaled preparation retains the maintenance fence. When
remote IDs remain, Repair Provider Access explicitly reveals the existing key
editor for their saved references; it does not reopen general data editing.
Resources whose recovery IDs were already deleted by an older completed cleanup
cannot be reconstructed by this recovery path.

Recording, processing, downloads and pending history writes must finish first. A
main-actor pipeline fence blocks all new entry points, save retry and retention.
History-only cleanup turns pending retained audio into detached assets before
forgetting its text; audio-only cleanup strips samples from pending text saves.
Generation invalidation rejects late transcription callbacks. Playback stops as the
fence begins. Notifications refresh History and sidebar statistics after cleanup.

One app copy holds an exclusive advisory lease on `.airdraft-data.lock` for its
entire lifetime. A second copy using the same directory is blocked; independent
isolated directories remain usable. Cleanup and reset never downgrade the lease.
Known running sibling builds are also checked because
older versions may not implement the lease. A blocked new copy does not open or
repair shared JSON stores. The lock file survives reset so its inode remains the
coordination point. Failed reset keeps new work fenced until retry or quit.

A copy that cannot open its data directory shows Data Unavailable, without implying
that deletion is running. Quit on this sheet goes through normal model shutdown
without an unfinished-history warning for a database the copy never opened. Idle
recovery and completed-reset sheets allow AppKit termination; only active cleanup
prevents it. The delegate also refuses quitting while cleanup is running.

Reset cancels pending model loading, drains the factory lease, closes SQLite and
then removes managed data. Directory roots cannot be symbolic links; child symlinks
are removed without following their targets. Audio export refuses destinations
inside the entire app-data directory, so exported copies survive full reset.

Permission reset uses `/usr/bin/tccutil reset All <current-bundle-id>` with a finite
deadline and an exact app-identity allowlist. Never use a system-wide reset, sudo or
edit TCC.db. The result screen provides the Accessibility settings link: macOS may
retain old path-based entries that the person must remove manually. Successful reset
holds the app closed to new work and offers Quit; reopening begins onboarding.

All destructive verification uses temporary data directories, isolated preferences,
metadata/deletion doubles and fake permission steps. Render/E2E containers skip
real Keychain, TCC, preferences and cache deletion. Playback tests use silent
transports; this workflow must never produce system sound.

Sources: [Apple: reset protected resources](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos),
[Apple: UserDefaults domains](https://developer.apple.com/documentation/foundation/userdefaults/persistentdomain(forname:)),
[Swift cooperative cancellation](https://forums.swift.org/t/is-task-cancellation-totally-cooperative/83100).
