# Media transcription

Imported audio and video become `TranscriptDocument` records in History.
`MediaJobRunner` owns their processing independently of dictation: it never
inserts text at the cursor or adds to dictation statistics. The import sheet
captures the engine, language and speaker-identification choice for that job.

## Input and storage

- Import one file through History’s Add Recording → Import Media menu or file
  drop. Record Meeting in the same menu opens audio capture. AVFoundation
  must decode exactly one audio track. Multiple-track files are rejected with an
  instruction to export the desired track separately.
- Both source duration and decoded audio must be positive and at most two hours.
  The decoder writes a managed 16 kHz mono, 16-bit PCM WAV through bounded buffers.
  It does not play the source or modify the original file.
- `RecordingAsset.source == .imported` keeps this WAV independent of dictation's
  Keep recordings setting. It remains until explicit audio removal. Deleting a
  transcript keeps its recording; deleting audio clears the document's recording
  reference while retaining its text. External originals and exported copies stay.
- The `mediaDocument` table stores indexed title/text plus a versioned document
  payload. Updates require the current revision, so a stale editor or callback
  cannot overwrite a newer document or recreate a deleted one.

Saved [meeting recordings](meeting-recording.md) reuse the import sheet after
capture stops. They retain a 16 kHz stereo WAV (microphone left, app audio right);
local processing averages the channels when reading samples. This does not assign
speaker identity by channel. The existing whole-session SpeakerKit memory check
still applies. Meeting capture itself performs no transcription or upload.

See [recording storage](recording-storage.md) and [data cleanup](data-cleanup.md)
for shared storage and deletion contracts.

## Local processing

The local engine is WhisperKit with `large-v3-v20240930_turbo`. Media jobs validate
that exact model independently of the dictation model. The user installs it in
Models. Speaker identification has a separate, explicit SpeakerKit download;
inference uses local files with automatic downloading disabled. Language choices
pass through `SpeechLanguagePolicy` before processing.

ASR reads at most 31 seconds from the WAV to choose a quiet boundary and sends
at most 25 seconds to WhisperKit. Each successful window saves words with absolute
timestamps, partial turns and the completed offset, so saved progress remains
readable and exportable. Pause cancels the current operation; Resume
reloads the saved configuration and offset. An interrupted normalization has no
resumable document until the managed recording and document exist.

After ASR finishes, optional SpeakerKit identification unloads speech models and
clusters the whole session. It is a separate memory-intensive stage, not a series
of independently numbered chunks. Preflight requires available free plus inactive
memory above `duration × 16,000 × 4 × 4 + 1,500,000,000` bytes. Workers are bounded,
but this check is an allocation estimate, not a promise that every two-hour file
fits every Mac.

Speaker reconciliation chooses the interval with greatest word overlap, leaves
gaps unknown and marks overlapping speech. IDs are estimates, never inferred
personal names. If identification fails, completed ASR text remains available;
Resume retries the remaining stage, or Keep Transcript completes without it.

## Soniox processing

Cloud use requires choosing Soniox and confirming Upload and Transcribe. The sheet
states that audio leaves the Mac, the user's API key is used, charges may apply,
and a local WAV remains. The long-file adapter uploads from a staged multipart
file, then creates an asynchronous job with the captured language and optional
speaker identification.

The document saves returned file and job IDs before the next request. Resume
reuses those IDs instead of uploading again. Completion deletes known provider
resources; document deletion and app cleanup also perform that cleanup first.
A failed cleanup keeps its IDs and error for retry. Cancellation preserves the
job for Resume; it does not assert that provider-side processing stopped.

## Editing, exports and summary

Original word text and timestamps remain alongside turns with optional edited
text and speaker assignments. Completed documents support title edits, speaker
renaming, reassignment, adding a speaker and Unknown Speaker. Edited/Original
selects the displayed text and the version used by Copy and Export. Speaker
display names are shared between versions. The editor shows 100 turns per page;
timestamp buttons play the retained recording from that point when available.

Save Changes uses the document revision. Closing a dirty editor asks before
discarding changes. An editor opened during processing must be reopened for the
latest result; editing remains unavailable until the document is complete.

TXT, JSON, SRT and VTT exports use a native save panel. JSON includes original
words, turns, speaker names and the optional summary; it excludes internal remote
IDs. Subtitle files preserve turn times and speaker labels. Original export
removes per-turn edits and reassignment and omits the summary. Export cannot write
inside the managed app-data directory.

Summarize is an explicit action using the selected refinement provider, with a
confirmation about text transfer and cost. It requires saved edits. Requests use
sections of at most 8,000 characters, including splitting a long edited turn.
Results remain ordered section summaries, with no unbounded final merge request.
History labels this operation Summarizing and offers Cancel. Cancellation or
failure leaves the transcript unchanged.

## Ownership and validation

`MediaAudioDecoder` normalizes files; `MediaJobRunner` checkpoints stages;
`LocalSpeakerDiarizer` owns global speaker inference; `SonioxMediaTranscriber`
owns remote jobs. `MediaDocumentStore` owns persistence and mixed History queries,
and `TranscriptExport` owns export formats. `AppContainer` makes media processing
mutually exclusive with dictation and data maintenance.

Tests use disposable roots, injected decoders, mocked HTTP and silent playback
transports. They must never play sound or use daily data or credentials. Synthetic
30-, 60- and 120-minute fixtures test window bounds, offsets and stage persistence;
they do not establish ASR accuracy, speaker quality or real long-file performance.
Recorded-speech inference is a separate opt-in test. Release and acceptance
results belong in the vault, not this implementation contract.
