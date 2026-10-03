---
version: 1
slug: "sources-app-views-profilespage-swift"
primary_target: "Sources/App/Views/ProfilesPage.swift"
related_targets: ["Sources/App/Views/ProfileEditor.swift","Sources/App/Views/ProfileSpeechSettings.swift","Sources/App/Views/ProfileSheets.swift","Sources/App/Views/ModelsPage.swift","Sources/App/Views/MainWindow.swift","Sources/App/Views/NavigationStyle.swift"]
---

# Profiles editor

Mode: Operate. Platform: native macOS SwiftUI.

## Direction

Keep the incumbent native neumorphic design, compact monochrome navigation and
secondary actions in native menus. The task is to choose a profile, edit its
dictation behavior and optional speech model, then return to dictation.

## Built composition

The shared 784-point window contains one scrolling editor. New Profile and the
action menu sit at the right of its heading. A compact 200-point profile picker
sits in the Profile section heading, followed by a card with Name, Dictation
and Refine transcript rows. Dictation shows In Use or Use Profile. Editing
selection stays separate from activation.

Speech model comes next. Its 240-point picker offers Use App Default and local,
cloud or saved speech recognition models. The readout names the resolved model,
explains missing downloads or unavailable selections, and identifies where cloud
audio is sent. Models opens setup. Use App Default inherits the global Models
choice; language and script settings remain shared. An active binding adds a
Models notice explaining that selections there edit the app default.

Instructions follows, with an optional Task disclosure that opens when configured.
Refinement off hides these fields, retains Speech model, and explains that
vocabulary and script conversion still apply. The shared Base system prompt is
last. Use the existing PageSection, SettingsCard, RowDivider and soft controls,
with 16-point card insets and 18-point corners.

## Actions and recovery

The action menu contains rename, duplicate, prompt preview, built-in reset or
custom-profile deletion, and Reset All Profiles. Name commits on Return or focus
loss; an empty edit restores the saved name. Base system prompt has its own Edit
button and warning. Preserve confirmations, disabled states, keyboard focus and
accessible labels.

## Scope and evidence

The native design rules are in docs/DESIGN.md. This extension adds the profile
speech-model choice and the related Models notice within that design.

Reference captures are in `.impeccable/review/profile-speech/states/`, including
local and cloud bindings, refinement off, and light and dark appearances.
`live-bound.png` and `live-models-override.png` in the parent folder show the
active binding and its Models notice. Release and verification history belong
in the vault.
