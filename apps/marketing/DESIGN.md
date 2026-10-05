---
name: Airdraft website
description: The app window's neutral neumorphism, built out into a page.
colors:
  chrome: "#f2f2f2"
  island: "#e6e6e6"
  face-top: "#e8e8e8"
  face-bottom: "#e3e3e3"
  control-top: "#ededed"
  control-bottom: "#e3e3e3"
  control-hover-top: "#f2f2f2"
  pressed: "#dedede"
  well: "#d9d9d9"
  well-soft: "#e3e3e3"
  bar-top: "#c9c9c9"
  bar-bottom: "#8a8a8a"
  caret-top: "#858585"
  caret-bottom: "#4d4d4d"
  cap-top: "#f7f7f7"
  cap-bottom: "#cccccc"
  key-top: "#2b2b2b"
  key-bottom: "#1a1a1a"
  ink: "#222222"
  muted: "#5c5c5c"
  quiet: "#666666"
  hud-top: "#2b2b2b"
  hud-bottom: "#1a1a1a"
  hud-well: "#141414"
  status-ok: "#34c759"
  status-attention: "#ff9500"
  status-busy: "#ffcc00"
  dark-chrome: "#363636"
  dark-island: "#262626"
  dark-face-top: "#303030"
  dark-face-bottom: "#2b2b2b"
  dark-control-top: "#373737"
  dark-control-bottom: "#2e2e2e"
  dark-well: "#242424"
  dark-bar-top: "#575757"
  dark-bar-bottom: "#383838"
  dark-caret-top: "#9e9e9e"
  dark-caret-bottom: "#6b6b6b"
  dark-key-top: "#ebebeb"
  dark-key-bottom: "#cccccc"
  dark-ink: "#dedede"
  dark-muted: "#a3a3a3"
typography:
  display:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter Variable", sans-serif'
    fontSize: "clamp(2.5rem, 1.45rem + 4.2vw, 4.25rem)"
    fontWeight: 600
    lineHeight: 1.05
    letterSpacing: "-0.025em"
  headline:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter Variable", sans-serif'
    fontSize: "clamp(1.875rem, 1.4rem + 1.6vw, 2.5rem)"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  entry-title:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter Variable", sans-serif'
    fontSize: "1.625rem"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.015em"
  title:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter Variable", sans-serif'
    fontSize: "1.25rem"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "-0.01em"
  lead:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter Variable", sans-serif'
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.6
  body:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter Variable", sans-serif'
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter Variable", sans-serif'
    fontSize: "0.8125rem"
    fontWeight: 600
    lineHeight: 1.4
  action:
    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter Variable", sans-serif'
    fontSize: "0.9375rem"
    fontWeight: 500
    lineHeight: 1.2
  rounded:
    fontFamily: 'ui-rounded, "SF Pro Rounded", -apple-system, sans-serif'
    fontSize: "0.8125rem"
    fontWeight: 500
    lineHeight: 1
rounded:
  island: "22px"
  card: "18px"
  well: "12px"
  field: "10px"
  cap: "7px"
  pill: "999px"
spacing:
  island-inset: "12px"
  island-inset-mobile: "6px"
  gutter: "48px"
  gutter-tablet: "32px"
  gutter-mobile: "20px"
  section: "144px"
  section-tablet: "120px"
  section-mobile: "96px"
  card: "28px"
  card-mobile: "22px"
components:
  key-primary:
    backgroundColor: "{colors.key-bottom}"
    textColor: "#ffffff"
    typography: "{typography.action}"
    rounded: "{rounded.pill}"
    padding: "0 24px"
    height: "48px"
  key:
    backgroundColor: "{colors.control-top}"
    textColor: "{colors.ink}"
    typography: "{typography.action}"
    rounded: "{rounded.pill}"
    padding: "0 20px"
    height: "44px"
  panel:
    backgroundColor: "{colors.face-top}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "{spacing.card}"
  well:
    backgroundColor: "{colors.well-soft}"
    textColor: "{colors.ink}"
    rounded: "{rounded.well}"
  segmented:
    backgroundColor: "{colors.well}"
    textColor: "{colors.muted}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "3px"
    height: "38px"
  chip:
    backgroundColor: "{colors.well-soft}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "6px 12px"
  hud:
    backgroundColor: "{colors.hud-bottom}"
    textColor: "#ffffff"
    typography: "{typography.rounded}"
    rounded: "20px"
    padding: "6px 14px 6px 6px"
---

# Design System: Airdraft website

## Overview

**Creative North Star: "The app window, not the icon"**

The website uses the native app's own material, translated value for value from
`Sources/App/Views` (`Theme`, `SoftControls`, `NeumorphicSurface`,
`SurfaceShadows`, `HomeHero`, `IndicatorPanel`). A visitor who opens Airdraft
after the site should recognise every surface: the light gray chrome around a
rounded mid-tone island, raised cards and capsule keys, pressed wells, Home's
waveform, the graphite recording pill.

