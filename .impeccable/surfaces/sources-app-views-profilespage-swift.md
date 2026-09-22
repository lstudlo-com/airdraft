---
version: 1
slug: "sources-app-views-profilespage-swift"
primary_target: "Sources/App/Views/ProfilesPage.swift"
related_targets: ["Sources/App/Views/ProfileEditor.swift","Sources/App/Views/ProfileSheets.swift","Sources/App/Views/MainWindow.swift","Sources/App/Views/NavigationStyle.swift"]
---

# Profiles editor

Mode: Operate. Platform: native macOS SwiftUI.

## Direction

The user pinned a Codex-inspired native direction: compact monochrome navigation,
quiet selection, an open list/detail editor and secondary actions in native menus.
The task is to choose a profile, edit its behavior and return to dictation.

## Built composition

The shared 200-point sidebar and toolbar remain the window frame. Profiles has a
page heading, visible New profile action and page settings menu. Below, a
164-point scrolling list sits beside the independently scrolling editor.
Instructions are immediately visible. Task is a disclosure control that opens
when configured. Refinement-off profiles show an explanation instead of those
fields.

The profile heading wraps to two lines at rest and opens an inline rename field.
The icon picker and secondary actions use native menus. Editing selection and
active dictation profile remain separate; a checkmark identifies the active
profile. The selected profile exposes Use profile when inactive.

## Actions and recovery

Keep rename, duplicate, prompt preview, built-in reset and custom-profile deletion
in the profile menu. Keep Shared rules and Reset all profiles in the page menu.
Shared rules use Save, Cancel and Restore defaults in a sheet. Reset and delete
retain confirmations, and built-ins remain undeletable. Keep disabled menu states,
keyboard focus and accessible labels.

## Scope and evidence

The native design rules are in docs/DESIGN.md. Other pages keep their own layouts
and inherit shared spacing components; the marketing site remains separate.
No new raster assets are included.

The built review set covers clean, compact, wide, summary, verbatim and custom
profiles in light and dark appearances under .impeccable/review/profiles/.
The live prompt and shared-rules sheets are captured in
.impeccable/review/prompt-live.png and .impeccable/review/shared-rules-live.png.
The finish reviewer returned ship after the long-name heading defect was fixed.
These are build-review findings; committed-release and DMG verification remain
separate release requirements.
