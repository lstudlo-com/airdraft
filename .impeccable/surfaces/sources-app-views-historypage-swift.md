---
version: 1
slug: "sources-app-views-historypage-swift"
primary_target: "Sources/App/Views/HistoryPage.swift"
related_targets: ["Sources/App/Views/HistorySnapshot.swift", "Sources/App/Views/HistoryRecordingControls.swift", "Sources/App/Views/HistoryPlayback.swift", "Sources/App/Views/Theme.swift", "Sources/App/Views/SoftControls.swift"]
---

# History recordings

Mode: Operate. Platform: native macOS SwiftUI.

## Direction

Extend the incumbent gray native History page so saved dictation audio can be found,
played and exported. Preserve the existing timeline, transcription cards,
neumorphic controls and native secondary menus.

## Built composition

The title and search remain in the shared page heading. Global cleanup lives in
Settings; History never clears invisible meeting data. An
All/Recordings segmented picker sits below it, opposite the current Keep
Recordings setting. The retention action opens Settings.

The 52-point timeline and the card column scroll independently with a shared
12-point gap. Both use the active filter and search. Timeline headings show
calendar dates; the card column can use Today and Yesterday. The active tick
follows the current card, and returning the cards to the top restores the first
timeline heading.

Transcript cards keep Copy, Details and version selection. Saved audio adds one
row below a RowDivider. Recordings without a saved transcript use the same
raised card with Recording, a timestamp and No saved transcript. Both card types
keep equal 16-point insets and 18-point continuous corners.

The shared recording row contains play/pause, a flexible recessed slider,
monospaced elapsed/total time, Save Audio and a native ellipsis menu. The slider
becomes available for the active recording, with 0.1-second drag steps and
five-second arrow-key seeking while focused. Save Audio remains a labeled
button; the menu holds Show in Finder, available Retranscribe, and available
Delete Recording Only actions. The lightweight accessibility rows expose the
same shared file actions as direct buttons.

## Actions and recovery

Filter and search changes, leaving History and starting dictation stop playback.
Save Audio opens a native WAV save panel and shows Saving during export.
Recording-only deletion has its own confirmation and keeps an attached
transcript. Dictation deletion removes its recording too. Unavailable actions
stay hidden or disabled according to their existing state.

Empty results hide the timeline. When no recordings remain and retention is off,
supporting text points to Keep Recordings for future dictations. Storage and
playback errors use the page's existing notice with its recovery action.

## Scope and evidence

The visual rules are in docs/DESIGN.md. This is a History extension within that
system. The fixed width remains 784 points. The minimum content height is 600
points; the minimum reference capture has a 632-point outer height.

Reference captures are the light and dark History images in
`.impeccable/review/history/recordings-min/`, `all-tall/` and
`detached-collapsed/`. The last set includes an audio-only card with the sidebar
collapsed. `live/compositor.png` records the live window treatment. These are
local reference captures; release and verification history belong in the vault.
