---
name: Airdraft native macOS
description: Compact navigation and an open profile editor with restrained native controls.
typography:
  title:
    fontSize: "18pt"
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
    fontSize: "11pt"
    fontWeight: 400
  metadata:
    fontSize: "11pt"
    fontWeight: 400
rounded:
  navigation: "7pt"
  editor: "8pt"
  card: "18pt"
  island: "12pt"
spacing:
  islandInset: "10pt"
  sectionTitleSpacing: "12pt"
  controlSpacing: "12pt"
  cardPadding: "16pt"
  sectionSpacing: "28pt"
  pagePadding: "24pt"
components:
  section-title:
    typography: "{typography.section}"
    minHeight: "32pt"
    textLeadingInset: "4pt"
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
    elevation: "raised, half the hero's shadow spread"
  soft-control:
    height: "28pt"
    elevation: "raised, a quarter of the hero's shadow spread"
  content-island:
    rounded: "{rounded.island}"
    inset: "{spacing.islandInset}"
---

# Design System: Airdraft native macOS

## Overview

**Creative North Star: "Codex-inspired native workspace"**

Airdraft uses compact navigation, monochrome SF Symbols, quiet selection and
raised neumorphic cards and controls lit from the top left. The user chose the Codex reference for the sidebar and Profiles
editor. The editor gives instructions room and places secondary actions in menus.

This record describes the built sidebar, Profiles page and its sheets as inspected
on 2026-09-23. Other native pages inherit the shared spacing and components;
their complete layouts were not redesigned. The marketing site has a separate
[design system](../apps/marketing/DESIGN.md). Release verification remains a
separate gate; these workspace captures do not establish a published release.

Onboarding and licensing were refreshed from the working tree on 2026-09-29.
Their readable design record is maintained in the Airdraft Obsidian vault:
[Onboarding and Licensing](obsidian://open?vault=Airdraft&file=Product%2FDesign%20System%2FOnboarding%20and%20Licensing).

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

Pages sit on `Theme.islandBackground`: white level 0.90 in light mode and 0.15
in dark mode. In both appearances the island stays darker than the chrome and at
the Home hero's surface gray (0.91–0.89 light, around the base; 0.19–0.17 dark,
just above it), so the hero and other neumorphic elements rise softly from it
instead of floating on white or near-black. The light mid-tone leaves the white
highlight about 0.10 of headroom; the light hero's well (0.85) and bars
(0.79–0.54) step down from its surface in the same order. Light cards (0.91–0.89),
controls (0.93–0.89) and inset tracks (0.85) follow the same step. The chrome is
therefore the lighter layer in both appearances. The window chrome, behind the sidebar and around the island, uses
`SidebarBackground`: one fully opaque neutral color, white level 0.95 in light
mode and 0.21 in dark mode, with no translucency or desktop blur. The window
itself is opaque with the same background color.
The island has no divider beside the sidebar. Its 0.5-point edge uses primary
color at 0.06 opacity in light mode, 0.08 in dark mode and 0.35 with Increase
Contrast. It casts no shadow, since it sits below the chrome.
Text uses `.primary` and `.secondary`.
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

The sidebar brand is a standalone neumorphic capsule without visible lettering.
`SidebarBrandMark` in `MainWindow.swift` keeps the app icon's five waveform
levels and separated caret, scaling the original compact mark proportionally
by 1.4 to about 57 by 28 points in a 30-point row.
The capsule is raised without an outline: its face is the sidebar itself, with
no fill or edge stroke, lifted by soft, wide shadows that light the top left and
shade the bottom right. A rim stroke or tight highlight would read as an outline.
The waveform bars and caret are carved into it as grooves: a darker floor (0.80
light, 0.12 dark), shaded inside the top-left edge and lit at the bottom right.
Increased contrast adds explicit edges to the capsule and grooves. Keep the original leading alignment
and header spacing, with 54 points above and 20 points below the row.
It has no hover, click or meter behavior.
Expose it as one image named `Airdraft` to assistive technology. The License
sheet reuses the same view at 32 points through its `height`
parameter; shadow depth scales with it, and the sidebar size is unchanged.

