---
name: Airdraft website
description: The app icon's silver body, pressed track and caret, built out into a page.
colors:
  surface: "#e6eaf1"
  surface-highlight: "#f1f4f9"
  surface-shade: "#dce1e9"
  panel-mid: "#e8ecf2"
  well-deep: "#d9dee7"
  well-shallow: "#e3e7ee"
  key-face: "#f5f7fa"
  key-face-shade: "#e2e7ee"
  key-face-hover: "#f9fafc"
  key-face-hover-shade: "#e6eaf0"
  result-card: "#f6f8fb"
  result-card-shade: "#eceff4"
  ink: "#263146"
  muted: "#505c73"
  quiet: "#5f6a80"
  accent: "#3b4bd0"
  key-blue: "#5462ef"
  key-blue-deep: "#4150da"
  key-blue-hover: "#5d6bf5"
  key-blue-hover-deep: "#4655e0"
  glow-violet: "#6b7aff"
  glow-cyan: "#3bc3f4"
  hud-top: "#2b303a"
  hud: "#1f232b"
  white: "#ffffff"
  scrollbar: "#b3bccb"
  wall-lit: "#e8ecf1"
  wall-shaded: "#8f9bb1"
typography:
  display:
    fontFamily: '"Manrope Variable", sans-serif'
    fontSize: "clamp(2.25rem, 1.2rem + 4.6vw, 4.5rem)"
    fontWeight: 650
    lineHeight: 1.04
    letterSpacing: "-0.035em"
  headline:
    fontFamily: '"Manrope Variable", sans-serif'
    fontSize: "clamp(2.125rem, 1.3rem + 2.6vw, 3.125rem)"
    fontWeight: 650
    lineHeight: 1.1
    letterSpacing: "-0.03em"
  entry-title:
    fontFamily: '"Manrope Variable", sans-serif'
    fontSize: "1.75rem"
    fontWeight: 650
    lineHeight: 1.25
    letterSpacing: "-0.02em"
  title:
    fontFamily: '"Manrope Variable", sans-serif'
    fontSize: "1.375rem"
    fontWeight: 650
    lineHeight: 1.25
    letterSpacing: "-0.02em"
  lead:
    fontFamily: '"Manrope Variable", sans-serif'
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.7
  body:
    fontFamily: '"Manrope Variable", sans-serif'
    fontSize: "0.9375rem"
    fontWeight: 400
    lineHeight: 1.65
  label:
    fontFamily: '"Manrope Variable", sans-serif'
    fontSize: "0.8125rem"
    fontWeight: 650
    lineHeight: 1.4
  action:
    fontFamily: '"Manrope Variable", sans-serif'
    fontSize: "0.9375rem"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.01em"
  keycap:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "0.9375rem"
    fontWeight: 500
    lineHeight: 1
rounded:
  panel: "20px"
  well: "14px"
  key: "12px"
  chip: "8px"
  keycap: "6px"
  mark: "2px"
  pill: "999px"
  stud: "50%"
spacing:
  gutter: "48px"
  gutter-tablet: "32px"
  gutter-mobile: "20px"
  section: "152px"
  section-tablet: "128px"
  section-mobile: "96px"
  panel: "28px"
  panel-mobile: "18px"
  well: "22px"
  source: "36px"
components:
  key-primary:
    backgroundColor: "{colors.key-blue}"
    textColor: "{colors.white}"
    typography: "{typography.action}"
    rounded: "{rounded.key}"
    padding: "0 24px"
    height: "52px"
  key-primary-hover:
    backgroundColor: "{colors.key-blue-hover}"
    textColor: "{colors.white}"
  key:
    backgroundColor: "{colors.key-face}"
    textColor: "{colors.ink}"
    typography: "{typography.action}"
    rounded: "{rounded.key}"
    padding: "0 20px"
    height: "48px"
  key-hover:
    backgroundColor: "{colors.key-face-hover}"
    textColor: "{colors.accent}"
  panel:
    backgroundColor: "{colors.panel-mid}"
    textColor: "{colors.ink}"
    rounded: "{rounded.panel}"
    padding: "{spacing.panel}"
  well:
    backgroundColor: "{colors.well-deep}"
    textColor: "{colors.ink}"
    rounded: "{rounded.well}"
    padding: "{spacing.well}"
  chip:
    backgroundColor: "{colors.well-deep}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.chip}"
    padding: "6px 10px"
  profile-selected:
    backgroundColor: "{colors.key-face}"
    textColor: "{colors.accent}"
    typography: "{typography.label}"
    rounded: "{rounded.chip}"
    padding: "0 14px"
    height: "34px"
  hud:
    backgroundColor: "{colors.hud}"
    textColor: "{colors.white}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "0 16px 0 14px"
    height: "40px"