It is neumorphism of a specific kind: hardware-like and crisp. Light comes from
the top left in both appearances. Raised surfaces carry a full-strength white
highlight up-left and a clearly darker shade down-right, with a **small spread**;
recessed surfaces reverse them inside the edge. Contrast stays at full strength
at every elevation; only the spread shrinks. It is never the hazy,
low-contrast, wide-shadow variant.

There is **no hue**. Every colour is a neutral gray, as in the app. The only
exceptions are the three status dots (green, orange, yellow), which mean the
same thing they mean in the app. `scripts/check-neutral.mjs` enforces this in
`pnpm check`.

Tokens live in `src/styles/global.css`; the sidecar `.impeccable/design.json`
carries shadows, motion, breakpoints and component previews.

**Key Characteristics:**

- One light source, top left, on every raised and recessed surface, in light and dark.
- The page is the app window: `--chrome` around a rounded `--island`; everything sits on the island.
- Raised: a 1px top-left rim, a shade cast down-right and a white highlight cast up-left.
- Recessed: inner shade at the top left, inner light at the bottom right.
- One graphite key for the primary action; everything else is a gray capsule.
- Engraved grooves (a shade line over a highlight line), never flat hairlines, to divide rows.
- Light and dark follow the system appearance, like the app's Auto theme.

## Colors

All values are the app's `Color(white:)` levels.

### Surfaces

| Token                                | Light            | Dark             | App source                                    |
| ------------------------------------ | ---------------- | ---------------- | --------------------------------------------- |
| `--chrome`                           | `#f2f2f2` (0.95) | `#363636` (0.21) | `Theme.chromeBackground`                      |
| `--island`                           | `#e6e6e6` (0.90) | `#262626` (0.15) | `Theme.islandBackground`                      |
| `--face-top` / `--face-bottom`       | 0.91 / 0.89      | 0.19 / 0.17      | `SoftRaisedSurface` cards, `HomeHero` surface |
| `--control-top` / `--control-bottom` | 0.93 / 0.89      | 0.215 / 0.18     | `SoftRaisedSurface` controls                  |
| `--pressed`                          | 0.87             | 0.15             | pressed controls                              |
| `--well`                             | 0.85             | 0.14             | Home's waveform well, `SoftInsetTrack`        |
| `--well-soft`                        | 0.89             | 0.14             | shallow `NeumorphicSurface` wells, chips      |
| `--bar-*`                            | 0.79 → 0.54      | 0.34 → 0.22      | Home's raised waveform bars                   |
| `--caret-*`                          | 0.52 → 0.30      | 0.62 → 0.42      | Home's caret                                  |
| `--cap-*`                            | 0.97 → 0.80      | 0.34 → 0.22      | `KeyCap`                                      |

Gradients run from the top-left corner to the bottom right (`135deg`).

### Text

- **Ink** (`#222222` / `#dedede`): headings and primary text.
- **Muted** (`#5c5c5c` / `#a3a3a3`): supporting text; 5.3:1 or better on the island in both appearances.
- **Quiet** (`#666666` / `#9a9a9a`): only the hero's facts line, 4.6:1 or better.

The app's secondary label colour is lighter; the site darkens it to meet WCAG AA.

### Primary key

Graphite, like the recording pill: `#2b2b2b → #1a1a1a` with white text in light
mode. On the dark island a graphite key would read as a hole, so dark mode
inverts it to the high-contrast light key (`#ebebeb → #cccccc`, dark text).
Either way it is the one achromatic key with the most contrast on the screen.

### Light and shade

| Token                               | Light                 | Dark                 |
| ----------------------------------- | --------------------- | -------------------- |
| `--light`                           | white                 | white 9%             |
| `--shade`                           | black 27%             | black 52.5%          |
| `--shade-deep` (wells, bars)        | black 32%             | black 75%            |
| `--rim` (top-left edge)             | white 27%             | white 4.8%           |
| `--groove-shade` / `--groove-light` | black 13% / white 85% | black 42% / white 9% |

Selection is a neutral gray; focus is a 2px ink outline. Never a hue.

## Typography

SF Pro, through the system stack (`-apple-system, BlinkMacSystemFont`), so Mac
visitors read the app's own face, with SF's optical sizes. Inter Variable is
self-hosted as the fallback for other systems and is only downloaded where the
system face is missing. Keycaps, the HUD timer and numbers in the app's rounded
style use `ui-rounded` where available.

| Step        | Size                                      | Use                                                         |
| ----------- | ----------------------------------------- | ----------------------------------------------------------- |
| display     | `clamp(2.5rem, 1.45rem + 4.2vw, 4.25rem)` | Hero only                                                   |
| headline    | `clamp(1.875rem, 1.4rem + 1.6vw, 2.5rem)` | Homepage sections; every subpage title (`.page-title`); 404 |
| entry-title | `1.625rem`                                | Subpage sections, changelog entries                         |
| title       | `1.25rem`                                 | Tile, plan and card titles                                  |
| lead        | `1.0625rem`                               | Intros, sample text, disclosure summaries                   |
| body        | `0.9375rem`                               | Paragraphs, actions                                         |
| label       | `0.8125rem`                               | Field labels, chips, metadata. The floor: nothing smaller   |

