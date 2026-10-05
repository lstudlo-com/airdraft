---
version: 1
slug: "media"
primary_target: "Sources/App/Views/MediaDocumentView.swift"
related_targets: ["Sources/App/Views/MediaImportSheet.swift", "Sources/App/Views/HistoryPage.swift", "Sources/App/Views/HistorySnapshot.swift"]
---

# Media import and transcript documents

Mode: Operate. Platform: native macOS SwiftUI.

## Direction

Extend History's native gray cards and controls for file transcription. Keep the
file, processing stage and next available action visible. Speaker labels remain
editable estimates; the interface makes no transcription-quality claim.

## Import

History adds an Import Media plus button beside search and accepts one dropped
file. The 480-point import sheet places the file name above one SettingsCard with
Transcription, Language and Identify speakers. Use SoftPicker, SoftSwitch and
RowDivider. Missing local models expose Open Models or an explicit speaker-model
Download action with progress and Cancel.

Supporting text explains local or Soniox processing, retained WAV audio, the
two-hour limit and the destination in History. The primary action is Transcribe
or Upload and Transcribe. Keep Cancel secondary and disable starting while a
required model is missing or other work is active.

## History and editor

Media documents share History's date grouping, 52-point timeline and recording
controls. Their cards show a title, stage, bounded text preview and engine name.
Active work shows progress and Pause; incomplete work can expose Resume or Keep
Transcript. Open Transcript opens the editor.

The 650-by-530-point editor keeps title and Close above Edited/Original, Copy and
the native Export menu. Speaker-name fields precede turn cards. Add Speaker and
the estimate notice remain adjacent. Each turn has a timestamp, speaker selector,
optional overlap notice and text. Show at most 100 turns per page with Previous
and Next. Preserve shared card insets, corner radius and system typography.

The footer holds Delete Transcript, active playback control, optional Summarize
and Save Changes. Editing is disabled until processing completes. Unsaved changes
require a discard confirmation; summaries require explicit confirmation and
saved edits. Deleting a transcript explains that its recording stays.

## Scope and evidence

The implementation contract is docs/media-transcription.md and the visual rules
are docs/DESIGN.md. This extension introduces no new visual tokens or branding.
Reference captures belong in `.impeccable/review/media/` under `media-import/`,
`media-editor/` and `history/`. Match captures to current sources before review;
fixtures and synthetic text do not demonstrate model accuracy. Verification and
release status belong in the vault.
