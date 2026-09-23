---
name: Airdraft native macOS
description: Compact navigation and an open profile editor with restrained native controls.
typography:
  title:
    fontSize: "20pt"
    fontWeight: 600
  section:
    fontSize: "14pt"
    fontWeight: 600
  body:
    fontSize: "13pt"
    fontWeight: 400
  field-label:
    fontSize: "13pt"
    fontWeight: 500
  supporting:
    fontSize: "12pt"
    fontWeight: 400
  metadata:
    fontSize: "11pt"
    fontWeight: 400
rounded:
  navigation: "7pt"
  editor: "8pt"
  card: "12pt"
spacing:
  sectionTitleSpacing: "8pt"
  controlSpacing: "12pt"
  cardPadding: "16pt"
  sectionSpacing: "20pt"
  pagePadding: "24pt"
components:
  navigation-row:
    typography: "{typography.body}"
    rounded: "{rounded.navigation}"
    height: "32pt"
  text-editor:
    typography: "{typography.body}"
    rounded: "{rounded.editor}"
    padding: "{spacing.controlSpacing}"
  settings-card:
    rounded: "{rounded.card}"
    padding: "{spacing.cardPadding}"
---

# Design System: Airdraft native macOS

## Overview

**Creative North Star: "Codex-inspired native workspace"**

Airdraft uses compact navigation, monochrome SF Symbols, quiet selection and
native controls. The user chose the Codex reference for the sidebar and Profiles
editor. The editor gives instructions room and places secondary actions in menus.

This record describes the built sidebar, Profiles page and its sheets as inspected
on 2026-09-23. Other native pages inherit the shared spacing and components;
their complete layouts were not redesigned. The marketing site has a separate
[design system](../apps/marketing/DESIGN.md). Release verification remains a
separate gate; these workspace captures do not establish a published release.

**Key Characteristics:**

- System typography and appearance-aware colors.
- Compact navigation with full-row selection and plain symbols.
- Open editing areas, with boundaries around editable text.
- Native menus, disclosure controls, sheets and confirmation dialogs.

## Colors

Use SwiftUI and AppKit semantic colors, which resolve for the current appearance.
There is no fixed brand palette for this native workspace, so the frontmatter
does not substitute sampled screenshot colors for system colors.

### Primary

`Color.accentColor` marks focused text editors and native prominent controls.
Navigation icons and selection remain neutral. Native controls retain their
system appearance, including the accent shown in the live Save button.

### Neutral

The main background is `NSColor.windowBackgroundColor`; the sidebar uses
`NSVisualEffectView.Material.sidebar`. Text uses `.primary` and `.secondary`.
`NavigationRowStyle` applies `Color.primary` at 0.09 opacity for selection,
0.045 for hover and 0.14 for a press.

Text editors use primary color at 0.025 opacity, with a 0.13-opacity border.
Shared cards use a 0.05-opacity fill and a 0.06-opacity border. These are semantic
overlays, so keep the source color and opacity together.

**The Neutral Selection Rule.** Use the shared row style for navigation and
profile selection. Color does not identify a page or profile category.

## Typography

Use SwiftUI `.system` typography at the roles in the frontmatter. Titles are
semibold; ordinary navigation and editable prose are regular. Labels use medium
weight and supporting text uses secondary color. Leave tracking and line height
at native defaults except for the text editor's existing 3-point line spacing.

The resolved prompt preview uses system monospaced text. SF Symbols supply icons;
do not substitute text glyphs. The native system font is intentional and must not
be replaced with a web display font.

Profiles use the name in the selection list as their only visible title. New
profile and Rename profile open a focused inline `TextField` in that list. Short
rows may truncate names, but their tooltip and accessibility label contain the
full name.

## Layout

`Theme.swift` owns the spacing tokens above. The window has a 200-point sidebar
and a minimum size of 900 by 600 points. Navigation rows use
the documented component height and a 2-point gap. The sidebar separates daily
destinations from Configuration and Models with space rather than headings.