Headings are semibold (600) with light negative tracking; actions are medium
(500), the primary key semibold. Headings balance; paragraphs use
`text-wrap: pretty`. Headings are plain statements without trailing full stops,
except the hero line.

## Layout

The page is the app window. The header and footer sit on `--chrome`; every
page's `<main>` is `.island`, inset `12px` from the window edges (`6px` on
phones), with `22px` corners, a 1px hairline edge and no shadow. The island
clips its content (`overflow: clip`, which keeps `position: sticky` working).

Scrolling fills the window with the island. Over the first `160px` of scroll
its inset, corners and hairline shrink to nothing and it grows up behind the
header, so it runs edge to edge; over the last `120px` before its bottom edge
enters the window they return, so the footer sits on the chrome below an inset
island again. The first scroll goes into the expansion: the island holds
`160px` of space above the content and starts translated up by that much.
Over the first `320px` the content's speed rises from still to the scroll's
own speed along smoothstep (3p² − 2p³), so it moves `30px` while the island
opens and `160px` in all, and its speed never jumps. The header blur appears
once the island is full, before content reaches the header.

The opening and the hold are a CSS scroll timeline (`.island-scroll`), never a
scroll listener: a script runs a frame behind the compositor's scroll, so
content it repositions jitters. The translate's and clip's curves are sampled
into `linear()` easings. The translate is composited with the scroll and is
zero past the first `320px`, so `position: sticky` and ScrollTrigger (which
measures that settled layout) are unaffected.
`src/scripts/island.ts` sets `.island-scroll` only where scroll timelines exist
and motion is allowed; elsewhere it opens the island itself without a hold and
shows the blur as soon as the page scrolls. The closing only changes the clip,
so the script drives it. The island's box always spans the window with
matching padding and the inset is a `clip-path`, so content never reflows.
Without JavaScript it stays inset.

Content width inside the island is `min(1120px, 100% - 2 × gutter)`, the same
as the header, so content lines up with the mark. Sections come from the
`Section` component and the spacing tokens; `first` sections take `56px` of top
padding instead of the section gap (subpages excepted, below). The sample is capped at `1040px`.

Subpages (Pricing, Support, Changelog) are `main.island.subpage` and open with
the same title block: `Section level={1} first`, the headline step for the title
(`.page-title`), and the full content width. An intro is optional; Changelog
opens with its title alone. No subpage narrows its content. The title sits
`0.75` of a section gap (`108px`, `90px`, `72px`) below the island's top edge,
a little further than the later
sections sit from each other (`0.72` of the gap: `104px` on desktop), which use `entry-title`
headings, a step below the page title.

The homepage bento is a three-column grid with `24px` gaps and seven tiles in
a fixed rhythm: wide + narrow, three narrow, narrow + wide. The provider board
never pins: it is about one viewport tall on desktop and stacks below `1000px`.

| Max width | Changes                                                                                                                                                                                                                           |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `1000px`  | Gutter `32px`, section `120px`; bento becomes two columns (wide tiles span both); pricing plans and homepage offers stack (max `560px`); the provider board stacks its three columns; the hero waveform drops its 12 oldest bars. |
| `700px`   | Gutter `20px`, section `96px`, island inset `6px`; sample, bento, footer and changelog stack; the hero waveform shows 15 bars; the HUD shows ten bars.                                                                            |
| `560px`   | The header shows the mark, Get Airdraft and the menu key; the links and GitHub move into the blur the menu pulls down.                                                                                                            |
| `420px`   | Hero and offer keys go full width; the hero waveform shows 12 bars.                                                                                                                                                               |

## Elevation & Depth

Exact values live in `:root`. They translate `SurfaceShadows` (SwiftUI radius
r ≈ CSS blur 2r).

- `--raise-hero`: `7px 9px 24px` shade, `-6px -7px 24px` light. The hero card, the featured offer and the ready-to-run pricing plan.
- `--raise-card`: half the spread. Panels, bento tiles, the Open source pricing plan, the provider board.
- `--raise-control`: a quarter. Keys, fields, the inserted-text card, art cards.
- `--raise-small`: keycaps, disclosure buttons, segmented thumbs, changelog studs.
- `--edge`: the 1px top-left rim plus a 0.5px hairline, on every raised face.
- `--sink-hero`: Home's waveform well. `--sink-track`: segmented tracks. `--sink-soft`: art wells and the waiting result. `--sink-chip`: chips, sockets, the current nav link, disabled keys. The provider rows' selection well uses the sidebar's own 2.5px inset.
- `--press`: a key while pressed; it sinks into a well (`--pressed` face).
- `--groove`: RowDivider, between disclosure, price-table, fund-list and provider rows, and the bento privacy flow.

