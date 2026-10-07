# Media transcription

Imported audio and video become `TranscriptDocument` records in Meetings.
`MediaJobRunner` owns their processing independently of dictation: it never
inserts text at the cursor or adds to dictation statistics. The import sheet
captures the engine, language and speaker-identification choice for that job.
Its immutable presentation payload contains the chosen file or recording, so the
first opening cannot race an empty selection. Each recording has a direct
Transcribe action; further transcriptions create versions without replacing text.
An active-job card remains visible even when search or pagination hides its row.

## Input and storage

- Import one file through Meetings → Import or file
  drop. Record Meeting opens audio capture from that page. AVFoundation
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

The job captures one of eight local model choices: Whisper Large v3 Turbo,
Qwen3-ASR 1.7B (5-bit) or 0.6B (4-bit), Cohere Transcribe 2B (5-bit),
SenseVoice Small, FireRedASR2, Parakeet TDT v3, or Apple Speech. Each routes to
its existing local adapter. No selection follows later dictation-setting changes.
Legacy payloads without the added selection retain Whisper Turbo. Exact model
IDs and language capabilities come from `MediaConfiguration` and
`SpeechLanguagePolicy`; Cohere requires a language and Apple uses its displayed
locale. Parakeet does not support Chinese.

Speech and SpeakerKit downloads are explicit actions inside transcription setup;
the selected source and options remain in the sheet. Apple checks actual language
asset readiness, and media inference refuses to install missing assets implicitly.
Switching to Apple maps the current language to its displayed locale and clears
the old language hint.

Whisper reads at most 31 seconds to select a quiet boundary and decodes at most
25 seconds, retaining native word timestamps. Optional SpeakerKit runs afterwards,
unloading speech models and clustering the whole session. Other engines identify
speakers first and checkpoint those intervals before ASR. `MediaSegmentPlan`
builds speech turns of at most 25 seconds with integer-frame offsets. It keeps
the longest active utterance as the estimated primary speaker, retains an overlap
warning, and joins same-speaker pauses up to 0.5 seconds without crossing another
speaker turn. Tiny overlap edges therefore stay in their utterance context.
Unassigned speech activity is transcribed as Unknown. Uncovered regions are not
decoded separately; no detected regions offers Without Speakers recovery instead
of a false empty success. This does not separate simultaneous voices. Without
speaker identification, engines use bounded unlabelled windows and require no SpeakerKit.
Only exact digital silence is skipped by the ASR adapter; quiet nonzero speech is preserved.

These additional engines return **segment timing**, not measured word timing.
Each decoded segment retains its full text and audio bounds; JSON marks its
`timing` as `segment` and the editor identifies segment timestamps. Partial
segments are never checkpointed after cancellation. Each completed slice saves
text plus the next offset atomically; Resume reuses the saved model, language,
speaker intervals and offset. It neither renumbers speakers nor changes engines.

SpeakerKit's whole-session memory preflight requires available free plus inactive
memory above `duration × 16,000 × 4 × 4 + 1,500,000,000` bytes. Workers are bounded;
this remains an estimate, not a guarantee that every two-hour file fits every Mac.
Speaker IDs are estimates, never inferred personal names. Failed speaker detection
has Resume and Without Speakers actions, including before any text exists. If ASR
already finished, Keep Transcript completes the existing text without detection.
All transcript versions retain these actions when opened in the editor.

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
discarding changes. An unedited open document refreshes when processing completes; editing remains
unavailable until its job is complete.

TXT, JSON, SRT and VTT exports use a native save panel. JSON includes original
words, turns, speaker names and the optional summary; it excludes internal remote
IDs. Subtitle files preserve turn times and speaker labels. Original export
removes per-turn edits and reassignment and omits the summary. Export cannot write
inside the managed app-data directory.

Summarize is an explicit action using the selected refinement provider, with a
confirmation about text transfer and cost. It requires saved edits. Requests use
sections of at most 8,000 characters, including splitting a long edited turn.
Results remain ordered section summaries, with no unbounded final merge request.
Meetings labels this operation Summarizing and offers Cancel. Cancellation or
failure leaves the transcript unchanged.

## Ownership and validation

`MediaAudioDecoder` normalizes files; `MediaJobRunner` checkpoints stages;
`LocalSpeakerDiarizer` owns global speaker inference; `SonioxMediaTranscriber`
owns remote jobs. `MediaDocumentStore` owns persistence; `MeetingLibrary` queries non-dictation audio
with every attached document version and transcript-only records,
and `TranscriptExport` owns export formats. `AppContainer` makes media processing
mutually exclusive with dictation and data maintenance.

Tests use disposable roots, injected decoders, mocked HTTP and silent playback
transports. They must never play sound or use daily data or credentials. Synthetic
30-, 60- and 120-minute fixtures test window bounds, offsets and stage persistence;
they do not establish ASR accuracy, speaker quality or real long-file performance.
Recorded-speech inference is a separate opt-in test. Release and acceptance
results belong in the vault, not this implementation contract.
