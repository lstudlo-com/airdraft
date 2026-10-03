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
| entry-title | `1.625rem`                                | Subpage sections, changelog entries, scene titles           |
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

Content width inside the island is `min(1120px, 100% - 2 × gutter)`, the same
as the header, so content lines up with the mark. Sections come from the
`Section` component and the spacing tokens; `first` sections take `56px` of top
padding instead of the section gap. The sample is capped at `1040px`.

Subpages (Pricing, Support, Changelog) are `main.island.subpage` and open with
the same title block: `Section level={1} first` with a one-line intro, the
headline step for the title (`.page-title`), and the full content width; no
subpage narrows its content. Their later sections are `104px` apart with
`entry-title` headings, a step below the page title.

The homepage bento is a three-column grid with `24px` gaps and seven tiles in
a fixed rhythm: wide + narrow, three narrow, narrow + wide. The provider story
pins for about 4.9 viewport heights on screens at least `1000px` wide and
`700px` tall; everywhere else it stacks.

| Max width | Changes                                                                                                                                                                                                         |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `1000px`  | Gutter `32px`, section `120px`; bento becomes two columns (wide tiles span both); pricing plans and homepage offers stack (max `560px`); the provider story stacks; the hero waveform drops its 12 oldest bars. |
| `700px`   | Gutter `20px`, section `96px`, island inset `6px`; sample, bento, provider scenes, footer and changelog stack; the hero waveform shows 15 bars; the HUD shows ten bars.                                         |
| `560px`   | The header shows only the mark, GitHub and Get Airdraft.                                                                                                                                                        |
| `420px`   | Hero and offer keys go full width; the hero waveform shows 12 bars.                                                                                                                                             |

## Elevation & Depth

Exact values live in `:root`. They translate `SurfaceShadows` (SwiftUI radius
r ≈ CSS blur 2r).

- `--raise-hero`: `7px 9px 24px` shade, `-6px -7px 24px` light. The hero card and the featured offer.
- `--raise-card`: half the spread. Panels, bento tiles, pricing plans, scene cards.
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
is the chrome it sits on, lifted only by a soft shade down-right and light
up-left (light: black 20% and white 95%; dark: black 55% and white 9%; radius
2.6 at 28px). Outer box-shadows never paint inside the box, which matches the
app's `excludesInterior`. Never give it an edge stroke or fill. Five waveform
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

### Provider story (`PipelineStory.astro`)

"You choose where each step runs" as six scenes: speech on this Mac, speech in
the cloud, refinement on this Mac, in the cloud, on your subscription, then
insertion at the cursor. Each scene is an eyebrow (the step), a short title and
one line on what leaves the Mac, beside one raised card. The card's symbol sits
in a recessed socket, and it holds a single choice laid out like the app's
settings tables: provider rows divided by grooves, the chosen row resting in the
sidebar's recessed selection well (12px corners, 2.5px depth) with a raised
check island inside it. The last card shows a vocabulary fix in a raised field.

On desktop the section pins and one raised card (hero spread) stays in place;
nothing tilts or flies. Scenes cross-fade inside it: the next rises `12px` into
place as the last one sinks away. While a scene holds, scrolling steps the
selection well row by row through its providers on `SelectionMotion.curve`, and
the check island follows 300ms later, as the sidebar's icon island follows its
well. A three-part stepper (Speech, Refinement, Insertion) fills like Home's
usage tracks: a raised gray fill in a shallow inset. Elsewhere, and with reduced
motion, copy and cards stack with the first provider selected; on phones the
cards rise into place.

### Get Airdraft (`GetAirdraft.astro`) and the license card (`LicenseCard.astro`)

The homepage close: two offers side by side. Build it yourself (Free, build
instructions) and the ready-to-run app's license card, raised with the hero
spread and holding the page's one primary key ("See pricing").

The license card is shared with the pricing page. Its title sits beside a
segmented **1 Mac | 3 Macs** choice; below it, only the chosen license's price
("one-time") and use show, and switching slides the new line up into place.
Both licenses have the same features, so one card shows them once. The choice
is a native radio group and CSS `:has()` picks the visible lines, so it works
without JavaScript; `segmented.ts` adds the sliding thumb. On the pricing page
it lists `licenseIncludes` and its action is the purchase: disabled "Not on
sale yet" until `siteLinks.checkout` is set, then the page's primary key.
Prices, Mac counts and inclusions come from `src/data/site.ts`. Every plan's
title row is the choice's height (`38px`), so side-by-side prices line up.

### Motion (`src/scripts/story.ts`, GSAP + ScrollTrigger)

One `gsap.matchMedia` context, off entirely with reduced motion:

- Section headings, the sample, bento tiles and the offers rise `36–48px` and fade in as they enter. Cards rise flat: they never tip through perspective.
- Bento loops play only while their tile is visible.
- The provider story pins on desktop; its selection well steps through the providers (see above).

The hero card rises once on load (CSS) and its bars grow; it never tilts,
because its light is fixed at the top left. Resting CSS is always the final
state, so nothing depends on the script to be readable. Interaction motion
outside GSAP: the hero's dictation (`dictate.ts`), hover magnification
(`waveform.ts`), the segmented thumb (`segmented.ts`), keycaps that follow the
keyboard (`keys.ts`), the license swap and disclosures (CSS).

### Disclosure (`ui/Disclosure.astro`)

Native `details`/`summary` rows inside a raised panel, divided by grooves. The
plus sits in a small raised round button and turns 45° when open, and the answer
eases open and closed (`::details-content` with `interpolate-size`; browsers
without it toggle at once). Used for pricing questions and support
troubleshooting. Answers may include `code`.

### Header, footer, pricing, support, changelog

The header sits on the chrome and stays at the top as the page scrolls: the
Brand mark, then Pricing, Support and Changelog as capsule links (the current
page sits in a recessed well, like the app's sidebar selection), the GitHub
icon key and the primary "Get Airdraft" key. On phones only the mark, GitHub
and Get Airdraft remain. Behind it is the app's progressive header blur
(`ProgressiveHeaderBlur.swift`): six stacked `backdrop-filter` layers (1 to
32px), each masked to the band where the app's radius ramp reaches it, so
content is lightly blurred at the header's bottom edge (plus a 4px feather)
and fully blurred at the top, while labels and controls stay sharp. Never
simulate it with a tint or an opacity fade; only Reduce Transparency gets an
opaque chrome header. Anchors land below it (`scroll-padding-top`). The footer
sits on the chrome below the island.

Pricing shows two plans: Open source (`$0`, build instructions, the page's
primary key until checkout opens) and the license card. A note gives the
currency and tax basis, a raised panel lists cloud speech list prices from
`src/data/pricing.ts`, dated, then the questions.
Support is troubleshooting disclosures, an issue link, then ways to fund the
project. The changelog runs a pressed groove down the date column with a raised
stud per entry; Unreleased is a recessed chip.

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