Objects inside a track or well (segmented thumbs, stage fills) keep their light
and shade clipped inside it. Elevation is declared once per element: a shadow,
never a border plus a shadow. Increase Contrast (`prefers-contrast: more`) adds
explicit edges, as in the app.

## Shapes

Island `22px`, cards `18px` (`Theme.cardRadius`), wells `12px`, fields `10px`,
keycaps `7px` (large keycaps `12–18px`). Keys, chips, segmented pickers, the
waveform well and the nav selection are capsules. The HUD is a `20px` rounded
rectangle, as in the app.

## Components

Reusable components live in `src/components/ui/`. Build new pages from them;
`/design/` (unlinked, `noindex`, excluded from the sitemap) shows each one in
every state and the palette in the current appearance.

### Hero card (`HeroCard.astro`, `ui/Waveform.astro`)

Home's hero card from the app, without its metrics (the site never shows usage
counts): a raised card with a faint top-left sheen holding the waveform well,
then the app's own first-run caption, "Hold ⌃⌥ and speak. Each dictation adds a
bar." The forty bars are decorative; their heights are a fixed pattern shaped
like the app's `0.26 + 0.74 × √share` mapping, not data.

The card sits `84px` below the hero facts line, reduced to `60px` at widths
of `700px` or less.

`Waveform` is the well: `104px` tall (`84px` on phones), raised gray bars up to
`48px`, and a `60px` graphite caret. Bars grow from 12% on load. Like the app,
the bars near the pointer grow by up to 28% on a Gaussian two and a half bars
wide, never past the caret, and the bar under the pointer deepens toward the
caret's tone (`src/scripts/waveform.ts`). They also rise with the shared voice.
Narrow screens hide the oldest (leftmost) bars so the newest stay beside the
caret. With reduced motion the bars are static; only the hover tone changes.

