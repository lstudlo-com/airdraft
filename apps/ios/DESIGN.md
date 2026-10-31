# Airdraft for iPhone: design

The Mac app's neutral neumorphism, on a phone. Neumorphism belongs to the
content; navigation belongs to the system.

## Layers

- **System layer:** `TabView` (Home, History, Transcribe, Settings), navigation
  bars, sheets, menus, search fields, `List` rows in History and Vocabulary,
  switches and pickers. They keep iOS's Liquid Glass and behavior; do not
  restyle them.
- **Content layer:** pages scroll over `MobileTheme.background`, the Mac
  island's mid-tone (0.90 light, 0.15 dark), and hold raised cards, wells and
  soft buttons. Light comes from the top left in both appearances.

## Shared with the Mac

`SurfaceShadows.swift`, `NeumorphicSurface.swift` and `NavigationStyle.swift`
are the Mac files themselves, compiled into the iOS targets. A change to them
changes both apps: build both and look at both.

`Airdraft/Design/MobileTheme.swift` translates the Mac values that cannot be
shared (they live in files that use AppKit). Change them together:

| iOS | Mac source | Values |
| --- | --- | --- |
| `MobileTheme.background` | `Theme.islandBackground` | white 0.90 / 0.15 |
| `MobileRaisedSurface` | `SoftRaisedSurface` | faces 0.90/0.18 (card), 0.91/0.20 (control); shade black 0.27/0.525; light white 1/0.09; spread ×0.5 card, ×0.25 control |
| `SoftCard`, `SoftSection` | `SettingsCard`, `PageSection` | 16-point insets, 18-point corners, sentence-case headings |
| `RowDivider` | `RowDivider` | engraved groove: shade line over highlight line |

## Phone rules

- Touch targets are at least 44 points; compact buttons keep 44 points of hit
  area around a 36-point face.
- Text uses Dynamic Type text styles, never fixed sizes; copy wraps at large
  sizes. The Mac's own Text size setting does not exist here.
- The one accent, the system blue, marks the primary action, selection and
  recording. Warnings may use the system orange symbol.
- `RecordKey` is the only large control: a raised key with the microphone in a
  recessed socket, sunk into its well while recording.
- Model rows put their action (Download, Use, Cancel) at the trailing edge;
  the selected model shows a checkmark.
- No private API: the Mac's progressive header blur is not used; the system
  scroll edge effect handles bars.

## Keyboard

The keyboard reuses `SurfaceShadows` for raised keys that sink while pressed.
One wide microphone key over space, delete and return; the globe key appears
when iOS asks for it. Status text sits above the keys in footnote size.

## App icon

`scripts/render-app-icon.swift` renders the iOS icon full bleed and opaque:
Carved Wave for light, Night Wave for dark, the same wave geometry as the Mac
icon. Never hand-edit the PNGs.
