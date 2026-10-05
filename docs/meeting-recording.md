# Meeting recording

Record Meeting captures app audio and an optional microphone on macOS 15 or
later. It saves an independent recording before offering transcription. Starting
or stopping capture never starts ASR, uploads audio, inserts text or changes
dictation statistics.

## Capture and controls

History's Add Recording menu contains Import Media and Record Meeting; the native
menu bar also offers Record Meeting. The setup sheet explicitly selects All Apps
or one running app. Browser selection includes all that browser's audio. Airdraft
excludes its own process audio. Microphone capture uses the device and optional
channel selected in the sidebar when recording starts.

`MeetingCaptureSession` uses ScreenCaptureKit `.audio` and `.microphone` outputs
on one serial queue. It registers no screen output and retains no video frames.
Screen & System Audio Recording permission is required; microphone access is
requested only when enabled. A missing selected device or app produces an error.
There is no echo cancellation: the setup sheet recommends headphones and asks
that participants know about recording.

The sheet shows elapsed time and separate Receiving/Waiting for audio meters.
Close leaves capture running; History and the menu bar reopen the sheet or stop
and save. Starting offers Cancel; finishing shows saving progress. Meeting work
shares the pipeline busy gate with dictation, media jobs and data cleanup.

## Timeline, storage and limits

- Capture normalizes each source to 16 kHz mono PCM using bounded buffers. Input
  presentation timestamps share one clock; late duplicate samples never overwrite
  accepted audio. Gaps remain on the timeline as sparse zero-filled regions.
- `MeetingStaging/<UUID>/` holds private raw 16-bit PCM files and session metadata.
  Recovery derives duration from file lengths, without needing a finalized WAV
  header. Directories use 0700 and files 0600 permissions.
- Stop drains callbacks and converter tails, closes the files, then writes a
  16 kHz stereo WAV in one-second buffers: microphone left, app audio right. The
  shorter or disabled track is padded with silence. These channels are sources,
  not speaker identities; app audio may contain multiple speakers.
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
and waits for finalization. After a process interruption, History exposes Recover
Meeting; its recovery menu lists individual dated drafts. `scanDrafts` isolates
unreadable session metadata, preserving corrupt files while listing other valid
drafts. A separate recovery issue offers Retry to rescan. Recovery saves the
available audio without creating a transcript.

## Transcription and deletion

After saving, Transcribe opens the existing `MediaImportSheet`. The user chooses
local Turbo or Soniox and speaker identification; cloud upload still requires
Upload and Transcribe. Local ASR reads a bounded stereo-to-mono average; SpeakerKit
uses the same downmix for its separate whole-session stage and memory preflight.
See [media transcription](media-transcription.md).

Meeting assets ignore dictation retention and remain until explicit audio
removal. Save Audio preserves both WAV channels. History-only cleanup preserves
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
