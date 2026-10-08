# Meeting recording

Record Meeting captures app audio and an optional microphone on macOS 15 or
later. It saves an independent recording before offering transcription. Starting
or stopping capture never starts ASR, uploads audio, inserts text or changes
dictation statistics.

## Capture and controls

Meetings is a dedicated sidebar page below History and above Models / Settings.
Its header contains Import and Record Meeting; the menu bar opens the same flow.
The compact setup sheet selects All Apps or one running app and an optional
microphone. Clicking App audio opens a 320-point chooser with 32-point app rows
and 4-point gaps. Its list has an explicit height derived from its content,
capped at seven complete rows, or 248 points. Empty states omit the scroll view;
loading, empty and permission messages resize the popup. Refresh keeps existing
rows visible and retains the selected app, marking it unavailable if it exits.
Browser selection includes all that browser's audio. Airdraft
excludes its own process audio. Microphone capture uses the device and optional
channel selected in the sidebar when recording starts.

`MeetingCaptureSession` uses ScreenCaptureKit `.audio` and `.microphone` outputs
on one serial queue. It registers no screen output and retains no video frames.
Screen & System Audio Recording permission is required; microphone access is
requested only when enabled. A missing selected device or app produces an error.
There is no echo cancellation: use headphones when microphone and speaker audio could feed back. The sheet
asks that participants know about recording.

Start closes setup and shows elapsed time plus Receiving/Waiting meters on
Meetings. Each source reuses the microphone picker's `MicrophoneLevelMeter`,
with ten fixed-height cells. `AudioLevel.meter` applies the same linear RMS × 8
response, clamped to 0...1, once in both microphone and meeting capture. The view
adds no gain or logarithmic curve; Receiving/Waiting describes buffer receipt
independently of the level. Leaving the page keeps recording; Meetings and the menu bar provide
Stop and Save. Starting offers Cancel; finishing shows saving progress.
The saved recording appears immediately with its date, duration and Transcribe
action, before any ASR runs. It remains in the library after restarting the app. Meeting work
shares the pipeline busy gate with dictation, media jobs and data cleanup.

Record Meeting, Start Recording, Stop and Save, Transcribe and Save Changes use
the shared `SoftButtonStyle(prominent: true)`: blue fill and white type with the
same raised capsule, pressed well and disabled geometry as secondary buttons.
The header actions share the 28-point control height.

## Timeline, storage and limits

- Capture normalizes each source to 16 kHz mono PCM using bounded buffers. Input
  presentation timestamps share one clock; late duplicate samples never overwrite
  accepted audio. Gaps remain on the timeline as sparse zero-filled regions.
- `MeetingStaging/<UUID>/` holds private raw 16-bit PCM files and session metadata.
  Recovery derives duration from file lengths, without needing a finalized WAV
  header. Directories use 0700 and files 0600 permissions.
- Stop drains callbacks and converter tails, closes the separate source files,
  then writes a 16 kHz, 16-bit stereo WAV in one-second buffers. Both channels
  contain the same microphone-plus-app mix. Each output sample is
  `(microphone + app audio) / N`, where `N` is the number of source files that
  contain samples. Two sources are averaged for headroom; a missing source does
  not halve the surviving source. Gaps and a shorter track contribute silence.
  The source count stays fixed for that recording.
- New captures and recovered drafts use this combined-channel format. It
  supersedes microphone-left/app-audio-right output; previously saved WAVs keep
  their original bytes. Separate source PCM and clocks remain internal to
  capture and recovery. Neither output channel identifies a speaker.
- The draft UUID is the recording ID. Adoption checks for an existing managed
  asset before completing recovery, preventing a duplicate after interruption.
  Staging is removed only after adoption; failed saves remain recoverable.
- Capture stops at two hours. Start requires 2,000,000,000 available bytes when
  capacity is reported; periodic writer checks stop below 256 MiB. There is no
  whole-recording sample array in capture or WAV finalization.
- Fifteen seconds without received audio buffers stops capture; this is not a
  silence detector. Capture more than five seconds behind the host clock also
  stops. Gaps over 0.25 seconds, missing sources and early track endings become
  recording details; interruption may leave an incomplete tail.

Sleep or capture failure cancels an unfinished start; during capture it stops
and saves. Normal Quit cancels an unfinished start, stops recording
and waits for finalization. After a process interruption, Meetings lists
individual dated drafts with a Recover Recording action. `scanDrafts` isolates
unreadable session metadata, preserving corrupt files while listing other valid
drafts. A separate recovery issue offers Retry to rescan. Recovery saves the
available audio without creating a transcript.

## Transcription and deletion

Every saved recording has a Transcribe action that opens `MediaImportSheet`
with that recording as an immutable payload; it never uses the most recent
capture as an implicit source. The user chooses
any supported local model or Soniox and speaker identification; cloud upload still requires
Upload and Transcribe. Local ASR reads a bounded stereo-to-mono average; SpeakerKit
uses the same downmix for its separate whole-session stage and memory preflight.
See [media transcription](media-transcription.md).

The library includes untranscribed audio, all transcript versions and transcripts
whose audio has been removed. Show in Finder opens the actual managed WAV;
Save Audio exports a byte-preserving copy. Managed data uses the legacy
`~/Library/Application Support/Transcribar/` root, with WAVs in `Recordings/` and
interrupted sessions in `MeetingStaging/`.

Meeting assets ignore dictation retention and remain until explicit audio
removal. Save Audio preserves both WAV channels. Global cleanup is in Settings, with
confirmations naming dictation and meeting data; History has no global-delete
action. Text-only cleanup preserves
recordings and interrupted drafts; audio-only, combined cleanup and Reset remove
them. Transcripts follow the existing independent text/audio deletion rules.
Schema v6 adds optional capture details to the recording asset.

## Verification boundary

Core tests exercise synthetic source clocks, gaps, resampling and tails,
interruption recovery, idempotent adoption, two-hour writing and cleanup. App
fixtures inject capture without opening input or output devices. These checks do
not establish actual OS permission behavior, simultaneous microphone/system
capture, drift, device changes or echo quality. Those results and release status
belong in the vault.
