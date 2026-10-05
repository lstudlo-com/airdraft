---
version: 1
slug: "meeting"
primary_target: "Sources/App/Views/MeetingSheet.swift"
related_targets: ["Sources/App/Views/HistoryPage.swift", "Sources/App/Views/MenuView.swift", "Sources/App/Views/MainWindow.swift"]
---

# Meeting recording surface

Extend the existing native gray window with a recording sheet; reuse the shared
materials and controls. Introduce no new palette, tokens or sidebar destination.

## Entry and setup

History's plus control is an Add Recording native menu containing Import Media
and Record Meeting. The menu bar also offers Record Meeting. Present the sheet
through the main window so it can be reopened while capture continues.

The 480-point sheet uses the existing page inset, 18-point heading and Close.
One SettingsCard holds App audio with SoftPicker and Choose App, then Include
microphone with SoftSwitch, separated by RowDivider. Keep the shared 16-point
card insets and 18-point corners. Supporting copy explains browser scope, the
sidebar microphone and headphones. Place Permissions beside its wrapping notice.
Keep the two-hour, separate-channel retention and post-save transcription note
above the primary Start Recording action.

## Capture and recovery

The active card leads with a 23-point monospaced timer and Stop and Save. Starting
shows Cancel; saving shows progress. Separate microphone and selected-app rows
show Receiving or Waiting for audio with labeled meters; disabled microphone
shows Off. Close remains available with copy explaining continued capture and
where to stop it.

History adds a compact Show Meeting or Recover Meeting notice. Saved recording
controls identify microphone left/app audio right and put capture issues in
Recording Details. Reuse the existing playback, Save Audio and native menu row.
The sheet's saved state offers Transcribe through MediaImportSheet; it does not
automatically begin transcription. Capture errors keep Dismiss in the same row;
recovery scan errors instead offer Retry. The Recover menu lists each valid draft
by date and time, even when another draft is unreadable.

## Evidence

Source contract: `docs/meeting-recording.md`; shared visual rules: `docs/DESIGN.md`.
Reference captures live under `.impeccable/review/meeting/` in `meeting-setup/`,
`meeting-recording/` and `history/`, each in light and dark. Synthetic receiving
meters demonstrate layout only; actual permissions, capture and echo quality
require separate verification.