---

# Design System: Airdraft website

## Overview

**Creative North Star: "The icon, built out into a page"**

Every surface on the site comes from the app icon rendered by
`scripts/render-app-icon.swift`: a silver body lit from the upper left, a raised
pill with a pressed track inside it, a waveform warming from gray to violet, and
a glowing caret where text lands. The page reuses those objects literally. Panels
are the body, wells are the track, keys are the pill, and the violet-to-cyan
gradient appears only where the icon uses it: the caret and waveform.

Depth carries meaning. What you said sits in a well; what Airdraft inserts is
pressed in while it waits and lifts out once it is typed. The one filled blue key
on each screen is the one action that matters. The HUD in the sample is a copy of
the app's own recording indicator, not an illustration.

This covers `apps/marketing`. Tokens live in `src/styles/global.css`; the sidecar
`.impeccable/design.json` carries shadows, motion, breakpoints and component
previews.

**Key Characteristics:**

- One light source, upper left, on every raised and recessed surface.
- Layered shadows: a top-edge highlight, a contact shadow, a key shadow and an ambient shadow. Never the symmetric twin-shadow recipe.
- Curved fills: raised surfaces are lighter at the top, wells darker at the top.
- A single filled blue key for the primary action; everything else is silver.
- Engraved grooves, never flat hairlines, to divide content.

## Colors

The palette is the icon's: cool silver, slate ink, and one violet-blue.

### Primary

