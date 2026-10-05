# Recording storage

`HistoryStore` owns `history.sqlite` and the private `Recordings` directory.
`recordingAsset` owns audio independently of `dictation`; `recordingID` is an
optional foreign key. Assets contain only an ID, creation time, filename, duration
and source. Transcript text, app context and speaker labels must not be copied
into audio metadata.

Migration `v4-recording-assets` adopts valid existing WAV files in place. Missing
or unsafe files lose their old reference without losing transcript text. The
legacy `audioFilename` field remains a mirrored compatibility field. New saves
create the WAV, asset and dictation under one SQLite writer lease; failed inserts
remove their new sidecar.

| Operation | Text | Managed audio |
|---|---|---|
| `deleteHistoryKeepingAudio` | Remove all | Preserve assets and files |
| `deleteRecording` | Preserve | Remove selected asset and clear its links |
| `deleteAllAudio` | Preserve | Remove all assets, files and recognized orphan writes |
| `delete(id:)` | Remove selected dictation | Remove its audio unless another dictation references it |
| `deleteAll` | Remove all | Remove all, including detached assets |

Dictation retention applies to detached dictation assets too. Imported and meeting
assets are independent of dictation retention. Orphan cleanup retains every
surviving asset filename, even after transcript deletion. Unknown files, directories
and symlinks are not recursively deleted. A file removal failure leaves database
metadata available for retry; bulk failures can have already removed some files,
so the UI must refresh availability and report failure rather than claim rollback.

Recording queries filter in SQLite before paging. Their continuation offset counts
scanned rows, including missing files. Prepare availability on a background task,
not in SwiftUI row bodies. A recording detached from history cannot match deleted
transcript or app-name searches.

`exportRecording` copies the existing bytes, with no playback or re-encoding.
Export and deletion share a SQLite writer lease across store instances. Copy to a
temporary file beside the destination, synchronize it, then publish it. Explicit
replacement is required for an existing destination. Never export into the managed
app-data directory. The exported copy belongs to the user and survives cleanup.

History uses one timeline with All and Recordings filters. Audio-only entries keep
their own date and duration without retaining deleted text. A single injected
playback controller owns pause/resume and seeking; only its active progress view
observes the clock. Native Save Audio and Show in Finder expose the managed WAV.
Retranscription remains review-only even for detached assets. Missing files never
produce playable rows, and changing the filter, starting dictation, cleanup or
leaving History stops playback.

Destructive fixtures must use temporary stores. All tests for this work remain
silent: read files or inject samples, and use fake playback transports. Debug
render fixtures use a silent transport even when their Play control is activated.

References: [GRDB migrations](https://swiftpackageindex.com/groue/GRDB.swift/documentation/grdb/migrations),
[SQLite foreign keys](https://www.sqlite.org/foreignkeys.html).

Configuration cleanup and reset coordination are defined in `data-cleanup.md`.
