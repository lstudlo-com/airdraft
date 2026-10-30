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
  quiet: "#5e5e5e"
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
  control: "12px"
  field: "12px"
  cap: "7px"
  pill: "999px"
spacing:
  step: "4px"
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
    rounded: "{rounded.control}"
    padding: "0 24px"
    height: "48px"
  key:
    backgroundColor: "{colors.control-top}"
    textColor: "{colors.ink}"
    typography: "{typography.action}"
    rounded: "{rounded.control}"
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
    rounded: "{rounded.control}"
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

Almost everything is a neutral gray, as in the app. The exceptions are the
three status dots (green, orange, yellow), which mean the same thing they mean
in the app, and one accent, `--accent`: the app's system accent blue
(`#007aff` light, `#0a84ff` dark). The accent marks progress and the current
step of a story only (the dictation sample's current step number and its
filling step tracks, the Transcribe playhead and current beat number, and the
provider channels' progress bar);
never text, control fills, glows, gradients, focus rings or selection. Where
white text sits on it (the sample's current step number), it takes
`--accent-strong` (`#0064d2`), a deeper shade of the same blue at 5.6:1 with
white; the system blue gives only 4.0:1 (light) and 3.6:1 (dark).
`scripts/check-neutral.mjs` enforces this in `pnpm check`.

Tokens live in `src/styles/global.css`; the sidecar `.impeccable/design.json`
carries shadows, motion, breakpoints and component previews.

**Key Characteristics:**

- One light source, top left, on every raised and recessed surface, in light and dark.
- The page is the app window: `--chrome` around a rounded `--island`; everything sits on the island.
- Raised: a 1px top-left rim, a shade cast down-right and a white highlight cast up-left.
- Recessed: inner shade at the top left, inner light at the bottom right.
- One graphite key for the primary action; everything else is a gray rounded key.
- Keys, fields and segmented tracks share one corner, `--radius-control` (the app's 8-point `SoftControl.radius` at the site's 44px key scale); never capsules.
- Engraved grooves (a shade line over a highlight line), never flat hairlines, to divide rows.
- A showcase is a scene of separate objects on the island, never one slab holding every part. Its steps or beats sit on the island under the title, and the scroll tells the story (pinned on desktop, reversible). Raised means what you act on or choose; recessed means what you read.
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
- **Quiet** (`#5e5e5e` / `#a3a3a3`): only the hero's facts line, a small label under the keys that never competes with them. It is dimmed further to 60% opacity (owner's choice, 2026-10-30), which puts it below AA (about 2.4:1 light, 3.1:1 dark); the same facts are in the lede, the FAQ and Get Airdraft.

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
Margins, paddings and gaps on the 4px grid use `--space-n` (n × 4px, from
`--space-1` to `--space-21`); the steps between (6, 10, 14, 18, 22px) are
deliberate per-component values translated from the app.

The homepage runs: the hero, the sample ("Hold, speak, let go"), the features
bento, Transcribe, the provider board, the interface, Setup guides, Questions,
then Get Airdraft. What Airdraft does comes before how it looks, and the
questions sit just above the offers they answer.

Subpages (Pricing, Support, Changelog) are `main.island.subpage` and open with
the same title block: `Section level={1} first`, the headline step for the title
(`.page-title`), and the full content width. An intro is optional; Changelog
opens with its title alone. No subpage narrows its content. The title sits
`0.75` of a section gap (`108px`, `90px`, `72px`) below the island's top edge,
a little further than the later
sections sit from each other (`0.72` of the gap: `104px` on desktop), which use `entry-title`
headings, a step below the page title.

The homepage bento is a three-column grid with `24px` gaps and nine tiles in
a fixed rhythm: wide + narrow, three narrow, narrow + wide, wide + narrow.
The last row holds the mixed-language tile (one sentence with English terms
in several languages, the page's own first, under a segmented picker of
language names, cycling while on screen; the Traditional Chinese page keeps
the app's 繁體中文 | 简体中文 script picker over one mixed sentence, and the
Simplified Chinese page shows 简体中文 | 繁體中文) and the subscription refiners (Claude Code raised with its status dot, Codex recessed). The provider board
never pins: it is about one viewport tall on desktop and stacks below `1000px`.

| Max width | Changes                                                                                                                                                                                                                           |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `1000px`  | Gutter `32px`, section `120px`; bento becomes two columns (wide tiles span both); pricing plans and homepage offers stack (max `560px`); the provider board stacks its three columns; the hero waveform drops its 12 oldest bars. |
| `700px`   | Gutter `20px`, section `96px`, island inset `6px`; sample, bento, footer and changelog stack; the hero waveform shows 15 bars; the HUD shows ten bars.                                                                            |
| `560px`   | The header shows the mark, Get Airdraft and the menu key; the links, GitHub and the language key move into the blur the menu pulls down.                                                                                          |
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

### Hero copy

The headline, then one sentence that says what Airdraft is (`home.lede`:
`--step-1`, muted, at most `38rem`, `24px` below), the three keys, then the
facts line, dimmed. There is no availability line. Until checkout opens the
primary key (Get Airdraft) leads down to `#get-airdraft` on the page, where the
free build is; once it opens, to Pricing. The lede rises with the keys.

### Hero card (`HeroCard.astro`, `ui/Waveform.astro`)

Home's hero card from the app, without its metrics (the site never shows usage
counts): a raised card with a faint top-left sheen around the waveform well,
nothing else, with the same inset on every side (two thirds of `32px`; two
thirds of `16px` on phones). The app's first-run line, "Hold ⌃⌥ and speak.
Each dictation adds a bar.", stays only for assistive technology. The forty
bars are decorative; their heights are a fixed pattern shaped like the app's
`0.26 + 0.74 × √share` mapping, not data.