`PageScaffold` applies `pagePadding`, `sectionSpacing` and an 860-point maximum
content width. It has no empty title row or divider. Search controls, where
needed, appear at the top of the page content. The sidebar toggle sits at the
window's top left, just after the macOS traffic lights, and remains there when
the sidebar is collapsed. The sidebar moves with the existing 0.18-second
ease-in-out transition.

The selected microphone sits in a padded capsule above the sidebar footer.
The footer places a settings icon at the left and the word count at the right.
The capsule opens a spacious anchored device overlay with a live input meter.
The gear opens a centered Account and Subscription overlay with clearly labeled
sample data. The sidebar uses native frosted material against a transparent
window background.

Profiles uses a fixed 164-point list, a divider and a flexible editor. The list
and editor scroll independently. Profile rows are 36 points high and reuse the
navigation selection style. Keep the editor aligned with the selected row and
its single action menu reachable at the minimum window size; do not introduce
mobile breakpoints into this macOS layout.

**The Card Owns Its Insets Rule.** Settings sections use `PageSection` and
`SettingsCard`. `cardPadding` applies equally on all four sides. Rows inside a
settings card add no vertical padding. Use `sectionTitleSpacing` above content,
`sectionSpacing` between sections and `controlSpacing` between card children.

## Elevation & Depth

Sidebar material, subtle fills and dividers establish depth. Profiles has no
shadowed editor container. Native menus and sheets retain system presentation.
The existing keycap shadow belongs to the keycap component; it is not a general
rule for panels or buttons.

## Shapes

Use the navigation, editor and card radii for their respective components.
Shared cards have continuous corners and a half-point border. Editable text
areas have a half-point resting border that becomes a 1.5-point accent border
when focused. Keep these text-area boundaries even though the surrounding
Profiles editor is unboxed.

## Components

### Navigation

Each destination is a `Button` with a complete row hit area, a monochrome symbol
and a text label. Selection adds the accessibility selected trait. The active
dictation profile has a separate checkmark; selecting a profile for editing does
not activate it.

### Profile editor

The selected profile's settings begin with Refine transcript. Instructions lead
below it. The optional Task uses `DisclosureGroup` and opens when a stored task
is present. Turning refinement off replaces those fields with a short
explanation of the remaining transcript processing.

Keep New profile and one action menu above the list and editor. The menu
contains selected-profile rename, icon, duplicate, prompt preview and either
built-in reset or custom-profile deletion, followed by Shared rules and Reset
all profiles. The list checkmark identifies the active dictation profile;
an inactive selection shows Use profile beside the refinement switch. Do not
repeat the page or selected-profile name as an editor heading. Preserve native
disabled and destructive states and the existing confirmations.

### Text fields and sheets

`ProfileTextEditor` owns the label, empty-state guidance, border and focused
state. Profile changes save through their bindings. Shared rules use a draft in
a separate sheet with Save, Cancel and Restore defaults. The prompt preview is
scrollable, selectable text with a Done action. Keep the existing default and
cancel keyboard shortcuts.

Apple's [sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars)
and [menu guidance](https://developer.apple.com/design/human-interface-guidelines/menus)
are the platform references. The implemented disclosure and focus behavior uses
[DisclosureGroup](https://developer.apple.com/documentation/swiftui/disclosuregroup)
and [FocusState](https://developer.apple.com/documentation/swiftui/focusstate).

## Do's and Don'ts

- Do reuse `Theme`, `NavigationRowStyle`, `PageScaffold` and the shared settings
  components before adding local spacing or container styles.
- Do inspect light and dark appearances, the minimum window size, long names,
  configured Task fields, refinement-off profiles and the real sheets.
- Do keep secondary actions labeled in menus, with help and accessibility labels
  on their icon-only triggers.
- Don't add colored icon badges or a saturated selection fill to this sidebar.
- Don't wrap the Profiles editor in another card or move its primary instructions
  behind a disclosure control.
- Don't generalize the open Profiles composition into a ban on settings cards,
  native control borders or the existing app icon's neumorphic artwork.
- Don't treat review PNGs as shipped image assets. This redesign adds no raster
  assets, and browser-specific visual detectors do not validate SwiftUI output.
