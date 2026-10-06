---
version: 1
slug: "sources-app-views-configurationpage-swift"
primary_target: "Sources/App/Views/ConfigurationPage.swift"
related_targets: ["Sources/App/Views/SettingsSearch.swift", "Sources/App/Views/AutomationSettings.swift", "Sources/App/Views/MicrophonePicker.swift", "Sources/App/Views/DataCleanupSettings.swift", "Sources/App/Views/MainWindow.swift", "Sources/App/Views/MenuView.swift", "Sources/App/Views/Theme.swift", "Sources/App/Views/SoftControls.swift"]
---

# Configuration

Mode: Operate. Platform: native macOS SwiftUI.

## Direction

Keep settings discoverable and data removal scoped within the incumbent
Configuration page. Preserve its gray cards, shared row alignment, labeled
actions and native confirmation controls.

## Search composition and behavior

A recessed 270 by 28 pt Search settings capsule sits at the right of the title
row. Its native text field uses 13 pt type and an accent focus ring; the result
position uses 11 pt type. Previous/next and clear controls stay inside the field,
and an empty result set reads No matches. The existing page remains visible.

Search uses the actual section names, setting titles and full descriptions.
Every term must match, ignoring case, diacritics and character width. Exact
setting titles come first; remaining matches follow the page's reading order.
Matched rows have neutral recessed wells, with greater depth for the current
result. Each well sits 4 pt inside the card edge with 14 pt continuous corners,
concentric with the 18 pt card. Content retains the card's 16 pt inset.

Command-F focuses search. Return and Down move forward; Shift-Return and Up move
backward, wrapping through results. Escape clears a query and releases focus
when empty; clear keeps focus in the field. Preserve native text composition.
The current row scrolls to the visible center below the sticky header over
0.22 seconds, or instantly with Reduce Motion.

Typing settles for 160 ms before matching. Rebuild the in-memory index only
when row copy changes; scrolling does no indexing or matching. Search reveals
conditional controls with their prerequisites and preserves unavailable states.
Discovery never changes persisted settings or enables a prerequisite.

## Data cleanup composition

Data & reset follows Permissions and precedes Updates. Its single SettingsCard
contains History, Audio files, History and audio, and Start fresh. Supporting
text identifies what each action keeps. Removal buttons align at the right;
Reset App is the final action. RowDivider separates the rows. The card retains
equal 16-point insets and 18-point continuous corners.

Checking stored data appears within the card while the preview loads. A preview
error uses an inline notice with Retry, and successful partial cleanup adds a
short completion message. Existing light/dark styling and collapsed-sidebar
geometry remain unchanged.

## Confirmation and recovery

Each removal opens a native confirmation with the chosen scope, available counts
and approximate managed size, preservation details, Cancel and the destructive
action. Preview Retry reloads this information and requires confirmation again.
The four actions are disabled while checking or when cleanup, dictation,
history saving or downloads are active.

Active or interrupted cleanup uses a sheet that cannot be dismissed
interactively. Running work shows the current step. An interruption shows the
error and completed steps, with a prominent Retry for the same scope and Quit
Airdraft once work stops. Reset completion keeps the sheet open with Quit
Airdraft, instructions to reopen for setup, and a reminder that license and
trial records remain. Open Accessibility Settings accompanies manual removal
guidance for obsolete macOS entries.

During maintenance the menu bar exposes only Data Cleanup, Open Airdraft and
Quit Airdraft; Quit is disabled while work runs. Settings choices remain absent.
Shortening Keep recordings or choosing Off requires its separate native
confirmation, with Cancel retaining the previous setting.

## Scope and evidence

The visual system is docs/DESIGN.md; deletion scope is defined in
docs/data-cleanup.md. This change introduces no new visual tokens.

Search extends the existing code and components without a separate visual comp.
Reference images live under `.impeccable/review/settings-search/`.

Cleanup reference images live under `.impeccable/review/cleanup/`: Configuration in
`minimum/`, `tall/` and `collapsed/`; the sheet in `failed/cleanup-*` and
`complete/cleanup-*`; and the live window in `live/compositor.png`.
`live/reset-confirmation.png` records native confirmation layout; current source
owns its final copy. `live/retained-recording.png` shows the retained audio card.
Release and verification history belong in the vault.