The card sits `84px` below the hero facts line, reduced to `60px` at widths
of `700px` or less.

`Waveform` is the well: `70px` tall (`56px` on phones), raised gray bars up to
`32px`, and a `40px` graphite caret. Bars grow from 12% on load. Like the app,
the bars near the pointer grow by up to 28% on a Gaussian two and a half bars
wide, never past the caret, and the bar under the pointer deepens toward the
caret's tone (`src/scripts/waveform.ts`). They also rise with the shared voice.
Narrow screens hide the oldest (leftmost) bars so the newest stay beside the
caret. With reduced motion the bars are static; only the hover tone changes.

The card works (`src/scripts/dictate.ts`). Holding ⌃⌥ while the card is on
screen, or pressing and holding the well, plays a pretend dictation: the
recording pill (timer and meter) rises `16px` under the card, a live bar enters at the caret and follows a synthetic speech envelope,
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
lit inside the bottom right. Geometry uses the original capsule mark's 364-point height:
bars `38` wide, `190 × level` tall, `30` apart; the caret `208` tall with `20`
more before it. Shadows scale with height. It is `34px` tall in the header and
`28px` (the sidebar's own size) in the footer, a static mark inside the home
link, whose accessible name is "Airdraft". Increase Contrast adds edges. The
outlined `SidebarWordmark` SVG remains the installer's wordmark only.

### Button (`ui/Button.astro`)

The site's keys (`SoftButtonStyle`). Renders `<a>` with `href`, otherwise `<button>`.

| Prop                 | Values                                    | Notes                                                                                      |
| -------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------ |
| `variant`            | `primary`, `secondary` (default), `quiet` | One `primary` in view at a time. `quiet` is an inline text action.                         |
| `size`               | `md` (44px), `lg` (48px)                  | `lg` for hero and closing actions.                                                         |
| `icon`               | `none`, `right`, `down`, `external`       | Trailing arrow.                                                                            |
| `iconOnly` + `label` |                                           | 44px square key; `label` is the accessible name and tooltip. Put the SVG in `slot="icon"`. |
| `disabled`           |                                           | Renders a pressed-in, non-interactive `<span aria-disabled>`.                              |

Keys are raised rounded rectangles on `--radius-control`. Hover lightens the top
of the face; pressing sinks the key into a well. Focus shows the 2px ink ring.

The native Transcribe flow's `SoftButtonStyle(prominent: true)` adds a blue fill
and white type to that same raised/pressed geometry. Website primary keys keep
the graphite `--key-*` tokens specified here; the native variant does not change
the site's palette.

### Segmented picker (`.segmented`, `src/scripts/segmented.ts`)

`SoftSegmentedPicker`: raised segments on a recessed rounded track, with the
thumb's corners concentric 3px inside the track's. One raised thumb slides to the selected item (`.is-selected` or `aria-pressed="true"`) on
`SelectionMotion.curve` (`cubic-bezier(0.65, 0, 0.35, 1)`, 360ms), whatever
changed the selection; its light and shade stay clipped inside the track.
Without JavaScript the selected item draws its own face. The selected label is
ink and semibold; the others are muted. Used for the sample's profiles and the
bento's profile and history graphics.

### Section, Surface, Chips, Keys, Tag, StatusDot

- `Section`: `title`, optional one-line `intro`, `level` 1 or 2, `first`, `sticky`. Owns the heading id and spacing; `level={1}` titles get `.page-title`. Its id comes from an ASCII title, so translated sections pass `id`. On the homepage (`main.home`) every section's title is centered over its content and has no intro; subpages keep title and intro at the leading edge.
- `Section sticky` (the bento, Transcribe and the provider board; the interface and the sections after it scroll normally): the title holds `48px` below the site header (`40px` on phones, none on windows under `540px` tall) while the section's content scrolls up under it, until the section ends. Behind the title the header's progressive blur continues (`.heading-blur`: the same six layers, their quadratic ramp stretched over the band, and the header row's `35%` veil, never the heavier tint, which would hide the content) from the window's top to `40px` below the title, so content stays visible, blurred, as it passes under the title, as it does under the header. Homepage titles are a step smaller than subpage titles (`28–36px`), and content starts a quarter further from its title (`55px`, `40px` on phones). A negative margin and its own formatting context keep the section's spacing unchanged. `src/scripts/sticky.ts` measures, on the section's view timeline (`--sticky`), when each item (`data-follow`, bento tiles, Transcribe beats, provider cards) rises: in order, `70px` of scroll apart, starting `260px` before the title settles and never before the item comes into the window. A story stage (`data-pin`) that fits under the settled title pins there while its runway (`data-pin-runway`, `120vh`) scrolls past and its story runs over `--story-0` to `--story-1`.
- `Surface`: `variant="panel"` (raised card) or `"well"` (recessed), any element via `as`. Never nest a panel in a panel. Lists and tables go inside a raised panel, divided by grooves, as in the app's settings cards.
- `Chips`: a list of recessed capsules. `Chip` is a single one: `tone` `muted` (recessed, default) or `strong` (raised), `as` `span` or `li`, and an optional leading `dot` (`ok`, `attention`, `busy`, `inactive`). The bento graphics, the transcript's speaker chips and `/design/` use it; never hand-write `.chip-*` classes.
- `Keys`: raised keycaps in the rounded system face; `size="lg"` and `keys-xl` for feature tiles. Modifier keycaps carry `data-key` and sink while the visitor holds that key (`src/scripts/keys.ts`), on every page. With a `label` the caps read as one image of that name; inside decorative art that is already hidden, leave it out and they are hidden too.
- `.tag`: a small recessed label.
- `.status-dot` with `data-tone` `ok` (default), `attention`, `busy` or `inactive`: the only colour on the site.

### Hud (`ui/Hud.astro`) and the dictation sample

`Hud` is the app's recording pill (`IndicatorPanel`): a graphite rounded
rectangle with a white top-left rim, holding a small dark inset well of white
bars, then a timer or state in the rounded face. It stays dark in both
appearances, as in the app. Pass `levels` for a still frame and `locale` for
the app's own state labels in that language (潤稿中 and 轉錄中 on the
Traditional Chinese pages, from `src/data/app.ts`, which holds each
language's catalog labels); scripts read them from
its `data-refining` and `data-transcribing` attributes.

The sample (`DictationPreview.astro`, `src/styles/sample.css`) is the
homepage's one telling of how dictation works, the first section after the
hero, titled "Hold, speak, let go" (each language's `preview.title`). It
renders its own section (`id="try"`, which the hero's "Try the sample" key
targets) and is a scene of separate objects on the island, never one panel.
The three steps (`preview.steps`: "Hold ⌃ ⌥ and speak" with real keycaps,
"Let go, and Airdraft tidies it", "It lands at your cursor") sit centered
under the title, outside any card: a raised number above each label, joined
by recessed tracks that fill with the accent as the story moves on; the
current number takes `--accent-strong`, reached steps read as ink and
upcoming ones fade. Below them stand a deep recessed "What you said" well
(`--sink-section`, card radius), the recording pill floating on an engraved
groove between them (scaled 1.12 on desktop, riding higher with a longer
shadow while it works, dimmed at rest), and the "What Airdraft inserts" card,
pressed in (`--sink-soft`, 0.985) while it waits and raised (`--raise-card`)
once typed. The profile picker and, under it, the Run key stand in the middle
column under the pill, so the scene is one row. The middle column is at least
as wide as the pill's widest state (`--hud-column`, measured by the script), so
the well and card never move while the pill changes; at `700px` or less the
controls follow the card.

The scroll tells the story. Above `700px`, with motion allowed and when the
scene plus `32px` fits under the header, it pins at the vertical centre below
the header over a runway of the larger of `900px` and 1.7 window heights; the
scroll position drives it: 0–4% lead-in, to 46% listening (words light up,
the pill's timer runs, its meter moves only while scrolling), to 56% decoding,
to 68% refining (fillers struck), to 90% typing, then the finished frame.
Scrolling back reverses every part. Run, a profile change or holding ⌃⌥
(only while the pointer or focus is on the scene; under `0.3s` or a third key
cancels) plays it in real time, and the scroll takes over again after about
`48px`. Phones, short windows and browsers without IntersectionObserver do not
pin: it plays once as it reaches the middle of the screen and jumps to its
finished frame off screen. At `700px` or less the objects stack and the
groove stands upright. Pinned objects rise only within their entry range, so
none freezes half risen. A visually hidden status line speaks the state.
Without JavaScript the Clean result shows with every step readable; reduced
motion shows the finished frame and never pins or plays. Its accessible name
is "Sample dictation".

### Transcribe (`MeetingsSection.astro`)

The app's Transcribe page (formerly Meetings; the file, `#meetings` anchor and
`meetings.ts` keep the old name). "Turn any recording into a transcript"
follows the features bento and precedes the provider board, its title sticky
(`Section sticky`). It is four separate objects on the island, each under a numbered label
(an `h3`, `meetings.steps`) whose number takes the accent while its beat
plays; there is no status dot:

1. The recording: a raised card with a five-bar icon in a recessed socket,
   the title, one metadata line and the play key.
2. The speaker lanes: a well carved into the island, one lane of Home
   waveform bars per speaker (the first speaker's bars in the caret's deeper
   tone), lying flat until the accent playhead reaches them. The lanes are
   computed from the turns' timestamps, a quarter-second column each.
3. The transcript: one raised card, like the app's transcript editor, its
   turns in rows (speaker chip, time, words in aligned columns, a subgrid)
   divided by grooves; each row waits empty, then its words fade up. The
   export beat beside it is as tall, its guide link on the line where the
   transcript card ends.
4. The export: four recessed slots that TXT, JSON, SRT and VTT tiles rise
   into one by one, then the transcription guide link.

On desktop the first row is the recording and the lanes, the second the
transcript and the export. One number from 0 to 1 drives the story and rests
at 1, so without JavaScript or with reduced motion the finished transcript
shows. The beats arrive one by one as the title settles. Above `1000px`,
where the stage fits under the settled title, it pins there and the story
runs over a `120vh` runway, backwards when scrolling back; otherwise each beat
plays its part over the scroll after it arrives. The play key plays the whole story in about `9s` and pauses it; a
timestamp plays from that turn and a click on the lanes from that point. A
timed play overrides the scroll animation with an `!important` value and
hands control back once the scroll would show the same finished frame, or
when the section leaves the screen or the tab hides; browsers without scroll
timelines play it once on arrival. Nothing is heard. The transcript is
authored sample text from an interview; Chinese and Japanese pages name
Qwen3-ASR 1.7B, the others Whisper Large v3 Turbo. Feature caveats live in
the guide.

### Interface section (`InterfaceShowcase.astro`)

"An interface you’ll love to use" follows the provider board and precedes the guides.
Its title is centered over the window, like every homepage section heading,
and scrolls with the page (from here on no title holds); the window follows
it in from further down (rising from `0.84`, its shadow growing), its callouts
after it. It shows the real app: the Settings page rendered from a Debug build by
`scripts/render-app-window.sh` (an isolated empty data directory, so no
history, usage count or personal setting; grayscale, as the app looks with the
Graphite accent) in `public/app/`: `configuration-*` in English and
`configuration-zh-tw-*` in the app's Traditional Chinese interface for the
`/zh-tw/` homepage, both from a Debug build of the current release. The other
languages show the English render until theirs exist, and the caption says
the window is the English interface; while a language's interface is not in a
published release (`interfaceReleased` in `src/i18n/index.ts`) the caption
also says the released app still shows English.
Re-render it when the Settings page, sidebar or materials change. The source render is 784 by 1000 points so all six recording-window choices,
the Disco switch and the timer row fit. Disco is off in these grayscale screenshots.
The window is `784px` wide at most, `16px`
corners (`12px` on phones), raised with the hero's spread, with an inactive
window's gray close and minimize buttons 16 points in. Both appearances are
stacked; a groove divider with a raised round key compares them. Dragging the
window or the keyboard on its range input moves it; without JavaScript it rests
at half. The recording-window picker offers Classic, Cube, Sonic, Orbit, Silk and None,
with Classic selected
and the timer off by
default. All five visible capsules share one size; the specimens and preview
faces are 1.2 times their former spatial size. Sonic shows braided ribbons, Orbit
interlocking silver rings, and Silk a folded metallic ribbon. Its callout points
to the first preview row and describes their voice response. On wide windows (from
`1280px`) six callouts name the materials at
their places in the window (carved mark, pressed well, raised button, raised
card, engraved divider, reactive capsules), joined by a leader ending in a
graphite stud ringed with the chrome. The window rises with the scroll and the
callouts draw out after it. Once, when the window is half in view, the divider
sweeps from the right edge to the middle over `1200ms` on the selection curve
(a smooth cubic, never linear); dragging follows the pointer directly.
Reduced motion and phone widths (`700px` or less, where the waiting divider's
key would sit cut in half at the clipped right edge) skip the sweep and rest it
at half, as without JavaScript.

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
Mac" boundary whose signal runs along grooves. Without JavaScript they show
their final frame.

The graphics perform while they are on screen (`src/scripts/bento.ts`,
named by `data-art`; it sets up `.bento:not(.specimens)`, since the interface
specimens are a `.bento` too). When a tile is first mostly on screen its
graphic starts, the tiles of a row one after another from the left (`220ms`
apart), then repeats twice on its own rhythm (about `5s`, `6.5s` for the
shortcut and cursor pair; choice tiles walk through their choices every
`2.8s`) and rests on its final frame, so nothing keeps moving unasked (WCAG
2.2.2). Coming back on screen, or a poke, allows another round.
Hovering a tile with a mouse, or tapping it, plays it at once (at most once a
second) and holds its loop for `8s`, so a choice the visitor made stays; a
choice tile tries its next choice instead. The parts
that are controls in the app work: segmented choices and the subscription
chips select on click (the chosen chip rises, the other sinks), and holding
the shortcut tile's keycaps, or the visitor's own ⌃⌥ while the pointer or
focus is on that tile (never VoiceOver's ⌃⌥ commands elsewhere), records in the cursor tile (live meter, timer) and types on release,
so the shortcut drives the pill as it does in the app. A third key cancels,
as in the hero. The dictionary's fix rises from the surface (flat, `0.92`,
shadow growing in); each stop on the privacy path rises from its socket as
the signal passes. A field's caret blinks while its tile is on screen, except
while text is typed. A tile leaving the screen jumps to its final frame, so
no timer runs off screen. With reduced motion nothing plays or loops; choices
still change, in place.

### Provider board (`PipelineStory.astro`)

"You choose where each step runs" (`src/styles/pipeline.css`) is three
separate raised cards on the island, in the order dictation runs: Speech,
Refinement, Insertion. Each has a numbered keycap and title, its choice of
where it runs (native radio groups as segmented pickers: This Mac | Cloud,
This Mac | Cloud | Subscription; Insertion reads "At your cursor"), one line
on what leaves the Mac, a settings-style table (rows divided by grooves, the
chosen row in the sidebar's recessed selection well with a raised check
island), and the text that step hands on. Recessed channels join the cards
at the height of those outputs; an accent progress bar and a small raised
packet travel along them.

One number, `--p` (0 to 1, from a CSS scroll timeline; `pipeline.ts`
computes it where scroll timelines are missing), drives every state, so the
story reverses when scrolling back. One dictation runs through: Speech
(.08–.28) shows the recording bars and then "um meet me in cooper tino at
nine", the misheard words underlined; Refinement (.40–.60) outputs "Meet me
in cooper tino at nine."; Insertion (.72–.92) strikes "cooper tino", brings
in Cupertino from its vocabulary table (six spelling examples) and shows the
caret. A card's shadow grows as it is reached and it floats `10px` forward
while it works, never changing size; the
chosen row's check island sinks with a busy dot and rises with its check;
finished keycaps turn ink. The cards arrive one by one as the sticky title
settles. Above `1000px`, where they fit under the settled title, they pin there
and the dictation runs over a `120vh` runway; otherwise it runs from the first
card's arrival to past the last's. At `1000px` or less they stack, the channels
stand upright. Changing a choice reruns that card. Reduced
motion, or no scroll timeline and no JavaScript, shows the finished frame
(`--p: 1`).

### Get Airdraft (`GetAirdraft.astro`) and the license card (`LicenseCard.astro`)

The homepage close: two equal offers side by side, Build it yourself first
(Free, build instructions), then the ready-to-run app's license card, raised
with the hero spread. Until `siteLinks.checkout` is set, Build instructions is
the section's one primary key and the license card's See pricing is
secondary; once checkout opens, See pricing is primary. Prices use the shared
`.price` class (with `.price-unit`), as on Pricing.
Both cards have the same rows (title, price, note, then the action below a
groove) as subgrid rows of one shared grid, so titles, prices, notes and keys
line up across the cards; both keys are the large size.

The license card's title sits beside a segmented **1 Mac | 3 Macs** choice;
below it, only the chosen license's price ("one-time") and use show, and
switching slides the new line up into place. The choice is a native radio
group and CSS `:has()` picks the visible lines, so it works without
JavaScript; `segmented.ts` adds the sliding thumb. Every title row is the
choice's height (`38px`). Under `1000px` the cards stack (max `560px`). The
pricing page lists each license as its own plan instead.
Prices, Mac counts and inclusions come from `src/data/site.ts`. Each license's
price keeps a visually hidden plan name, so text extraction reads "$29 (1 Mac)
$49 (3 Macs)" rather than the run-together prices.

Until checkout opens, `NotifyRow` sits under the homepage's offers (Pricing has
none): one muted line and two quiet keys, Watch releases on
GitHub and the changelog RSS feed in the page's language. It is the way to
hear when the official app goes on sale; it renders nothing once it is.

### Questions (homepage)

"Questions" (`home.faqTitle`) sits between Setup guides and Get Airdraft: the
pricing page's raised question list with grooved `Disclosure` rows, five
questions in each language (`home.faq`): whether Airdraft is free (the answer
switches with `siteLinks.checkout`), which Macs it runs on, whether it works
offline, what leaves the Mac, and how it differs from Apple Dictation. Answers
link to the guide or page that goes deeper. They are visible content only;
there is no FAQ markup (see `SEARCH.md`).

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
outside it (`--tile`, `--cost-table`). Production CSS is minified with esbuild
(`astro.config.mjs`): Lightning CSS folds `animation-timeline` into the
`animation` shorthand, which Chrome drops, removing every scroll-driven
animation; `scripts/check-search.py` rejects a build that does.

| Where            | Motion                                                                                                                                                                                                                         |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Section headings | Fade up `28px` as they enter; on the homepage what they introduce follows from further down (`96px`, `140px` of scroll later), so it slides in behind the title at a different speed.                                          |
| Hero exit        | The copy lags the scroll (up to `70px`) and fades before it reaches the card; Home's card sinks to `0.94` and its shadow flattens.                                                                                             |
| Sample           | The steps, the well, the pill, the controls and the card follow the title one after another; above `700px` the scene pins and the scroll plays the story (`preview.ts`), otherwise it plays once mid-screen.                   |
| Bento            | Under its sticky title, tiles rise one by one (`110px`, from `--in`, `sticky.ts`) as the title settles or as they come up, then scroll under the title's blur. Each graphic lags `±18px` in its well; wide tiles lead `±16px`. |
| Transcribe       | The beats arrive in turn under the sticky title; the stage pins under it where it fits and the scroll runs the story, otherwise each beat plays after it arrives (`meetings.ts`).                                              |
| Provider board   | The cards arrive in turn; `--p` runs one dictation through them and the channels, pinned under the title where it fits (`pipeline.ts`, `sticky.ts`).                                                                           |
| Close            | Both offers follow their title, the license from furthest (`0.94`, `140px`); both settle level.                                                                                                                                |
| Pricing          | Plan cards and what they include rest in place from the first frame (never mid-rise); the cost rows fade up in turn; each three-year bar fills to its share.                                                                   |

**GSAP (`src/scripts/story.ts`).** One `gsap.matchMedia` context, off
entirely with reduced motion. In browsers without scroll timelines, GSAP
gives headings, the sample, the panels, tiles and offers a one-time
`36–48px` rise instead; with reduced motion nothing moves.

**Beats.** Below the hero the page alternates between something that plays
for the visitor and something the visitor plays, and builds to one climax;
it is never nine things moving at once. Each beat plays once when it is on
screen, then rests on its final frame until the visitor touches it, and
answers touch from then on: the sample types its result (`preview.ts`); the
Transcribe panel writes its transcript (`meetings.ts`); the interface window's divider
sweeps and its specimens loop until touched (`interface.ts`); bento tiles
loop while on screen and replay on hover or tap (`bento.ts`); the provider
board runs one dictation through the chosen steps (`pipeline.ts`), the
climax before the close. Watch visibility
with IntersectionObserver; anything off screen stops on its resting frame,
and no frame loop runs while nothing moves. Performances move transforms,
opacity and shadows only (the Transcribe playhead slides; it never resizes). Loops
run only while their element is on screen; never add an ambient loop that runs
whether or not the visitor is looking.

**Entrances and depth (`src/scripts/flourish.ts`, motion.css).** The headline
rises line by line out of its own line boxes on load, then the keys and facts
follow; section headings rise word by word (character pairs in Chinese and
Japanese) as they arrive, and the content under them rises the same way
(`32px`, out of a `6px` blur, blocks arriving together `90ms` apart): guide tiles, guide and text-page sections,
breadcrumbs, pricing questions and changelog cards. Every page loads it
(`Layout.astro`). Blocks the scroll timelines already raise are left to them; the hero card drifts up to `12px` toward the pointer
and the copy `6px` away, translation only, so light stays at the top left. The
app window grows from `0.84` and `140px` below as it arrives.

The hero card rises once on load (CSS) and its bars grow. Resting CSS is always
the final state, so nothing depends on motion to be readable. Interaction
motion: the hero's dictation (`dictate.ts`), hover magnification
(`waveform.ts`), the island fill (`island.ts`), the segmented thumb
(`segmented.ts`), keycaps that follow the keyboard (`keys.ts`), the bento's
controls (`bento.ts`), the Transcribe panel (`meetings.ts`), the license and
provider board swaps and disclosures (CSS).

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
language key (a globe icon key named "Language: English" in the page's
language), the GitHub icon key and the primary "Get Airdraft" key sit at the
end, one `10px` step apart (the `.header-actions` gap, so right-to-left pages
need no margins). The header's keys (language, GitHub, Get Airdraft and the
phone menu key) are raised keys exactly as tall as the brand capsule, `34px`,
with a transparent margin that keeps a `44px` touch target.

The language key opens the language menu (`LanguageMenu.astro`,
`src/styles/languages.css`): a native `popover` raised panel (as wide as the
longest name plus its row insets, at least `132px`,
anchored under the key with `position-area`, otherwise at the header's end)
with one `40px` row per language, each named in itself and tagged with its
`lang`; the current language rests in the recessed `--sink-chip` well. A row
leads to this page in that language: every page exists in every language, so
nothing is marked as English. It works without JavaScript; the footer has no
language list.

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
Changelog, the current page resting in the `--sink-chip` well, then a groove,
"Source on GitHub" with its external arrow, and a Language row with a globe
glyph and the current language that opens the same language menu over the
phone menu, across the width under the header (`--menu-h` is `262px`). Fixed row heights give the blur
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
the graphite key in light. Behind the header row itself sits a second, steady layer:
the island's colour (`--island`, the surface scrolling under it: the darker
gray in dark mode, the light gray in light mode; the phone menu opened over
the chrome takes `--chrome`, like the tint) at `35%`, solid through the row and
feathered out only below it, so the nav labels stay readable over busy content. The tint sits on top of the blur, never in place of
it; never simulate the blur with a tint or an opacity fade; only Reduce Transparency gets an
opaque header, in the tint's colour. Anchors land below it (`scroll-padding-top`). The footer
sits on the chrome below the island: the mark, its links, and under them every
language named in itself, the current one in ink.

No right-to-left language ships yet; a locale with `dir="rtl"` in `src/i18n/locales.json` is ready for it.
`src/styles/languages.css` moves flow-relative spacing to logical properties
there and turns arrows that point along the reading direction. The light still
comes from the top left, so shadows, rims and raised edges are unchanged.
Pictures of the app keep its left-to-right layout: the window render and its
callouts, the Home waveform (newest bar last), the recording pill and key
caps (⌃ before ⌥, as macOS prints shortcuts).

Pricing keeps its copy to labels, prices and short checks; details belong in
the questions. The plans are three equal raised cards under two group titles
on the island, "Open source" (Build it yourself, `$0`) and "Ready-to-run app"
(One Mac `$29`, Three Macs `$49`, raised with the hero spread); titles,
prices and keys line up across all three (`src/styles/pricing.css`). Each
group's checklist (`pricing.sourceIncludes`, `pricing.licenseIncludes`) is
its own well carved into the island under its cards, headed by its list
label, each item checked in a small recessed socket. License actions are the
purchase, disabled "Not on sale yet" until `siteLinks.checkout` is set; until
then build instructions hold the page's primary key, after that One Mac. At
`1000px` or less the groups stack (the source card beside its list); at
`560px` or less everything is one column. A note gives the currency and tax
basis. "What a year of dictation costs" follows as two objects sharing one
column layout so figures line up: Airdraft's setups in a raised table and
the subscriptions in a recessed one (its headers for screen readers only),
figures aligned to the end, each setup saying what leaves the Mac, each
three-year total over a usage track filled to its share of the most
expensive setup; phones drop the per-month column. Then one note with the
workload, models, token budget and price date, then the questions.
Support is troubleshooting disclosures, then an issue link; it asks for no
donations.

### Guide and text-page sections (`GuideSection.astro`)

Guides, Support and Privacy open with the page title alone (no intro line),
then sections. A section has no frame: a numbered keycap and heading on the
island, then its body at most `70ch` wide; sections sit `72px` apart (`56px`
on phones). The content picks its material: steps are raised number keycaps
on a recessed track; `guide-decisions` is a grid of raised cards (four make
2 + 2); tables and troubleshooting sit in a raised panel; plain lists use
recessed dots; Privacy's event list is a grid of small cards and its
analytics choice a settings card. Support's "Still stuck?" is a raised card
beside the troubleshooting (`GuideSection aside`), sticky on desktop; its top
lines up with the troubleshooting card, not its heading (the section and the
card share the article's rows through `subgrid`).

With at least three sections, `GuideToc` ("On this page", `208px` wide,
sticky `124px` from the top, hidden at `1000px` or less) lists them, a raised
thumb on a recessed track following the section being read on the selection
curve.

### Guide picker (`GuideLinks.astro`, `GuideGlyph.astro`)

The homepage's "Setup guides" section (設定指南, 设置指南, Guías de
configuración, 設定ガイド) has no intro: one raised tile
per guide, the whole tile a link named by the guide's full title. Each tile is
a small graphic in a recessed `112px` well over one short label
(`guideLinks.labels` in `src/i18n/messages/<locale>.ts`, by slug: English four
words at most, Chinese eight characters, kept inside the title where possible
so voice control finds it). No summary,
no "Read Guide" key. The graphics are the app's parts (`guideGlyphs`, by
slug): the 繁｜简 picker under a mixed phrase, a terminal prompt with the ink
caret, Home's waveform well inside This Mac, the provider board's This Mac /
Cloud rows, the $0 and license price keys, Transcribe's speaker chips, and a
grooved table with one column in the selection well. Hover and keyboard focus
lift the tile `2px` with a wider shade and give its graphic one move (the
selection slides, a key sinks, a chip rises, bars grow, the caret blinks);
pressing sinks the tile like a key. Reduced motion keeps them still; the
resting frame is complete without JavaScript. Rows stay balanced: up to four
across, three when that divides evenly, a short last row centred (seven read
as 4 + 3); two across below `1000px`; below `420px` one per row with the
graphic beside its label. Guide pages reuse it for related guides; the hub
passes `detail`, which shows the full title as its heading and the one-line
summary instead of the label. The Traditional Chinese homepage adds one link,
更多指南（英文）, to the English hub.