- **Deep violet-blue** (#3b4bd0): links, selected profile, current page, focus rings. 5.2:1 on the deepest well, 6.1:1 on the highlight.
- **Key blue** (#5462ef → #4150da): the filled primary key, top to bottom. White label text.
- **Icon glow** (#6b7aff → #3bc3f4): the caret only. Never text, never a fill larger than a mark.

### Neutral

- **Icon silver** (#e6eaf1): the page. Panels fade from **highlight** (#f1f4f9) through **panel mid** (#e8ecf2) to **shade** (#dce1e9).
- **Well** (#d9dee7 → #e3e7ee): recessed surfaces, chips and the profile track.
- **Key face** (#f5f7fa → #e2e7ee): silver keys, keycaps, the selected profile and the changelog studs.
- **Result card** (#f6f8fb → #eceff4): the inserted text once it has lifted.
- **Slate ink** (#263146): headings and primary text. **Muted slate** (#505c73): supporting text, 4.7:1 or better on every surface. **Quiet slate** (#5f6a80): only the hero's facts line, at 4.5:1 on the page.
- **HUD** (#2b303a → #1f232b): the recording indicator, matching the app's dark capsule.
- **Walls** (#e8ecf1 lit → #8f9bb1 shaded): the hero object's sides, mixed by the direction each one faces.
- Shadows use the shade `rgb(112 126 156 / α)`; highlights use white at varying opacity.

## Typography

Manrope Variable, self-hosted. Seven sizes and nothing else:

| Step        | Size                                        | Use                                                        |
| ----------- | ------------------------------------------- | ---------------------------------------------------------- |
| display     | `clamp(2.25rem, 1.2rem + 4.6vw, 4.5rem)`    | Hero only                                                  |
| headline    | `clamp(2.125rem, 1.3rem + 2.6vw, 3.125rem)` | Section headings, changelog and 404 titles                 |
| entry-title | `1.75rem`                                   | Changelog entries                                          |
| title       | `1.375rem`                                  | Stage, panel and feature titles                            |
| lead        | `1.0625rem`                                 | Hero and section intros, sample text, disclosure summaries |
| body        | `0.9375rem`                                 | Paragraphs, actions                                        |
| label       | `0.8125rem`                                 | Field labels, chips, metadata. The floor: nothing smaller  |

Tracking is `-0.035em` for display, `-0.03em` for headlines, `-0.02em` for
titles. Headings balance; paragraphs use `text-wrap: pretty`. Headings are plain
statements without trailing full stops, except the hero line.

Keycaps use the system face, because Manrope has no ⌃ or ⌥ glyphs.

## Layout

Content width is `min(1120px, 100% - 2 × gutter)`. Sections come from the
`Section` component and the spacing tokens; `first` sections (page headers)
take `56px` of top padding instead of the section gap, and `narrow` sections
cap at `800px`. The sample is capped at `1040px`, the changelog at `960px`.

The homepage bento is a three-column grid with `20px` gaps and seven tiles in
a fixed rhythm: wide + narrow, three narrow, narrow + wide. The provider story
pins for about 4.9 viewport heights on screens at least `1000px` wide and
`700px` tall; everywhere else it stacks.

| Max width | Changes                                                                                                                                                                                               |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `1000px`  | Gutter `32px`, section `128px`; bento becomes two columns (wide tiles span both); pricing plans and homepage offers stack (max `560px`); the provider story stacks.                                   |
| `700px`   | Gutter `20px`, section `96px`; sample, bento, provider scenes, footer and changelog stack; the hero object scales to 66%; the price table folds the model under the provider; the HUD shows ten bars. |
| `560px`   | The header hides Changelog (it stays in the footer).                                                                                                                                                  |
| `420px`   | Hero and build keys go full width; the header wordmark is `24px` tall and nav gaps tighten to `14px`.                                                                                                 |

## Elevation & Depth

Exact values live in `:root` and the sidecar.

- `--lift-panel`: panels. A white top edge, a 1–2px contact shadow, a 14px key shadow and a 36px ambient shadow pulled in with negative spread, plus a tight white counter-light. The white never blooms outside the panel.
- `--lift-card`: the inserted-text card once lifted.
- `--lift-key`: silver keys, the selected profile, studs, and the strong vocabulary chip.
- `--press`: a key while pressed, together with a 1px downward move.
- `--sink`: wells. `--sink-chip`: chips and the profile track.
- `--groove`: an engraved line (shade over white) between disclosure rows, privacy rows, price-table rows, support items and the footer.

Elevation is declared once per element: a shadow, never a border plus a shadow.

## Shapes

Panels `20px`, wells `14px`, keys and the profile track `12px`, chips and
profile buttons `8px`, keycaps `6px`. The HUD is a full pill. Carets and
waveform bars use `2px`. Changelog studs are circles.

## Components

Reusable components live in `src/components/ui/`. Build new pages from them;
`/design/` (unlinked, `noindex`, excluded from the sitemap) shows each one in
every state.

### Hero object (`HeroPlateau.astro`, `ui/Capsule3D.astro`)

The hero is the app icon rebuilt as a solid, not a picture: real CSS 3D
geometry from `src/data/icon.ts`, which mirrors `scripts/render-app-icon.swift`.

- **Body.** A `300px` face; its walls are 44 real faces around the rounded
  outline (4 sides, 10 facets per corner), `480px` deep, fading to transparent
  along an eased gradient. Back faces are culled. Each wall's shade comes from
  `cos(facing + twist)`, so the side facing the upper-left light stays lit as
  the object turns.
- **Capsule** (`Capsule3D`). A raised ring whose groove is
  an actual opening, a floor with contact shading, and bars that stand up from
  the floor: each bar is a stack of slices whose height is `--lift`.
- **Pose.** Twisted 30° clockwise and tilted 54° away in a `1500px`
  perspective. `--tp`/`--xp` (pointer) and `--ts`/`--xs` (scroll) add to the
  twist and tilt, in unitless degrees.
- **Stage.** The hero stage is exactly one screen below the header (`100svh`, grows only if the group cannot fit) and centres the object and copy, so the next section is always below the fold. The object is `660px` tall (`560px` at 82% scale on desktop windows under `820px` tall), pulled up `94px` and overlapped `280px` by the hero copy, with a final
  mask from 72% down. It rises into place on load.

### Voice (`src/scripts/voice.ts`)

Every `[data-waveform]` listens to one shared "voice": pointer speed and scroll
speed raise it, it decays when still. Bars rise with it (the hero by up to
`22px`); the logo's waveform strokes stretch up to 90% with it (`--gain`)
while its caret stays still; the hero's bars also lean toward the pointer. The
loop runs only while the voice is audible and a waveform is on screen, and not
at all with reduced motion. Hovering the logo makes it speak.

### Brand (`ui/Brand.astro`)

The logo is the app's own outlined wordmark, read at build time from
`Sources/App/Assets.xcassets/SidebarWordmark.imageset/wordmark.svg` (generated
by `scripts/render-sidebar-wordmark.swift`): the capsule, waveform and caret as
round-capped strokes, then lowercase "airdraft" as outlined lettering. It is
drawn in `currentColor`, ink by default and accent on hover, `27px` tall in the
header (`24px` below `420px`) and `22px` in the footer. The component splits the
waveform path into one stroke per bar so the bars can move; the artwork itself
is never redrawn on the web. The link carries the accessible name.

### Button (`ui/Button.astro`)

The site's keys. Renders `<a>` with `href`, otherwise `<button>`.

| Prop                 | Values                                    | Notes                                                                                                       |
| -------------------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `variant`            | `primary`, `secondary` (default), `quiet` | One `primary` in view at a time. `quiet` is an inline text action.                                          |
| `size`               | `md` (48px), `lg` (52px)                  | `lg` for hero and closing actions.                                                                          |
| `icon`               | `none`, `right`, `down`, `external`       | Trailing arrow.                                                                                             |
| `iconOnly` + `label` |                                           | 44px square; `label` is the accessible name and tooltip. Put the SVG in `slot="icon"`.                      |
| `disabled`           |                                           | Renders a pressed-in, non-interactive `<span aria-disabled>`; use it for actions that aren't available yet. |

Hover lightens the fill; pressing moves the key down 1px and swaps its shadow
for `--press`. Focus shows the 2px accent ring.

### Section, Surface, Chips, Keys, Tag

- `Section`: `title`, optional one-line `intro`, `level` 1 or 2, `first`, `width="narrow"`. Owns the heading id and spacing.
- `Surface`: `variant="panel"` (raised) or `"well"` (recessed), any element via `as`. Never nest a panel in a panel.
- `Chips`: recessed, non-interactive names in ink. `.chip-muted` and `.chip-strong` show a before → after pair.
- `Keys`: keycaps in the system face; `size="lg"` for feature tiles.
- `.tag`: a small recessed label.

### Hud (`ui/Hud.astro`) and the dictation sample

`Hud` is the app's recording pill: white bars and a timer or state. Pass
`levels` for a still frame. The sample animates it.

The sample pairs a recessed "What you said" well with a "What Airdraft
inserts" card, above Run sample, the HUD and a status line that speaks only
while running. It plays once when mostly on screen: words light up, the HUD
counts, then shows Decoding and Refining, fillers are struck one at a time, and
the result card lifts as the text is typed with the icon's caret. Profile
buttons re-run only the refinement; Stop jumps to the result. Without
JavaScript the Clean result shows; reduced motion shows it immediately and
never autoplays. It has no visible heading or badge; its accessible name is
"Sample dictation", and its field labels ("What you said", "What Airdraft
inserts") carry it.

### Bento (`ui/BentoTile.astro`)

Every tile has the same anatomy and nothing else: a recessed well `232px` tall
(`210px` on phones) holding one large graphic, a title at the title step, and
one line of body text. Tiles are the same panel with the same padding; only the
span differs (`wide` spans two columns). The graphics are built from the
system's own parts, never icons: a text field and HUD, big keycaps, the profile
picker, a vocabulary correction, a history card deck, the refinement fallback,
and a "This Mac" boundary. Each plays a short loop while on screen
(`data-art`); without JavaScript they show their final frame.

### Provider story (`PipelineStory.astro`)

"You choose where each step runs" as six scenes: speech on this Mac, speech in
the cloud, refinement on this Mac, in the cloud, on your subscription, then
insertion at the cursor. Each scene is an eyebrow (the step), a short title and
one line on what leaves the Mac, beside one card. A card holds a single choice:
provider names only, no model details, on a picker wheel with a recessed
selection band; the last card shows a vocabulary fix in a text field.

On desktop the section pins and the cards are solid slabs (six stacked edge
layers) flying through 3D space. One variable, `--t` on the deck, drives
everything: each card's distance `--q` from the current scene sets its place
on a diagonal, its tilt, and its fog. The steps ahead queue toward the upper
right and sink into the page colour; the current card hops forward, its wheel
turns through the names as the visitor scrolls; a finished card flies past to
the lower left. A three-part stepper (Speech, Refinement, Insertion) fills as
the scenes pass, and the pointer tilts the whole deck. Elsewhere, and with
reduced motion, copy and card pairs stack with plain lists; on phones the cards
tip up into place.

### Get Airdraft (`GetAirdraft.astro`)

The homepage close: three offers side by side. Build it yourself (Free, build
instructions), the ready-to-run app in the middle (raised, the page's one
primary key, "See pricing" until `paidPlan` is set), and Support the project
(donation, disabled until configured). Prices are set at the display step.

### Motion (`src/scripts/story.ts`, GSAP + ScrollTrigger)

One `gsap.matchMedia` context, off entirely with reduced motion:

- Hero: the object tilts toward the pointer (quickTo, 1s), and over the first
  `900px` of scroll orbits (+22° twist, +14° tilt), sinks `220px` and shrinks to
  88% while the copy rises `50px`: parallax.
- Section headings, the sample and bento tiles rise `36–48px` and fade in as
  they enter; the offers tip up from `-16°`.
- Bento loops play only while their tile is visible.
- The provider story pins on desktop and flies its cards (see above).

Resting CSS is always the final state, so nothing depends on the script to be
readable.

### Disclosure (`ui/Disclosure.astro`)

Native `details`/`summary` rows inside a well, divided by grooves. Used for
pricing questions and support troubleshooting. Answers may include `code`.

### Pricing and support pages

Pricing shows three plans: Open source (`$0`, the one primary key), Supporter
(donation; disabled until a URL exists), and the paid plan from
`src/data/site.ts` (a well reading "Not announced" until it is set). A well
table lists cloud speech list prices from `src/data/pricing.ts`, dated.
Support is troubleshooting disclosures, an issue link, then ways to fund the
project; donation stays disabled until configured.

### Header, footer, changelog

The header starts with the Brand logo, then Pricing, Support, Changelog, the
GitHub icon key and a primary "Get Airdraft" key to the pricing page. On phones
only the logo, GitHub and Get Airdraft remain. The footer lists GitHub, build instructions, pricing,
support, changelog, privacy and an optional license above a groove. The
changelog runs a pressed groove down the date column with a raised stud per
entry; Unreleased is an accent chip.

## Do's and Don'ts

### Do:

- Do take new colors, light and shapes from the icon renderer.
- Do keep exactly one filled blue key in view at a time.
- Do use the seven type steps and the `0.8125rem` floor.
- Do keep sample, pricing, license and download claims factual. Hide anything unconfirmed.

### Don't:

- Don't use the symmetric `9px 9px 24px` twin-shadow recipe, or a 1px border under a soft shadow.
- Don't color non-interactive text blue.
- Don't divide content with flat hairlines; use the groove or space.
- Don't repeat a two-tone headline pattern or add eyebrow labels above headings.
- Don't add copy that restates a heading, narrates the page, or labels the obvious. If a line doesn't change a decision, cut it.
- Don't hand-roll a key or section; extend the component instead.
- Don't put more than one line of text in a bento tile, or a graphic that isn't built from the system's parts.
- Don't animate anything that has no resting state in CSS, or ignore reduced motion.
- Don't publish app renders that contain personal profiles, device names or usage counts.