The outlined `SidebarWordmark.imageset/wordmark.svg` remains the website and
installer wordmark. Regenerate that asset with
`swift scripts/render-sidebar-wordmark.swift`; sidebar branding no longer
renders it.

Profiles use the name in the selection list as their only visible title. New
profile and Rename profile open a focused inline `TextField` in that list. Short
rows may truncate names, but their tooltip and accessibility label contain the
full name. The rows have no profile-specific icons. Return or moving focus away
commits a non-empty name; an empty edit keeps the previous name.

## Layout

`Theme.swift` owns the spacing tokens above. The window has a 180-point expanded
sidebar and a fixed width of 784 points. Every page, including onboarding, renders
inside one rounded content island (`.contentIsland()`), inset 10 points from the
window's top, trailing and bottom edges. The gutter repeats the sidebar's content
inset, which also forms the island's leading gutter, so the selected row sits
centered between the window edge and the island. Window controls, the sidebar and
its toggle stay on the chrome; the recording HUD is a separate panel. The collapsed sidebar remains an icon
rail, sized from the unchanged brand width plus its 20-point inset on each side,
about 91 points total. Destination, microphone and license icons are
centered horizontally and keep the same vertical positions, row heights and
group spacing as the expanded sidebar. Text and the microphone chevrons disappear;
tooltips, accessible names and selection remain. The footer keeps the license
button in all builds. Height resizes from a 600-point minimum.
Close and Minimize have 16-point top and leading insets within a 46-point
titlebar, with the sidebar toggle aligned to their centers. The green zoom/full-screen button is
hidden and full-screen/tiling is disabled. Navigation rows use
the documented component height and a 2-point gap. The sidebar separates daily
destinations from Configuration and Models with space rather than headings.

`PageScaffold` applies `pagePadding` and `sectionSpacing` across the available
content width. Section headings, heading controls and cards share a right edge.
Settings pickers use `SoftPicker`, a raised capsule whose visible edge aligns
with the card's trailing 16-point inset. Editable numeric settings use
`SettingsNumberStepper` for direct entry and arrow adjustments. Every page has
the same header row: its destination name on the
left and page controls on the right. Profiles keeps New Profile and its action
menu together in that right-side control group. Comparable actions use the shared
compact capsule treatment. The sidebar toggle sits at the
window's top left, just after the macOS traffic lights. The compact rail is too
narrow for both, so the toggle moves into the island's heading row, entirely
outside the rail. Its symbol aligns with the page title's leading inset and its
center with the heading row.
The native window controls retain their 46-point titlebar. Page headings have
a separate 32-point row, inset 16 points from the island's top with 12 points below.
`PageScaffold` keeps this header fixed with `safeAreaInset`. The island clips the
header and its blur to its rounded top; the blur never samples the chrome.
`ProgressiveHeaderBlur` covers the 60-point header plus a 4-point outer feather.
The 64-point blur is centered on the heading row, whose center is 32 points
from the island's top. The feather joins the clear page to a visible 1-point
blur at the bottom of the header. From there, the radius increases quadratically
to 32 points at the top. Text entering the header must soften while its letter
shapes remain identifiable. The 24-point scroll-content inset remains below
the header; the blur no longer covers that whole inset.
The radius mask drives the blur filter; it never changes the
opacity of a material or adds a tint. Header labels and controls remain above
the filtered layer and stay sharp. Suppress the system's hard scroll-edge separator
on macOS 26+. The implementation isolates the undocumented `CABackdropLayer` and
`CAFilter` variable-blur APIs behind capability checks. If they are unavailable,
use standard within-window header material; it does not provide variable radius.
Verify live compositing after macOS upgrades. No screen capture, scroll snapshots
or per-frame application rendering are used.
Only Reduce Transparency replaces the blur with a solid background.
History puts its top content margin inside both scroll views so both columns
can pass beneath the header. Its timeline uses calendar-date headings such as
Sep 25 for every day; only the main card column uses Today and Yesterday.
Header positions stay unchanged on sidebar collapse.
The sidebar changes width with the existing 0.18-second
ease-in-out animation.