### Product guides and sharing

The homepage links to the guides after the interface section, using `GuideLinks`
as the guide picker (see Guide picker above): offline setup, mixed Chinese and
English, coding agents and terminals,
local/cloud data flow, source build versus official app, private meeting
transcription, and the app comparison, each leading to the guide in the
page's language. The mixed-language
results table reuses `.guide-table-wide`, so on narrow regions each model
becomes a block of labelled rows. The
comparison table (`.guide-table-wide`) keeps seven columns at `880px` minimum
(`760px` on phones) inside its focusable scroll region, then lists sources with
`time` check dates. The
hub keeps H2 titles with one summary line in the picker's `detail` variant; related
guides inside a titled section use the picker with H3 names. `GuideLayout`
reuses the subpage title, Section, Surface and Button, followed by visible wrapping
breadcrumbs and readable answer sections. Tables keep real headers and captions;
on phones they scroll inside a keyboard-focusable region without widening the page.
Cards retain the shared neutral materials and 28px padding (22px on phones).
Footer and Support links keep the guides reachable without changing the header.
The footer also links the release RSS feed, with a 760px link group to avoid an
isolated final link at desktop widths.

Each language has a 1200×630 social card (`social-card.png` for English,
`social-card-<code>.png` otherwise) with the existing app icon, neutral chrome
and island, and factual product copy in that language ("Speak into any app.
Transcribe anything. Keep it on your Mac."), matching its `og:image:alt`.
Regenerate them from the repository root with
`swift apps/marketing/scripts/render-social-card.swift`. They contain no personal
app data, price or unverified availability claim.

### Changelog

The release timeline has one entry per product version and an initial source
build. Version, date and the latest-release chip sit in a `112px` column
beside each card, sticky while a long card is read (above it at `1000px` or
less). A feature release (x.y.0) shows its linked title on the island above
its raised `Surface` card, never inside it; the latest feature release is
raised with `--raise-hero`. Patch releases (x.y.z with z above 0) show no
title (it stays for screen readers) and are recessed wells, even when one is
the latest release. The card holds described change items, separated by
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

- Don't introduce a hue beyond the status dots and `--accent`, and use the accent only for progress and a story's current step: no coloured text, control fills, glows, gradients, focus rings or selection. `pnpm check` fails on any other hue.
- Don't lower a shadow's contrast to make it subtle; shrink its spread.
- Don't use wide, low-contrast ambient shadows or blooming white halos.
- Don't divide content with flat hairlines; use the groove or space.
- Don't tilt, rotate or fly a lit object through perspective: its light is fixed at the top left. Objects rise from and sink into the surface, and selections slide.
- Don't repeat a two-tone headline pattern or add eyebrow labels above section headings.
- Don't add copy that restates a heading, narrates the page, or labels the obvious. If a line doesn't change a decision, cut it.
- Don't hand-roll a key or section; extend the component instead.
- Don't put every part of a showcase in one raised slab; separate its objects on the island and let the scroll tell the story.
- Don't put more than one line of text in a bento tile, or a graphic that isn't built from the app's parts.
- Don't animate anything that has no resting state in CSS, or ignore reduced motion.
- Don't publish app renders that contain personal profiles, device names, history or usage counts.

## Analytics consent

The optional analytics notice reuses the neutral panel and Button components.
Allow and Decline have equal visual weight. Keep it readable and scrollable on
small screens, with a link to the privacy page. It stays hidden without
JavaScript or when collection is disabled. Privacy uses the shared subpage
layout and lets visitors turn analytics off.

## App icon artwork

The website's `airdraft-icon.png` and `favicon.png` use the Carved Wave app icon,
generated by `scripts/render-app-icon.swift`: five darker recessed bars on a
neutral rounded-square tile, without an inner capsule or caret. Pure Wave and
Night Wave are selectable native Dock icons. All three share Carved Wave's
84-point bars, 30-point gaps, 480-point maximum height, height ratios and position
on a 1024-point canvas. Pure Wave and Carved Wave darken the bars; Night Wave
darkens the background. The site's sidebar-derived capsule
brand, Home-style hero waveform and installer wordmark retain their existing
geometry. Regenerate the Settings screenshots when its icon pickers change.
