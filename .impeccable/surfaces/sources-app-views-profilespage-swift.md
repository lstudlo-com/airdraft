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

The shared 200-point sidebar remains the window frame. The sidebar
toggle sits beside the macOS traffic lights even when the sidebar is hidden.
The microphone picker sits above the dictation word count at the bottom of the
sidebar. The content begins without an empty title row. Profiles has a visible New
profile action and one action menu. Below, a 164-point scrolling list sits
beside the independently scrolling editor.
Instructions are immediately visible. Task is a disclosure control that opens
when configured. Refinement-off profiles show an explanation instead of those
fields.

The list name is the only profile title and becomes an inline rename field.
Icon selection and secondary actions share the page menu. Editing selection
and active dictation profile remain separate; a checkmark identifies the active
profile. The selected profile exposes Use profile when inactive. The right
editor starts with Refine transcript, without repeated page or profile titles.

## Actions and recovery

Keep rename, icon selection, duplicate, prompt preview, built-in reset,
custom-profile deletion, Shared rules and Reset all profiles in one menu.
Shared rules use Save, Cancel and Restore defaults in a sheet. Reset and delete
retain confirmations, and built-ins remain undeletable. Keep disabled menu states,
keyboard focus and accessible labels.

## Scope and evidence

The native design rules are in docs/DESIGN.md. Other pages keep their own layouts
and inherit shared spacing components; the marketing site remains separate.
No new raster assets are included.

The review set covers clean, compact, wide, summary, verbatim and custom
profiles in light and dark appearances. Live checks cover the single action
menu, inline rename, new profile, prompt preview, sidebar toggle and microphone
picker. Committed-release and DMG inspection remain separate release gates.