Speech and refinement providers use compact pickers in their section headings.
Both speech pickers default to All and only filter their tables; selecting a row
changes the active provider and model. `ModelTable` fixes its column header above
a scrollable body capped at `Theme.modelTableMaxHeight` (300 pt). Short results
shrink to their measured height. Rows retain equal 16-point insets, with 13-point
model names and 11-point secondary text. Local rows show language coverage;
cloud rows identify the hosting provider, even when several hosts offer the same
model. Brand icons use the model's mark or its creator's logo, bundled locally;
see [brand asset sources](model-brand-assets.md).
A refresh action sits immediately beside the picker whose data it reloads.
Supporting copy appears only for a choice, consequence, or actionable problem
that the controls do not already explain. Do not repeat the provider name or
announce that the model list is visible.

The selected microphone lives in a padded capsule at the bottom of the sidebar,
above a footer with a left-aligned license button and right-aligned word count.
The capsule opens an anchored device list with a checkmark for the selection and
a ten-cell live level meter at the right of every row. Silence leaves all cells
empty; increasing input fills one through ten cells. Each device has its own
preview, and System Default shares the matching device's level. Unselected
Continuity microphones stay disconnected with idle meters until selected;
System Default counts as selected when it resolves to that device. Switching
away stops the Continuity preview. The panel is
compact: 336 points wide, an 8-point inset, a 28-point title row and 32-point
rows on the same scale as the sidebar destinations, with a 15-point corner
concentric to their 7-point selection. It aligns with the capsule's leading edge
and sits 8 points above it. Six rows show before the list scrolls, and long
device names truncate in the middle (most fit within about 175 points). Keep the
title and close button, but omit decorative descriptions, repeated section headings
and a separate meter card. Permission actions and device errors appear only
when needed, directly beneath the list and aligned with the device names.
Previews stop when the overlay closes or dictation starts. The license
button uses `key.horizontal` and opens the native License sheet described under
Onboarding and licensing. It shows the self-built edition or actual official
trial/license state; it does not display sample account data. The window chrome is a solid opaque color; nothing behind the window shows through.

Profiles uses a fixed 136-point list, a divider and a flexible editor. The list
and editor scroll independently. Profile rows are 36 points high and reuse the
navigation selection style. Keep the editor aligned with the selected row and
its single action menu reachable at the minimum window size; do not introduce
mobile breakpoints into this macOS layout.

