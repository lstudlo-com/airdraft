---
version: 1
slug: "sources-app-views-meetingspage-swift"
primary_target: "Sources/App/Views/MeetingsPage.swift"
related_targets: ["Sources/App/Views/MeetingSheet.swift", "Sources/App/Views/MediaImportSheet.swift", "Sources/App/Views/MediaDocumentView.swift", "Sources/App/Views/MainWindow.swift", "Sources/App/Views/HistoryRecordingControls.swift", "Sources/App/Views/Theme.swift", "Sources/App/Views/SoftControls.swift"]
---

# Meetings library

Mode: Operate. Platform: native macOS SwiftUI.

## Direction

Extend Airdraft's existing gray neumorphic window with a durable library for
meetings and imported audio/video. Keep the shared raised cards and controls,
recessed tracks, engraved dividers and top-left lighting. The main window remains
784 points wide, with equal 16-point card insets and 18-point continuous corners.
The task is to save a recording, choose how to transcribe it, then return to its
audio and every transcript version after restarting the app.

## Built composition

The sidebar order is Home, Profiles, Vocabulary, History, Meetings, then Models
and Settings. History holds dictations. Meetings uses the shared page heading
with Import and the primary Record Meeting action at the right. Below it,
Recordings and Search meetings lead a single full-width card column. Collapsing
the sidebar preserves the shared icon rail and gives the cards the available
page width.

Record Meeting, Start Recording, Stop and Save, Transcribe and Save Changes use
`SoftButtonStyle(prominent: true)`. Blue fill and white type share the secondary
button's raised capsule, pressed well and disabled geometry. The page-header
actions share the 28-point control height.

Each card belongs to one recording. Title, date and duration lead the card;
untranscribed audio shows Ready to transcribe and Transcribe. The latest
transcript adds a three-line preview, stage, processing destination and Open
Transcript. Transcript Versions opens every saved run, labeled with its version,
date and model. New Transcription always starts from that card's audio and keeps
earlier versions. Show in Finder, playback, Save Audio and the secondary menu
stay within the same card. Removing audio leaves all transcript versions visible
with Transcript retained and Audio unavailable copy.

The library has loading, empty and no-match states, with Load More for further
records. Recording status, interrupted drafts and active transcription appear
above this searchable list, so a query cannot hide the current work. Page notices
keep their Dismiss or Retry action beside selectable error text.

## Recording setup and recovery

Record Meeting opens a 480-point sheet with an 18-point heading, one
SettingsCard, a short participant/local-storage notice and Cancel beside Start
Recording. App audio uses a raised selector; Include microphone uses the shared
switch below a RowDivider. The microphone follows the sidebar's selected device.

The app selector opens a 320-point popover with All Apps, individual running
apps, a selection checkmark and Refresh. App rows are 32 points high with
4-point gaps. The list has an explicit content-derived height, capped at seven
complete rows, or 248 points; additional apps scroll. Empty states omit the
scroll view. Loading, empty and permission messages resize the popup, with
Open Recording Permissions for recovery. Existing rows stay visible during
refresh. The selected app is retained; an exited app remains named with an
unavailable notice and blocks Start Recording.

Start closes the sheet and opens Meetings. The status card shows Starting,
Recording Meeting or Saving Recording, a 23-point monospaced elapsed time and
the appropriate Cancel, Stop and Save or progress control. App audio and an
enabled microphone each reuse the microphone picker's ten fixed-height meter
cells. Both capture paths apply `AudioLevel.meter` once, using linear RMS × 8
clamped to 0...1; the view adds no gain or logarithmic response. Receiving/Waiting
remains independent of amplitude. An omitted microphone has no meter row.
Leaving Meetings keeps capture running. Stopping saves the recording before
transcription is offered.

Interrupted recordings appear as individual dated rows with Recover Recording.
An unreadable draft has a separate Retry notice while valid drafts remain
available. Saved recording controls use the label Meeting audio and disclose
capture issues under Recording Details. New and recovered WAVs put the same
combined microphone/app mix in both stereo channels. Existing saved audio keeps
its original bytes, and Save Audio copies the file without remixing it.

## Transcription and editing

Import, file drop and a card's Transcribe action open the same 520-point
Transcribe Recording sheet with its exact source already attached. A single
SettingsCard holds Process audio, local Model, Language and Identify speakers.
On This Mac offers Whisper Large v3 Turbo, Qwen3-ASR 1.7B and 0.6B, Cohere
Transcribe, SenseVoice, FireRedASR2, Parakeet and Apple Speech. Keep language
validation, model readiness and explicit speech/speaker downloads in this sheet,
with progress, Cancel Download and errors. Preparation preserves the source and
options; transcription stays disabled until the required setup is ready.

Whisper retains word timestamps. Other local models show segment timestamps,
aligned to speaker intervals when identification is enabled. Speaker labels are
estimates and remain editable. Local copy states that audio stays on the Mac;
Soniox names upload and provider charges, and requires Upload and Transcribe.
The footer names Meetings as the destination and the two-hour input limit.

The 650 by 530-point editor keeps the title, Close, Edited/Original, Copy and
Export above the scrolling content. Shared speaker-name fields precede turn
cards with timestamp playback, speaker assignment and editable text. Show
overlap and segment-timing notices where applicable. Keep 100 turns per page,
full original text, and each incomplete version's Resume, Without Speakers or
Keep Transcript actions. A fixed footer holds Delete Transcript, active
playback, optional Summarize and Save Changes. Dirty edits require confirmation
before closing. TXT, JSON, SRT and VTT exports follow Edited/Original selection.

## Scope and evidence

Shared visual rules live in `docs/DESIGN.md`; processing and storage contracts
live in `docs/media-transcription.md` and `docs/meeting-recording.md`. This extends
the incumbent native design without a new visual world or web detector pass.

Reference captures live under `.impeccable/review/meetings/`: `min/`, `tall/`,
`collapsed/` and `empty/` contain `meetings-light.png` and `meetings-dark.png`;
`setup/` contains `meeting-setup-light.png` and `meeting-setup-dark.png`;
`editor/` contains `media-editor-light.png` and `media-editor-dark.png`.
These earlier synthetic records demonstrate library composition. The expanded
app chooser requires its own visible-row inspection; AX entries and a closed
setup sheet cannot establish that result. These captures do not establish real
capture permissions, audio quality, speaker accuracy or provider acceptance.
Release and verification history belong in the vault.