The caption works (`src/scripts/dictate.ts`). Holding ⌃⌥ while the card is on
screen, or pressing and holding the well or the caption's keycaps, plays a
pretend dictation: the caption gives way to the recording pill (timer and
meter), a live bar enters at the caret and follows a synthetic speech envelope,
and the oldest bar folds away. On release the pill shows Refining, then the bar
settles at the height the app would give that length (`0.26 + 0.74 × √share`,
six seconds being a full bar) and the caret lifts once (HomeHero's flare).
Nothing is recorded. Holds under 0.3 s, a third key (so VoiceOver's ⌃⌥ commands
never add a bar), a touch that turns into a scroll, or the card leaving the
screen cancel it; eight seconds stop it. With reduced motion the live bar holds
one level and nothing animates.

### Voice (`src/scripts/voice.ts`)

Every `[data-waveform]` listens to one shared "voice": pointer speed and scroll
speed raise it, it decays when still. Each `[data-bar]` gets `--gain` (0–1),
and the hero's bars stretch up to 40%. The loop runs only while the voice is
audible and a waveform is on screen, and not at all with reduced motion.

### Brand (`ui/Brand.astro`)

The mark is the app sidebar's `SidebarBrandMark` (`MainWindow.swift`),
translated value for value, with no lettering, as in the app. The capsule's face
is the chrome, painted opaque in `--chrome` so page content scrolling under the
sticky header never shows through it, and lifted only by a soft shade down-right and light
up-left (light: black 20% and white 95%; dark: black 55% and white 9%; radius
2.6 at 28px). Outer box-shadows never paint inside the box, which matches the
app's `excludesInterior`. Never give it an edge stroke, a translucent face or
any fill other than `--chrome`. Five waveform
strokes (levels `0.36, 0.66, 1, 0.72, 0.48`) and a separate caret are carved in
as opaque grooves: white 0.80 (dark 0.12), shaded inside the top-left edge and
lit inside the bottom right. Geometry uses the icon's 364-point capsule height:
bars `38` wide, `190 × level` tall, `30` apart; the caret `208` tall with `20`
more before it. Shadows scale with height. It is `34px` tall in the header and
`28px` (the sidebar's own size) in the footer, a static mark inside the home
link, whose accessible name is "Airdraft". Increase Contrast adds edges. The
outlined `SidebarWordmark` SVG remains the installer's wordmark only.

### Button (`ui/Button.astro`)

The site's keys (`SoftButtonStyle`). Renders `<a>` with `href`, otherwise `<button>`.

| Prop                 | Values                                    | Notes                                                                                  |
| -------------------- | ----------------------------------------- | -------------------------------------------------------------------------------------- |
| `variant`            | `primary`, `secondary` (default), `quiet` | One `primary` in view at a time. `quiet` is an inline text action.                     |
| `size`               | `md` (44px), `lg` (48px)                  | `lg` for hero and closing actions.                                                     |
| `icon`               | `none`, `right`, `down`, `external`       | Trailing arrow.                                                                        |
| `iconOnly` + `label` |                                           | 44px circle; `label` is the accessible name and tooltip. Put the SVG in `slot="icon"`. |
| `disabled`           |                                           | Renders a pressed-in, non-interactive `<span aria-disabled>`.                          |

Keys are raised capsules. Hover lightens the top of the face; pressing sinks the
key into a well. Focus shows the 2px ink ring.

### Segmented picker (`.segmented`, `src/scripts/segmented.ts`)

`SoftSegmentedPicker`: raised segments on a recessed capsule track. One raised
thumb slides to the selected item (`.is-selected` or `aria-pressed="true"`) on
`SelectionMotion.curve` (`cubic-bezier(0.65, 0, 0.35, 1)`, 360ms), whatever
changed the selection; its light and shade stay clipped inside the track.
Without JavaScript the selected item draws its own face. The selected label is
ink and semibold; the others are muted. Used for the sample's profiles and the
bento's profile and history graphics.

### Section, Surface, Chips, Keys, Tag, StatusDot

- `Section`: `title`, optional one-line `intro`, `level` 1 or 2, `first`. Owns the heading id and spacing; `level={1}` titles get `.page-title`.
- `Surface`: `variant="panel"` (raised card) or `"well"` (recessed), any element via `as`. Never nest a panel in a panel. Lists and tables go inside a raised panel, divided by grooves, as in the app's settings cards.
- `Chips`: recessed capsules. `.chip-muted` and `.chip-strong` (raised) show a before → after pair.
- `Keys`: raised keycaps in the rounded system face; `size="lg"` and `keys-xl` for feature tiles. Modifier keycaps carry `data-key` and sink while the visitor holds that key (`src/scripts/keys.ts`), on every page.
- `.tag`: a small recessed label.
- `.status-dot` with `data-tone` `ok` (default), `attention`, `busy` or `inactive`: the only colour on the site.

### Hud (`ui/Hud.astro`) and the dictation sample

`Hud` is the app's recording pill (`IndicatorPanel`): a graphite rounded
rectangle with a white top-left rim, holding a small dark inset well of white
bars, then a timer or state in the rounded face. It stays dark in both
appearances, as in the app. Pass `levels` for a still frame.

The sample (`DictationPreview.astro`) is a raised panel: a recessed "What you
said" well and a "What Airdraft inserts" card that waits pressed in and rises
once typed, above Run sample, the HUD and a status line that speaks only while
running. It plays once when mostly on screen: words light up, the HUD counts,
then shows Decoding and Refining, fillers are struck one at a time, and the text
is typed with an ink caret. Profile buttons re-run only the refinement; Stop
jumps to the result. Without JavaScript the Clean result shows; reduced motion
shows it immediately and never autoplays. Its accessible name is "Sample
dictation".

### Interface section (`InterfaceShowcase.astro`)

"An interface you’ll love to open" follows the sample and precedes the guides.
Its heading and one-line intro are centered over the window, `72px` above it
(`48px` on phones). It shows the real app: the Configuration page rendered from a Debug build by
`scripts/render-app-window.sh` (an isolated empty data directory, so no
history, usage count or personal setting; grayscale, as the app looks with the
Graphite accent) in `public/app/`. Re-render it when the Configuration page,
sidebar or materials change. The window is `784px` wide at most, `16px`
corners (`12px` on phones), raised with the hero's spread, with an inactive
window's gray close and minimize buttons 16 points in. Both appearances are
stacked; a groove divider with a raised round key compares them. Dragging the
window or the keyboard on its range input moves it; without JavaScript it rests
at half. On wide windows (from `1280px`) six callouts name the materials at
their places in the window (carved mark, pressed well, raised button, raised
card, engraved divider, sliding choice), joined by a leader ending in a
graphite stud ringed with the chrome. The window rises with the scroll and the
callouts draw out after it. Once, when the window is half in view, the divider
sweeps from the right edge to the middle over `1200ms` on the selection curve
(a smooth cubic, never linear); dragging follows the pointer directly and
reduced motion rests it at half.

Below it, three bento tiles are live specimens (`src/scripts/interface.ts`):
large keycaps that sink on the pointer or the visitor's ⌃⌥; the sidebar
selection at 1.18× the app's size (`40px` rows, `14px` well, `34px` icon
island with `11px` corners), whose well slides on the selection curve while
the island follows `300ms` later inside it; a soft switch whose on state fills
the track with the primary key's graphite, above a segmented picker. Each plays
a loop while on screen until the visitor touches it; reduced motion never
loops and moves them instantly.

### Bento (`ui/BentoTile.astro`)

Every tile has the same anatomy: a recessed well `232px` tall (`210px` on
phones) holding one large graphic, a title, and one line of text. Tiles are the
same raised panel; only the span differs (`wide` spans two columns). The
graphics are built from the app's own parts, never icons: a raised text field
and the recording pill, big keycaps that sink when pressed, a segmented profile
picker, a vocabulary correction, a history card deck, a refinement status chip
with its status dot (yellow while refining, orange when it fails), and a "This
Mac" boundary whose signal runs along grooves. Each plays a short loop while on
screen (`data-art`); without JavaScript they show their final frame.

### Provider board (`PipelineStory.astro`)

"You choose where each step runs" as one raised card in three columns, in the
order dictation runs: Speech, Refinement, Insertion. Engraved vertical grooves
(`RowDivider` on its side) divide the columns, and a small raised chevron sits
on each groove level with the headings. Below `1000px` the columns stack, the
grooves lie flat and the chevrons point down. The section never pins.

Speech and Refinement each carry a segmented choice of where they run (This
Mac | Cloud, and This Mac | Cloud | Subscription). The choice swaps that
column's one line on what leaves the Mac and its provider table, laid out like
the app's settings tables: rows divided by grooves, the first resting in the
sidebar's recessed selection well (12px corners, 2.5px depth) with a raised
check island inside it. Every choice is visible at once, so the columns read as
independent. Each choice's alternatives share one grid cell, so a column keeps
the height of its longest list and switching never moves the page. The choices
are native radio groups and CSS `:has()` swaps the columns, as on the license
card; `segmented.ts` adds the sliding thumb.

Insertion has no choice: "At your cursor" sits at the pickers' height, then a
raised field where the vocabulary fix strikes "cooper tino" and brings in
"Cupertino" (a `data-art` loop while on screen; its resting frame is the fixed
sentence). The board rises as it arrives and its columns follow left to right.

### Get Airdraft (`GetAirdraft.astro`) and the license card (`LicenseCard.astro`)

The homepage close: two offers side by side. Build it yourself (Free, build
instructions) and the ready-to-run app's license card, raised with the hero
spread and holding the page's one primary key ("See pricing").

The license card's title sits beside a segmented **1 Mac | 3 Macs** choice;
below it, only the chosen license's price ("one-time") and use show, and
switching slides the new line up into place. The choice is a native radio
group and CSS `:has()` picks the visible lines, so it works without
JavaScript; `segmented.ts` adds the sliding thumb. The Build it yourself title
row is the choice's height (`38px`), so the side-by-side prices line up. The
pricing page lists each license as its own plan instead.
Prices, Mac counts and inclusions come from `src/data/site.ts`.

### Motion

Motion follows height, as the material does. Raised objects sit closer to the
visitor, so they lead the scroll a little; the contents of recessed wells sit
further away, so they lag. Objects rise from the surface as they arrive (they
grow from `0.92–0.94` while their shadow grows from nothing) and sink back into
it as they leave (they shrink while their shadow flattens). Light stays at the
top left; nothing tilts or flies through perspective, and text fades and moves
but never zooms.

**Scroll timelines (`src/styles/motion.css`).** Where the browser supports
CSS scroll timelines and motion is allowed, every scroll-linked effect is a
`view()` or named view timeline, so it moves in the same frame as the scroll and
never jitters; never move content from a scroll listener. Transforms and
opacity run apart from shadows so the browser can composite them. An element
inside a scroll container (`overflow: hidden` or `auto` included) would take
that container as its scroller, so its timeline comes from an ancestor
outside it (`--tile`, `--cost-table`).

| Where            | Motion                                                                                                                                                                                   |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Section headings | Fade up `28px` as they enter.                                                                                                                                                            |
| Hero exit        | The copy lags the scroll (up to `70px`) and fades before it reaches the card; Home's card sinks to `0.94` and its shadow flattens.                                                       |
| Sample           | Rises from `0.92` and `56px` below until it is near the middle of the window, then plays (`preview.ts`). The spoken words lag `±6px` in their well; the raised result card leads `±6px`. |
| Bento            | Tiles rise as they enter, left to right within a desktop row (`8%` of the range per column). Each graphic lags `±10px` in its well; wide tiles lead `±10px`.                             |
| Provider board   | Rises from `0.94` and `56px` below until `40%` covered; its columns then fade up `18px` left to right (`6%` of the range apart).                                                         |
| Close            | Both offers rise as the island settles back to its inset; the license rises furthest (`0.92`, `72px`) and leads `±10px`.                                                                 |
| Pricing          | Plans rise left to right; cost rows and group labels fade up in turn; each three-year bar fills to its share.                                                                            |

**GSAP (`src/scripts/story.ts`).** One `gsap.matchMedia` context, off
entirely with reduced motion. Bento loops play only while their tile is
visible, as does the provider board's vocabulary fix. In browsers without
scroll timelines, GSAP gives headings, the sample, the provider board, tiles
and offers a one-time `36–48px` rise instead; with reduced motion nothing
moves.

The hero card rises once on load (CSS) and its bars grow. Resting CSS is always
the final state, so nothing depends on motion to be readable. Interaction
motion: the hero's dictation (`dictate.ts`), hover magnification
(`waveform.ts`), the island fill (`island.ts`), the segmented thumb
(`segmented.ts`), keycaps that follow the keyboard (`keys.ts`), the license
and provider board swaps and disclosures (CSS).

### Disclosure (`ui/Disclosure.astro`)

Native `details`/`summary` rows inside a raised panel, divided by grooves. The
plus sits in a small raised round button and turns 45° when open, and the answer
eases open and closed (`::details-content` with `interpolate-size`; browsers
without it toggle at once). Used for pricing questions and support
troubleshooting. Answers may include `code`.

### Header, footer, pricing, support

The header sits on the chrome and stays at the top as the page scrolls. It is
a three-column grid with equal outer columns: the Brand mark at the start; at
the window's true centre, Pricing, Support and Changelog as capsule links (the
current page sits in a recessed well, like the app's sidebar selection). The
well is one element in its link's grid cell. Moving between these pages, a
cross-document view transition slides it to the new link on
`SelectionMotion.curve` (`360ms`, `--ease-select`) while the labels crossfade
above it; only the header's links and well take part, so the rest of the page
changes at once. Layout's `pagereveal` script marks a move between two linked
pages `nav-slide`, where the moving group draws the well itself so it keeps its
shape; arriving from or leaving for another page fades it. Reduced motion and
browsers without cross-document view transitions change pages instantly. The
GitHub icon key and the primary "Get Airdraft" key at the end. The header's
keys (GitHub, Get Airdraft and the phone menu key) stand exactly as tall as the
brand capsule, `34px`, with a transparent margin that keeps a `44px` touch
target.

On phones (`560px` and below) the links and the GitHub key fold into a menu:
the header keeps the mark, Get Airdraft and a round menu key with two strokes.
The menu key wears the brand capsule's material rather than a key's: the
opaque `--chrome` face lifted only by the mark's soft shade and light at the
same `34px` depth, with no rim.
The menu is not a dropdown panel. Opening it pulls the header's own
progressive blur down the full width, from `100px` to the header plus the rows
plus `100px` (`440ms`, `--ease-out`; closing `320ms` on `SelectionMotion.curve`).
The blur's stops are measured up from its bottom edge, so above the rows it
is the full `32px` blur and the same `100px` fade sits only at its end; at
`100px` they are the app's ramp. It shows even before the island is full.
It carries the header blur's `65%` tint (below), so the rows keep
their contrast; they are ink, never muted, for the same reason. The
rows sit on it below the header row, aligned with the mark, each `44px` with
`12px` corners like the app's sidebar destinations: Pricing, Support and
Changelog, the current page resting in the `--sink-chip` well, then a groove
and "Source on GitHub" with its external arrow. Fixed row heights give the blur
its reach (`--menu-h`) without measuring. The rows follow the blur down one
after another (`35ms` apart) and fade at once on closing. While the menu is
open the key sinks, the mark's shade and light falling inside it, like the
app's microphone button under its overlay, and its strokes cross into a close mark. The blur fades through its
layers' opacity, never the container's: a translucent ancestor becomes their
backdrop root and draws a flat panel instead of a blur. The menu is a native
`popover`, so it works without JavaScript: the key toggles it, Escape and an
outside tap dismiss it and return focus, and the links follow the key in
reading and Tab order. Browsers without popovers keep the GitHub key and rely
on the footer's links.

Behind it is the app's progressive header blur
(`ProgressiveHeaderBlur.swift`): six stacked `backdrop-filter` layers (1 to
32px), each masked to the band where the app's radius ramp reaches it, so
content is lightly blurred at its bottom edge and fully blurred at the top,
while labels and controls stay sharp. The blur is `100px` tall at every width,
reaching past the header's row (`72px`, `64px` on phones) without moving it. At the top of the page it is
hidden; it fades in (`240ms`) once the island has filled the window
(`.is-blurred`, set by `island.ts`; see Layout), and stays shown without
JavaScript. The blur carries colour: a `65%` tint of `--island`, the surface
it covers once the page has scrolled (never the lighter chrome), above its
layers; only the phone menu opened before the island is full, still over the
chrome, takes `--chrome`. It fades out with the layers over the last `100px` (at the header's own `100px`, from
the top edge down) and appears and fades with them. It keeps whatever sits
on the blur in contrast whatever passes under it: white content in dark mode,
the graphite key in light. The tint sits on top of the blur, never in place of
it; never simulate the blur with a tint or an opacity fade; only Reduce Transparency gets an
opaque header, in the tint's colour. Anchors land below it (`scroll-padding-top`). The footer
sits on the chrome below the island.

Pricing keeps its copy to labels, prices and short checks; details belong in
the questions. Two plans share a row (`src/styles/pricing.css`): the
ready-to-run app leads, wider and raised like the homepage's license offer,
with One Mac (`$29`) and Three Macs (`$49`) side by side, divided by a vertical
groove, each a muted label, price and action; the Open source card mirrors one
license (`$0`, build instructions), so prices, keys and lists line up. A groove
separates each card's short checklist (`licenseIncludes`, `sourceIncludes`),
each item checked in a small recessed socket. License actions are the
purchase, disabled "Not on sale yet" until `siteLinks.checkout` is set; until
then build instructions hold the page's primary key, after that One Mac. Plans
stack under `1000px` (max `560px`) and licenses stack under `520px`. A note
gives the currency and tax basis. "What a year of dictation costs" follows: a
raised table from `src/data/pricing.ts` (setup, per month, first year, three
years; phones drop per month), Airdraft's setups and the muted subscriptions
under small group labels, each setup saying what leaves the Mac, each
three-year total over a usage track filled to its share of the most expensive
setup, then one note with the workload, models, token budget and price date.
Then the questions.
Support is troubleshooting disclosures, an issue link, then ways to fund the
project.

### Product guides and sharing

The homepage links to three guides after the hero, sample and interface section, using `GuideLinks`:
offline setup, local/cloud data flow, and source build versus official app. The
hub uses H2 card titles; related cards inside a titled section use H3. `GuideLayout`
reuses the subpage title, Section, Surface and Button, followed by visible wrapping
breadcrumbs and readable answer sections. Tables keep real headers and captions;
on phones they scroll inside a keyboard-focusable region without widening the page.
Cards retain the shared neutral materials and 28px padding (22px on phones).
Footer and Support links keep the guides reachable without changing the header.
The footer also links the release RSS feed, with a 760px link group to avoid an
isolated final link at desktop widths.

The shared 1200×630 social card uses the existing app icon, neutral chrome and
island, and factual product copy. Regenerate it from the repository root with
`swift apps/marketing/scripts/render-social-card.swift`. It contains no personal
app data, price or unverified availability claim.

### Changelog

The release timeline has one entry per product version and an initial source
build. Version, date and the latest-release chip sit above each raised `Surface`
card. Its linked title leads straight into described change items, separated by
the shared groove, followed by a release or source link. Neither the page title
nor release titles have summary paragraphs. Cards use the shared card radius,
padding and neutral materials; descriptions stay within `70ch`.

A release-family navigator sits beside the timeline in a recessed track. It is
`160px` wide with a `64px` column gap, narrowing to `140px` with a `32px` gap
below `1000px`. On desktop it sticks `124px` from the top. Below `700px` it
becomes an inline seven-column row above the timeline, with dates hidden. A
raised thumb follows the current family on the established `360ms`
`cubic-bezier(0.65, 0, 0.35, 1)` selection curve; links retain visible keyboard
focus and `aria-current` identifies the selected family.

A thin recessed rail fills with reading progress. Each entry has a raised stud;
the current entry's stud turns to the ink color and sinks into its socket.
Version links and linked release titles land below the shared header and move
focus to the entry. The timeline uses `36px` of leading space and `64px` between
entries, reduced to `24px` and `40px` on phones.

`src/scripts/changelog.ts` reveals each card once as it enters view. The card
rises `18px` over `650ms`; its title and change rows rise `8px` and fade from
`0.35` opacity over `480ms`, staggered by `55ms`, using the existing ease-out
curve. Resting CSS keeps every entry readable without JavaScript. Reduce Motion
removes reveals, thumb transitions and smooth scrolling, including animations
already running when the preference changes.

## Do's and Don'ts

### Do:

- Do take every value from the app's views (`Theme`, `SoftControls`, `NeumorphicSurface`, `HomeHero`, `IndicatorPanel`) and say which in a comment.
- Do keep light at the top left in both appearances, and check both.
- Do keep exactly one primary key in view at a time.
- Do use the seven type steps and the `0.8125rem` floor.
- Do keep sample, pricing, license and download claims factual. Hide anything unconfirmed.

### Don't:

- Don't introduce a hue: no blue, violet or cyan text, fills, glows, gradients, focus rings or selection. Status dots are the only colour. `pnpm check` fails otherwise.
- Don't lower a shadow's contrast to make it subtle; shrink its spread.
- Don't use wide, low-contrast ambient shadows or blooming white halos.
- Don't divide content with flat hairlines; use the groove or space.
- Don't tilt, rotate or fly a lit object through perspective: its light is fixed at the top left. Objects rise from and sink into the surface, and selections slide.
- Don't repeat a two-tone headline pattern or add eyebrow labels above section headings.
- Don't add copy that restates a heading, narrates the page, or labels the obvious. If a line doesn't change a decision, cut it.
- Don't hand-roll a key or section; extend the component instead.
- Don't put more than one line of text in a bento tile, or a graphic that isn't built from the app's parts.
- Don't animate anything that has no resting state in CSS, or ignore reduced motion.
- Don't publish app renders that contain personal profiles, device names, history or usage counts.

## Analytics consent

The optional analytics notice reuses the neutral panel and Button components.
Allow and Decline have equal visual weight. Keep it readable and scrollable on
small screens, with a link to the privacy page. It stays hidden without
JavaScript or when collection is disabled. Privacy uses the shared subpage
layout and lets visitors turn analytics off.