Home remains the most expressive page, and its hero always leads it. Average speed,
words, apps used and time saved sit in one row of four equal-width,
leading-aligned columns, with 23-point headline numbers. Beneath them the hero draws the app icon's pressed-in
capsule from the user's own history: one raised bar per recent dictation, ending
in a raised gray caret. The bars are neumorphic pills, lit from the top left
and shadowed to the bottom right; height follows words, capped at 32 pt so the
metrics lead. Everything is grayscale: the caret is a raised pill a step darker in light
mode and brighter in dark mode than the bars, the hovered bar deepens toward
it, and a new dictation lifts the caret's shadow instead of a coloured glow. The well is pressed in
with inner shade and light. The well is 60 pt tall with 24 pt minimum horizontal inner
insets, bringing the waveform closer to all four edges without enlarging the
bars. Light-mode bar faces use a darker silver gradient against the pale well.
The hero surface is grayscale with a deliberately faint 0.02 gray ramp and a
20% top-left sheen, and its edge highlight is faint (30% of the rim colour). The card is raised from the island: with
light from the top left, `SurfaceShadows` casts a 12-point highlight 6–7 points
up-left (the palette's light color) and a 12-point shade 7–9 points down-right
(its shade at 70% opacity in dark mode, 85% in light mode). With no history it shows the icon's
five decorative strokes and the shortcut. Bars magnify under the pointer and the caption
names the hovered dictation. Entrance waits for initial history so animated
placeholder bars are never replaced mid-flight. Real bars enter once with a
0.45-second scale animation and at most 0.12 seconds of stagger; their layout
height stays fixed. Hover magnification also uses scale.

Each real bar is a native button keyed by its saved record ID, with keyboard and
accessibility activation. Activating it opens that dictation's delivered text
below a `RowDivider` inside the hero; activating it again hides the text. Another
bar switches records and resets text expansion. The selected bar keeps a neutral
highlight and a small dot while retaining hover magnification. The inline text
uses History's selectable six-line preview with Show More and Copy for the complete
saved `finalText`. Close or Escape hides the transcript and returns focus to the
selected bar. Changing the period or removing the selected record from the
overview clears selection. Opening and closing use a smooth 0.25-second transition.
Motion stops after each interaction; Reduce Motion removes it.

Below the hero, one readiness card
shows the active pipeline and expands to the setup checks, opening on its own when
a check fails; it never moves above the hero. Summary ranks apps by words with
their real icons and lists streak, dictations, active days and the longest
dictation, all computed locally by `HistoryStore.overview`. Keep the brand
colours inside Home; other pages stay neutral.

**The Card Owns Its Insets Rule.** Settings sections use `PageSection` and
`SettingsCard`. `cardPadding` applies equally on all four sides. Rows inside a
settings card add no vertical padding. Use `sectionTitleSpacing` above content,
`sectionSpacing` between sections and `controlSpacing` between card children.
`SectionTitle` uses `sectionTitleMinHeight` for a 32-point minimum row height,
with its title and trailing controls vertically centered. The 12-point content
gap and 28-point section gap keep each heading closer to its own content.
Only the title text receives the 4-point `sectionTitleLeadingInset` for optical
alignment; the row and trailing controls retain their shared edges.

## Elevation & Depth

Home's top-left lighting extends across the window. Every page card is raised
with the hero's highlight and shade at full strength and half its spread; buttons,
text fields and editors, menu pickers, segmented controls, switches, sliders and
stepper buttons are raised at a quarter of the spread (`SoftRaisedSurface` in
`SoftControls.swift`). Pressed buttons sink into an inset well; segmented controls,
switches and sliders sit in inset tracks; a switch's on state fills its track with
the system accent; editing fields show an accent ring. The single primary action
keeps the native prominent button. The same lighting covers selected sidebar
destinations, the sidebar microphone capsule, each device's ten-cell input meter,
shortcut keycaps, appearance preview frames, Home's app-usage tracks and the
recording HUD.
`NeumorphicSurface` supplies the neutral raised and recessed material, scaled
by depth to the component size; Increase Contrast adds an explicit edge.
Light comes from the top left in both appearances. Raised faces have an upper-left
highlight and cast their shadow down-right. Recesses shade the inner upper-left
edge and catch light on the inner lower-right edge. The Home rim follows the
same diagonal. `SurfaceShadows` draws outer shadows in a Canvas so live windows,
Xcode previews and bitmap captures share one direction. Direct offset shadow
modifiers invert vertically in AppKit bitmap capture on the current macOS;
never compensate by reversing the live shadow or by changing only light mode.
Selected sidebar destinations are an opaque recessed well: 2.5-point depth,
inner top-left shading and inner bottom-right highlight, 34 points high. The
microphone button inverts it, so the control never reads as a selected page: a
raised 38-point button in the sidebar's tone with a recessed socket for its plain
symbol and a trailing chevron; it sinks into a well while pressed and dims while
unavailable. Both share 12-point continuous corners (`NavigationStyle.wellShape`),
the same width and a 44-point label start. Increase
Contrast retains an explicit edge. Text and symbols stay opaque.
Inside the well, the selected icon rests on a flat raised island, like a switch
knob on its track: a rounded square concentric with the well (9-point corners) that
touches its top, bottom and leading edges 3 points in, with its light and shade
clipped inside the well. The symbol is carved deep into the island, with a shade
rim up-left and a highlight rim down-right. The well moves first and the island
follows 300 ms later on the same curve, sliding into the new well. Segmented
thumbs and switch knobs likewise keep their light and shade inside their tracks.
A single well serves both destination groups and slides to the newly selected row
on a 0.36-second ease-in-out curve that eases away, glides and settles, whether the page changed from the
sidebar, a Home action or the menu bar; Reduce Motion moves it without animation.
Other list selection remains native.
Preview frames stay recessed and retain an accent selection outline. Usage
fills are raised solid gray pills inside their inset tracks (0.66 light, 0.32
dark), lit from the top left, and remain proportional, with no fill for zero. The recording HUD fits its current timer or status and
keeps bright live bars, a dark inset waveform track and shallow rim. Errors and
recovery notices expand over 0.28 seconds into a rounded diagnostic panel with
13-point wrapping text and a 28-point Copy Message icon at the far right. Full
diagnostics remain visible through the pipeline's idle reset until the next
operation; text scrolls only beyond the screen-bound height. Copy preserves all
text without activating the panel. Recording remains click-through, and Reduce
Motion disables spatial expansion. Informational confirmations such as Copied to
clipboard show for three seconds and then fade over 0.5 seconds. Delivery metadata
distinguishes these confirmations from persistent recovery messages.

Sidebar material, subtle fills and dividers continue to separate ordinary
content. Profiles has no shadowed editor container. Native menus, action
buttons, text lists and sheets retain their existing presentation.

## Shapes

The Auto theme thumbnail clips its dark half to its actual layout bounds so the
diagonal split reaches the bottom and trailing edges without exposing the light base.

Use the navigation, editor and card radii for their respective components.
The content island uses `Theme.islandRadius` for 12-point continuous corners.
With the window's 16-point corner and the 10-point gutter, a concentric corner
would be 6 points; 12 keeps the island's corners visibly soft.
Shared cards use `Theme.cardRadius` for 18-point continuous corners and a half-point border. Editable text
areas have a half-point resting border that becomes a 1.5-point accent border
when focused. Keep these text-area boundaries even though the surrounding
Profiles editor is unboxed.

## Components

### Navigation

Each destination is a `Button` with a complete row hit area, a monochrome symbol
and a text label. Selection adds the accessibility selected trait. The active
dictation profile has a separate checkmark; selecting a profile for editing does
not activate it.

### History timeline

History keeps its title and search above two independently scrolling columns.
A 52-point guide on the left groups compact timestamps and horizontal ticks by
day. Its dates and times align with the History heading's leading edge. Each 24-point row is a button that jumps to its transcription; the active
row uses a longer, stronger tick and emphasized time. The guide follows the
current card without adding a second selection state. When the cards return to
the top, the guide restores its first day heading as well as its first timestamp. Day labels, search
results and deletion use the same record list in both columns. Full dates and
times remain available in tooltips and accessibility labels.

The cards retain the remaining width after the shared 12-point gap, their
16-point insets, lazy loading and native copy, details, version and delete
controls. Empty results omit the guide. Jumps respect Reduce Motion.

### Profile editor

The Profiles sidebar item uses `square.and.pencil`. The editor is one scrolling
column in the shared 784-point window. A 200-point `SoftPicker` in the Profile
section heading chooses the profile to edit, using names without icons.

The Profile card contains Name, Dictation and Refine transcript rows, separated
by `RowDivider`. Name commits on Return or focus loss; an empty edit restores the
saved name. Dictation shows In Use for the active profile or Use Profile for an
inactive selection. Choosing a profile to edit does not activate it.

Speech model follows the Profile card and stays visible with refinement off.
Its 240-point `SoftPicker` offers Use App Default, local models, cloud models
and saved selections outside the catalogue. Use App Default follows the choice
in Models; an explicit selection binds that speech recognition model to the
profile. The next row names the resolved model and shows an unavailable-model
reason, a required download, local processing or the cloud audio destination,
with a Models button for setup. Language and script settings remain shared.
When the active profile has a binding, Models explains that selections there
change the app default and provides a Profiles button. Keep Apple Speech locale
available for a bound Apple model; protect the default and active bound model
from deletion. Downloads preserve the default while a profile override is active.

Instructions follows Speech model when refinement is on. Its optional Task uses
`DisclosureGroup` and opens when a stored task is present. Turning refinement
off hides both fields and adds the short vocabulary and script-conversion note
under Refine transcript. The shared Base system prompt section comes last. It
shows Default prompt or Custom prompt, and Edit warns about effects on all
AI-refined profiles before opening the draft editor.

Use `PageSection`, `SettingsCard` and the existing neumorphic controls throughout.
Cards own their equal 16-point insets and 18-point continuous corners; do not add
another container around the whole editor. Keep New Profile and one action menu
together at the right of the page title. The menu contains rename, duplicate,
prompt preview, built-in reset or custom-profile deletion, and Reset All Profiles.
Preserve native disabled and destructive states and the existing confirmations.

### Shared controls

`Theme.swift` holds one component per concept: `StatusDot` (ready, attention,
in progress, off), `RefreshButton`, `EmptyNote`, `OverlayPanel` for the
microphone panel, and `.settingsDisclosure()`, which styles only a
disclosure header. Settings row titles use the field-label role (13 pt medium),
below the 14 pt section headings. Descriptions share `.supportingText()`: 11 pt
regular in the native secondary color, with one short phrase where possible.
Privacy and recovery instructions remain explicit; longer model explanations
stay inside their details disclosure. Inline notices keep text and actions in
one horizontal row, and every Home readiness row has a `RowDivider`. Separators
inside cards are engraved: a 1-point shade line (black 13% light, 42% dark) over
a 1-point highlight (white 85% light, 9% dark), lit from the top left like the
cards; Increase Contrast deepens the shade line.
Every provider key is an `APIKeyField` row
followed by a Connection row with Test and Cancel.

### Onboarding and licensing

Onboarding reuses the 784-point window, a fixed 180-point step rail and shared
settings cards for Permissions, Speech and Try It. Header and footer actions
stay outside its scrolling content. Set Up Later preserves progress; successful
practice requires real pipeline delivery. Returning users' refinement and output
settings are restored after practice.

The License sheet is plain text on the sheet, with no cards, status dots, badges,
helper lines or footnotes. Its top row holds the sidebar brand mark at 32 points
(a Sandbox build adds a `PillTag`) and Done. Below it are one 17-point headline
(Licensed, 13 days left in your trial, Your trial has ended) and one 13-point
sentence in secondary color, then only the buttons that apply. Each state has at
most one prominent action (Start Trial, Buy Airdraft, Allow Access, Manage Devices
during recovery, or Update Key for a revoked activation); every other control uses
`SoftButtonStyle`. A licensed Mac names itself in the sentence (`Airdraft ·
XXXXXXXX`, the label Polar shows) and offers Check License, Manage Devices and
Update Key…, with Deactivate This Mac… as quiet secondary text. Without an
activation, a plain key field with Activate This Mac sits beneath the purchase
buttons, with a Find My License link. An unfinished activation becomes the headline
and sentence, with its portal actions before trial, purchase and key entry; key
entry is disabled until it is resolved. A failure appears as one line of
supporting text unless the state's own sentence already says the same. The sheet
is 440 points wide and as tall as its content (about 140 points for a self-built
edition to about 320 for an unfinished activation), scrolling only past 520
points. Native controls and semantic colors remain unchanged. The vault topic
linked above records states, inspected renders and the separate live-purchase and
release gates.

### Text fields and sheets

Pointer clicks clear stale control focus before the new target handles the click.
Clicks inside the active text editor preserve its selection and composition.
Overlay dismissal restores trigger focus for keyboard and VoiceOver interaction;
pointer dismissal clears it. A subsequent pointer action cancels pending focus
restoration. Native keyboard focus cues remain visible.

`ProfileTextEditor` owns the label, empty-state guidance, border and focused
state. Profile changes save through their bindings. The base system prompt uses
a draft in a separate sheet with Save, Cancel and Restore defaults. Cancel
discards the draft, including a pending restore; Save rejects whitespace-only
text. The prompt preview is scrollable, selectable text with a Done action. Keep the existing default and
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
- Don't add profile icons, colored badges or a saturated selection fill to this sidebar.
- Keep Home's full hero treatment on Home, in grayscale; no brand hues. Other cards and
  controls use the smaller raised spread, never the hero's; do not add continuous
  decorative motion.
- Don't tint the hero's surface or return its metrics to the corners.
- Don't wrap the Profiles editor in another card or move its primary instructions
  behind a disclosure control.
- Don't generalize the open Profiles composition into a ban on settings cards,
  native control borders or the existing app icon's neumorphic artwork.
- Don't treat review PNGs as shipped image assets. This redesign adds no raster
  assets, and browser-specific visual detectors do not validate SwiftUI output.
