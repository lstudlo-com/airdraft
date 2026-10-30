# Airdraft

Personal macOS menu-bar dictation app: speech ▸ LLM refinement ▸ insert at cursor.
Not a Printage company repository; the workspace `dev-guidelines` skill does not apply here.

External contributors: start with `CONTRIBUTING.md` and `docs/development.md`.
This file is the complete engineering contract for the maintainer and coding
agents; its Maintainer environment section applies only to the maintainer's Mac.

## Product goals

`docs/PRODUCT.md` lists the goals the mature app must meet (quality UI, independent
local/remote engines, preset-driven setup, editable and resettable refinement
profiles). Read it before touching UI, settings, or prompt handling, and keep its
status table current. That table records implemented behavior only; release and
verification status belong in the vault (see Maintainer environment).

## Maintainer environment

This section describes the maintainer's Mac, knowledge base and checkout
workflow. Coding agents working for the maintainer follow it; external
contributors can skip it (see `CONTRIBUTING.md`).

### Knowledge vault and project files

- The canonical market research and product knowledge base is the iCloud Obsidian
  vault at `/Users/lightiichen/Library/Mobile Documents/iCloud~md~obsidian/Documents/Airdraft/`.
  Start at `Home.md`. The vault's `Knowledge Architecture.md` is the complete
  specification for its folders, frontmatter, file names, language and write method.
  `Research/` owns external evidence, `Strategy/` positioning and business decisions,
  and `Product/` readable product knowledge; these describe the current state and are
  rewritten in place, never extended with dated update paragraphs. `Work/` tracks
  issues and tasks. `Records/` only gains dated releases, decisions, studies,
  verification and evidence. Put new research and product analysis there, not in
  Project Files or new repository reports. Record source dates and commits,
  distinguish implemented/tested/released/verified, and retain explicit corrections.
- The repository is authoritative for implementation contracts: code, tests, build
  and release commands, this file and `docs/*.md`. When a vault topic disagrees,
  fix the vault. The vault is authoritative for work status, release and verification
  history, research and strategy; repository docs do not track release or acceptance
  status.
- Update the vault in the same task that causes the change:
  - User-visible behavior, UI rules, limits or build/release contracts change:
    rewrite the affected `Product/` topic and its `verified_on`/`source_commit`.
    Refactors, tests and tooling without a behavior change need no vault update.
  - A user-reported problem, work spanning commits or sessions, a release with
    verification gaps, or committed but unstarted work: create or update a `Work/`
    item. `type: issue` means behavior differs from the specification,
    documentation or clear intent, such as bugs and regressions; `type: task` covers
    features, adjustments, verification and migrations. Items share one `AD-###`
    sequence (next number = highest existing + 1).
  - Commits that advance an item end with a `Refs: AD-###` trailer; append a row to
    the item's log instead of editing earlier rows.
  - A release adds its `Records/Releases/` note and marks included items `released`;
    the push-and-release skill does this.
  - A user decision rewrites the `Strategy/` or `Product/` topic and adds a
    `Records/Decisions/` note. Research rewrites `Research/` and adds a
    `Records/Studies/` snapshot. A wrong vault claim is fixed in its topic with a
    correction record.
- Re-read a vault note immediately before editing it: other sessions and iCloud write
  concurrently. Never move or rename vault files with a bare `mv`; update every link
  in the same change (`obsidian move` waits on a dialog while automatic link updates
  are off). After any vault write, `python3 scripts/check-vault.py` must report 0
  errors. Changing the vault rules updates `Knowledge Architecture.md`, both guidance
  files and `scripts/vault_check.py` together.
- `/Users/lightiichen/Desktop/Project Files/Production Projects/Airdraft/` stores
  miscellaneous files and resources related to Airdraft.
- `/Users/lightiichen/Desktop/Project Files/Production Projects/Airdraft/competitor_analysis/repos/`
  stores cloned repositories of competing products for reference and analysis.
  Handy lives in `Handy/` from `https://github.com/cjpais/Handy`; VoiceInk lives in
  `VoiceInk/` from `https://github.com/Beingpax/VoiceInk`.

### Checkouts and branches

The main folder (this repository root) is where the user builds in Xcode and
where releases are made. Keep it on `main`; it is the only checkout of `main`.

- Start every session with `python3 scripts/check-checkout.py`. When it warns,
  stop and tell the user; never build, render or verify from a stale checkout.
  Debug builds run the same check as an Xcode build phase.
- Several sessions, worktrees and subagents work in parallel. Every
  implementation, fix, refactor, documentation or website change, every merge
  of another branch, every spawn of file-editing agents or sessions, and every
  push, release or deploy follows `.agents/skills/parallel-work/SKILL.md`: before
  starting, run `python3 scripts/parallel_work.py status --fetch --paths <paths>`
  and read the area's open Work items and recent Decisions; integrate finished
  but unmerged work that touches your paths first, never edit the same section
  another worktree has uncommitted, and land structural moves as a small commit
  merged first. Claim your task's branch and paths with `parallel_work.py claim`.
  Finished means merged: validated work is merged to main in the same task (or
  reported first as unmerged with the decision asked for). Before a push,
  release or website deploy, `parallel_work.py status --fetch --release` must
  show no unmerged, unparked branch; park long-lived `wip/` branches explicitly.
  Workspace cleanup is routine: run `parallel_work.py cleanup --fetch --apply`
  at the start of every task and `cleanup --fetch --apply --remote` after each
  push. It removes only worktrees and branches already merged into main with
  nothing uncommitted, no claim and no activity for two hours (moving their
  `dist/` evidence to the main folder first), drops dead claims, deletes merged
  origin branches, and lists everything it keeps.
- Do features and fixes in a separate worktree on a branch (`claude/<topic>`,
  `codex/<topic>`) created from the latest `origin/main`. Only a single small
  commit may go directly on `main` in the main folder, with no other session active.
- In a new worktree, clone the main folder's `Packages/SherpaOnnxKit/Vendor` with
  `cp -cR` and run `python3 scripts/generate-project.py` (see Structure).
- When validated, rebase onto `origin/main`, fast-forward `main` in the main
  folder, then remove the worktree and its branch.
- Never leave unfinished work in the main folder. Commit it to a `wip/<topic>`
  branch in a worktree and keep the main folder on `main`.
- `dist/` is ignored and is deleted with its worktree. Before removing one, move
  its `dist/validation/` and `dist/releases/` evidence into the main folder's
  `dist/` without overwriting, and update vault notes that cite the old path.

### Release Mac

Run `moon run airdraft:release-setup` once per release Mac. The installed pre-push
hook builds committed sources locally for every origin/main push that can change
the app. A push whose changes since the latest published release are only the
website (`apps/marketing/`), Markdown guidance (root `*.md`, `docs/`) and
`pnpm-lock.yaml` changes that leave its root importer (moon) unchanged skips the
app release, and the publish workflow skips with it; deploy the website on its own.
`AIRDRAFT_RELEASE_FORCE=1` releases anyway. The GitHub workflow publishes the
verified draft after the push succeeds. See `docs/updates.md`
and Local releases below.

## Structure

- Moon is a small task runner around the existing Xcode layout. `.prototools` pins
  moon; `.moon/workspace.yml` maps one `airdraft` project; `moon.yml` defines
  `prepare` (once after clone), `generate`, `build`, and `test`. Use
  `moon run airdraft:build` / `moon run airdraft:test` for routine validation.
  Keep Xcode tasks uncached in moon and serialized by the shared mutex.
  `pnpm build:app` resolves the pinned local Moon binary; `pnpm test:local` runs
  the credential-free regression allowlist through the same Xcode mutex. Project
  generation uses installed XcodeGen or an existing `dist/tools/xcodegen` binary,
  and fails with an installation hint when neither exists. The root `Package.resolved`
  is the canonical reviewed SwiftPM graph; every generation route restores it into
  the generated project. Xcode builds use `-onlyUsePackageVersionsFromResolvedFile`;
  release builds compare the final pins with that committed graph.
- Third-party notices are generated: `scripts/acknowledgements.py generate` writes
  `Sources/App/Resources/Acknowledgements.txt` and `Sparkle-LICENSE.txt` from
  resolved SwiftPM checkouts, binary targets, native inputs and brand assets, using
  the reviewed `ThirdParty/acknowledgements.json` and the pinned texts in
  `ThirdParty/licenses/`. Never hand-edit the output. After changing
  `Package.resolved`, a package manifest, native inputs or a `ModelBrand` image set,
  build once, regenerate, and run `python3 -B scripts/test-acknowledgements.py`.
  Unreviewed dependencies, license files or texts fail; CI and release preparation
  reject stale notices. Settings > Updates > Acknowledgements opens the bundled file.
  `python3 scripts/generate-project.py --install-xcodegen` is the explicit,
  checksum-verified XcodeGen download for fresh clones; normal generation never
  downloads.
- `project.yml` is the source of truth for the Xcode project. After changing it run
  `python3 scripts/generate-project.py` (bare `xcodegen` drifts the SwiftPM pins).
  `airdraft.xcodeproj` is generated and git-ignored. Release preparation and CI
  accept only the pinned XcodeGen 2.46.0: a copy on PATH counts only when its
  extracted tree and version match the pin, otherwise the checksum-verified archive
  is downloaded into `dist/tools`, and a non-pinned `dist/tools/xcodegen` is
  refused. Normal generation still accepts any installed copy.
- `Packages/AirdraftCore` holds all engine-agnostic logic and most tests.
  `Tests/AirdraftAppTests` holds logic tests for App-only code: the bundle compiles
  `Sources/App` itself instead of using the app as a test host, so tests never launch
  Airdraft. Build containers through `IsolatedContainer` (temporary settings file and
  data directory, injected permissions, a dictation boundary that refuses to record);
  never read real preferences, history, Keychain or the microphone. Run the tests
  (see Validation) before finishing a change in either place.
- `Sources/App` is the SwiftUI shell: `App/` (entry point, `AppContainer`, `ModelLifecycle`),
  `Hotkeys/`, `HUD/`, `Views/` (one file per page, shared components in `Theme.swift`),
  `Debug/` (offscreen renders, self-tests).
- `apps/marketing` is the Astro marketing website, initialized from Cloudflare's
  official Astro Framework Starter and deployed with Workers static assets. Its
  Worker (`worker/index.ts`) runs only for requests that match no asset and serves
  their 404 as `no-store`, so a hashed file requested before a deploy reached it is
  never cached as missing under the immutable `/_astro/*` rule.
  Read its `PRODUCT.md` and `DESIGN.md` before changing content or design, and
  build pages from its reusable components in `src/components/ui/`. The site ships
  the app's interface languages: English at the root, translations under
  `/<code>/` with the English slug (zh-tw, zh-cn, es, ja). `src/i18n/locales.json` (code, BCP 47 tag, Open Graph locale, own name,
  direction, translated paths) drives hreflang, sitemap alternates, the language
  menu, the analytics path allowlist and `check-search.py`; add a translated page
  there together with its page file, `_redirects` aliases and `llms.txt`. Every page
  exists in every language: homepage and pricing copy lives in `src/i18n/messages`,
  every other page in `src/locales/<code>/` (page copy in `pages.ts`, Support,
  Privacy and guide bodies as Astro files, release notes in `changelog.ts`, each
  language with its own changelog feed). Translated pages quote the app's catalog
  labels for that language. `href()` refuses a missing translation, so nothing
  links to English or carries an "(English)" mark. The language menu (header globe
  key) is as wide as its names; the footer has no language row. The homepage's
  Settings window is rendered in every language. No right-to-left language ships yet; styles use logical properties so one can (keep
  the top-left light and app pictures, the waveform, the HUD and key caps left to
  right). The homepage's guide picker
  (`GuideLinks`/`GuideGlyph`) shows one app-part graphic and one short label per
  guide, labels in `guideLinks.labels` of every language's messages file. Guide and
  text-page sections are `GuideSection`: a numbered heading on the island at the top
  left over an unframed body whose material follows its content (never a heading
  inside a raised card), and guide titles have no intro line. Homepage section titles
  are centered (`main.home`) and have no intro line; subpages keep their titles and
  intros at the leading edge. The header keys sit one 10 px step apart through the
  `.header-actions` gap, never margins. Bento tiles play on arrival, repeat twice
  while on screen, then rest, and hold after a touch (`bento.ts` sets up
  `.bento:not(.specimens)`); the visitor's ⌃⌥ drives a demo only while the
  pointer or focus is on it, never from VoiceOver commands elsewhere. The
  homepage runs hero, sample, features, Transcribe, provider board, interface,
  Setup guides, Questions, Get Airdraft; the hero states what Airdraft is in one
  `home.lede` sentence. Until `siteLinks.checkout` is set, the hero's key leads to
  `#get-airdraft`, the source build holds the primary key there and on Pricing,
  and `NotifyRow` offers GitHub releases and the changelog feed; the hero has no
  availability line, its facts line is a dimmed small label, and its waveform card
  is only the well with equal insets (the pretend dictation's pill floats under
  it); the dictation
  sample after the hero (`DictationPreview`, `preview.ts`), titled "Hold, speak,
  let go", is the one telling of how dictation works: its three steps stand over
  separate objects in three shared columns (the well, the pill on its groove, the
  card), each control on the object it acts on (the Run key in the well, the
  profile picker in the card) and light as it plays. Every showcase is a scene of
  separate objects on the island, never one raised slab, and its story is told by
  the scroll (reversible). On the homepage a title always arrives before its content,
  which follows from further down at a different speed, a quarter further from the
  title than on subpages. The bento, Transcribe and the provider board use `Section
  sticky` (the interface and everything after it scroll normally): the title holds
  48 px below the site header (40 px on phones) and, only while held (`.is-held`), over a
  continuation of the header's progressive blur that eases out across the title
  band (its veil but not its heavier tint; the heading never animates its own
  opacity, which would make the band opaque), so content stays visible, blurred,
  while it scrolls under the title, and `sticky.ts` makes items arrive one at a
  time as the title settles. A held title stays while its content plays and
  leaves as the visitor leaves its section (Section `titleMotion`, from
  `sticky.ts`'s `--leave`: the next section's title coming up into the window),
  opening and blurring, never as soon as the content starts to move; the bento's
  names each tile in turn first (`cycle.ts`, an `aria-hidden` copy over the real
  heading, decoding through its own characters). The bento scrolls at half speed
  (Section `slow`, `sticky.ts`): eased down once its first tile rises and back to
  full speed before the next section, by moving into a space added after it,
  never by changing the visitor's scroll; Transcribe's stage and the provider cards pin under the
  title where they fit and play their story over a runway, otherwise each plays as
  it passes; the provider cards never scale. Transcribe's turns are rows in one
  transcript card, staggered like a conversation (the first speaker's chip and time
  at the leading edge, the second speaker's at the trailing edge); its export beat
  is as tall as the transcript, its slots filling down to the guide link on the
  card's bottom line. Pricing plans are
  separate cards and text pages frame no section in a well; headings rise word by
  word and subpage content rises block by block (`flourish.ts`); nothing in the
  hero drifts with the pointer. Where WebGL2 is available three.js draws the hero's
  waveform card (`hero3d.ts`, `hero3d-scene.ts`) as one folded metal ribbon (the
  app's Silk style), pointed at both ends with no caret object, lit from the top
  left; near the pointer it opens, ripples and catches a small light, and as the
  hero scrolls away it comes apart into a three-strand sound wave of grains
  (reversible). It loads after load and idle on the homepages only, never with
  Save-Data, and the HTML card keeps its box and stays the pointer target and the
  fallback. A fine silver thread (`thread.ts`) carries on from the ribbon's end
  beside the content, 48 px out from its edge, crosses sides only inside the
  space between two tall sections (never over a title or card) and ends as a
  bead over Get Airdraft's title, drawn by the scroll, only where the margins are
  at least 64 px wide. Scroll-driven animations need `cssMinify: "esbuild"`: Lightning
  CSS folds `animation-timeline` into the `animation` shorthand, which Chrome drops,
  and `check-search.py` rejects such a build. Reduce Motion and no-JS keep resting
  frames. The one accent,
  `--accent` (the app's system blue), marks progress only (the sample's current step and tracks, the Transcribe playhead and beat number, the provider channels). JavaScript packages
  use the root pnpm workspace and lockfile; do not add nested repositories or lockfiles.
  `pnpm dev:marketing`, `pnpm check:marketing`, `pnpm build:marketing`, and
  `pnpm preview:marketing` run its independent Moon tasks. Website-only changes
  require those checks and desktop/mobile browser verification, not Xcode tests.
  Keep the hero waveform card 84px below its facts line, or 60px at viewport
  widths of 700px or less.
  The homepage's interface section shows the real Settings window; regenerate
  `public/app/` with `apps/marketing/scripts/render-app-window.sh` from a Debug
  build of the current release (isolated empty data, grayscale) when that page,
  the sidebar or materials change; it renders English (`configuration-*`) for the
  English pages and zh-Hant (`configuration-zh-tw-*`) for `/zh-tw/`.
  Capture at 784 by 1000 points so the recording choices, Disco and timer row
  fit; keep the website frame dimensions and bottom-anchored callouts aligned,
  with per-language callout positions where the layouts differ.
  Keep the generated WebP origin sidecars with those screenshots. At 700px or
  less, and with reduced motion, the light/dark divider rests at half.
  Keep the changelog current with published app releases: one entry per product
  version, dated from GitHub publication in Asia/Taipei, with a release/source link.
  Group rebuilds under their version and verify changes against the tagged sources.
  The page and each feature release use a title followed by described change items,
  without a title summary; a release's title sits above its card, and patch releases
  show no visible title and stay recessed wells, even when latest. Preserve the version navigator, reduced-motion behavior and
  readable content without JavaScript.
  Search contracts live in `apps/marketing/SEARCH.md`. Mixed-language accuracy
  statements come only from `eval/mixed-asr` through
  `apps/marketing/src/data/mixed-asr.ts`, quoted as Airdraft's dated own measurement
  with its method link and limits; update both when the measurement is re-run.
  English, Japanese and Korean accuracy statements come only from `eval/eja-asr`
  through `apps/marketing/src/data/eja-asr.ts` (model output, shown in the offline
  setup guide), quoted the same way; update both when the measurement is re-run.
  Website guides that describe insertion or model recommendations describe the
  current release and name a version only where older behaviour differed; when
  `selfDrawingEditorBundlePrefixes` or the onboarding recommendation changes, update
  the coding-agent and mixed-language guides in the same release. Keep factual guide content,
  metadata and structured data aligned; never invent sale availability, reviews or
  ranking claims. The app comparison guide cites each product's own pages with
  check dates, states where competitors are better and marks unknown cells Not
  checked; recheck rows before changing their dates. Marketing builds validate generated crawlability, canonical URLs,
  sitemap membership, links, feeds and social previews, and title (60) and
  description (160) widths, CJK counting double. Keep `_redirects` aligned
  with canonical HTML routes. IndexNow defaults to a dry run; submission is a
  separate explicit command after publication, never a build side effect.
  Website analytics follow `apps/marketing/ANALYTICS.md`: consent before SDK
  loading, explicit production configuration, anonymous event allowlists (including slug-only `guide_clicked`), no
  native dictation data or replay, and privacy-page revocation. Keep event names,
  dashboard definitions and consent/data-filter regressions aligned. Website
  clicks measure intent, not installs or revenue.

- The app icon is code: edit `scripts/render-app-icon.swift` and run it from the
  repo root. It generates waveform-only Pure Wave, Carved Wave and Night Wave
  images, the bundled Carved Wave `AppIcon.appiconset`, and the website PNG/favicon.
  Do not hand-edit generated PNGs. Keep the outer rounded-square tile, five-bar
  rhythm and neutral grays; the app icons have no inner capsule or caret.
  Share Carved Wave's geometry across all three: 84-point bars, 30-point gaps,
  480-point maximum height, the same five height ratios and a -3-point horizontal
  offset on the 1024-point canvas. Only materials differ: darker raised Pure Wave
  bars, darker Carved Wave grooves, and bright Night Wave bars on a darker tile.
  Settings > Appearance stores independent light/dark icon choices, defaulting
  to Carved Wave and Night Wave. All three artworks are available for either theme.
  Follow the app's effective appearance, including system changes in Auto, and apply
  saved choices at launch through `NSApplication.applicationIconImage`. This changes
  the running Dock icon; never modify the signed bundle or Finder metadata at runtime.
  Finder uses the bundled Carved Wave icon. Generate exploratory variants only in
  scratch directories. After icon changes, run
  `uv run apps/marketing/scripts/render-brand.py` for the separate capsule wordmarks.
  The sidebar, Home waveform and website brand keep their capsule and caret.
  The website's tokens in `apps/marketing/src/styles/global.css` translate `Theme`,
  `SoftControls`, `NeumorphicSurface` and `HomeHero` values for light and dark; when
  those change, update the website and its `DESIGN.md` in the same change.

- Native sidebar branding is `SidebarBrandMark` in `MainWindow.swift`: a compact
  28-point-high raised neumorphic capsule with five waveform bars and a separate
  caret carved into it, without visible lettering. Keep the waveform height
  pattern. The capsule face is the sidebar itself, unfilled, lifted only by soft,
  wide `SurfaceShadows` (highlight up-left, shade down-right, excluded from the
  face). Never give it an edge stroke or a tight highlight that reads as an
  outline. The bars and caret are opaque grooves with a darker floor, inner shade
  at the top-left edge and inner light at the bottom-right; never raise them.
  Increase Contrast adds explicit edges.
  Scale the original compact mark uniformly by 1.4: about 57 by 28 points
  in a 30-point row. Retain its leading alignment, outer spacing and the
  accessible name Airdraft.
  It is a static image, not a button or a live meter.
  The expanded sidebar is 180 points wide.
  Collapsing the sidebar keeps an icon rail. Derive its width from the unchanged
  brand width plus equal 20-point side insets. Center destination, microphone
  and available account icons horizontally while preserving their expanded
  vertical positions and row heights. Hide text, retain tooltips and accessible
  names, and keep the sidebar toggle available to expand it again. In both sidebar
  states, place the toggle outside the sidebar in the page island's heading row, with
  its symbol aligned to the page leading inset and its center on the heading row;
  it never moves into the titlebar. Always inset the page heading beside the toggle
  so their hit areas stay separate.
  The website uses this mark too, without lettering: `apps/marketing/src/components/ui/Brand.astro`
  translates `SidebarBrandMark` value for value (34 px header, 28 px footer); change
  both together. The outlined `SidebarWordmark.imageset` SVG remains the installer
  wordmark. Regenerate that asset with `swift scripts/render-sidebar-wordmark.swift`;
  keep its capsule strokes and lowercase lettering paths intact.

## Rules

- The window chrome uses `SidebarBackground` across the whole window, behind the
  sidebar and around the page island: one fully opaque color,
  `Theme.chromeBackground`, white level 0.95 in light mode and 0.21 in dark mode.
  The sidebar has no translucency or desktop blur: `WindowChromeView` keeps the
  window opaque with the same background color. Do not reintroduce
  `NSVisualEffectView` behind the sidebar.
- Pages render on one rounded content island through `.contentIsland()`,
  including onboarding. It is inset by `Theme.islandInset` (the sidebar's 10-point
  content inset) from the top, trailing and bottom window edges; the sidebar's
  own inset is its leading gutter. Use `Theme.islandRadius` (12-point continuous
  corners) and `Theme.islandBackground`: 0.90 white in light mode and 0.15 in
  dark mode. In both appearances the island must stay darker than the chrome and
  at the Home hero's surface gray (light hero 0.91–0.89 around it; dark hero
  0.19–0.17 just above it) so neumorphic elements rise from it. Keep it a mid-tone
  with room for both the white highlight and the shade; never brighten it toward
  white or darken it toward black. Separate it with a hairline edge only, no shadow or sidebar divider.
  The island clips its page,
  including the sticky header blur; the chrome must not bleed into that blur.
  The recording HUD is not part of this shell.
- Keep every project-owned `AGENTS.md` and its same-directory `CLAUDE.md` as
  byte-for-byte replicas. Whenever documentation, Markdown, project behavior or
  workflows change, update affected guidance in both files in the same change;
  never update only one. Create, rename, move or remove both files together.
  Verify that every pair matches before finishing or committing the change.
- After completing and validating a requested fix or feature, make a local
  conventional commit for that task on its branch (see Checkouts and branches)
  unless the user asks to leave it uncommitted.
  Stage only task-related files or hunks; preserve unrelated worktree changes.
  If the task cannot be committed cleanly, explain why. Push or release only
  when the user requests it.
- Interface consistency is a product requirement. Native section cards must have
  equal top, bottom, leading and trailing insets: `Theme.cardPadding` (16 pt).
  All page content cards use `Theme.cardRadius` (18 pt) for continuous corners.
  Use `PageSection` and `SettingsCard` for settings sections, including Settings
  and Models. The card owns the outer padding; rows inside it must not add another
  vertical inset. Use shared spacing tokens instead of page-specific values.
  Text uses the `TextStyle` tokens in `Typography.swift` through `.appFont(_:)`,
  never a fixed `.system(size:)`; symbols, brand marks, the HUD and the native
  menu keep fixed sizes. Settings > Appearance > Text size (Default, Large,
  Larger: 1.0/1.12/1.24) scales the tokens because macOS applies no Dynamic Type
  to SwiftUI text; Default keeps the design sizes. At Larger, copy wraps rather
  than truncates in the 784-point window, and fixed text columns grow with the
  scale. AppKit draws native menu-picker titles at 13 points, so above Default
  `SoftPicker` draws the selected choice's label at the scaled body size and grows
  its width; the native picker stays underneath at 0.001 opacity (never 0, which
  drops it from the accessibility tree) for VoiceOver and the keyboard. Every control has a VoiceOver name (not just a placeholder) and state;
  never emit `accessibilityHidden(false)` (use `accessibilityHidden(true,
  isEnabled:)`), never let an SF Symbol name a menu, and give labelled composites
  a role. Section titles are headings. Spatial animation has a Reduce Motion
  branch; see `docs/accessibility.md`.
  Descriptions use the shared `.supportingText()` style: 11-point regular,
  secondary text below 13-point setting titles. Keep each description to one short
  phrase when possible; retain essential privacy, cost and recovery information.
  Remove redundant descriptions and place longer explanations in existing details
  disclosures. Error notices keep the message and action in one horizontal row;
  long diagnostics may wrap beside the action. Reuse `NoticeRow` inside an existing
  card and `InlineNotice` for a standalone card; never nest cards or repeat their
  outer padding. Read errors offer reload/retry-read, not Retry Saving. Separate
  every Home readiness row
  with `RowDivider`, including rows without a trailing action. `RowDivider` is the
  only separator inside cards: an engraved groove, a shade line with a highlight
  line just below it from the same top-left light, never a flat hairline.
  Section headings use a shared 32-point minimum row height, a 12-point gap to
  their content and 28-point section spacing. Center titles and trailing controls
  vertically within the row, including provider pickers. Inset only the heading
  text by `Theme.sectionTitleLeadingInset` (4 pt) for optical alignment.
  Page content must fill its available width after `Theme.pagePadding`; do not add
  a left-aligned maximum width that strands section controls far from the window's
  right edge. Section headings, their trailing controls and cards share one right
  edge. Use `SoftPicker(title, selection:, width:)` for menu pickers in settings rows or
  section headings so the visible control aligns with that edge. Numeric settings with a
  stepper must also support direct keyboard entry through `SettingsNumberStepper`.
  Settings keeps a recessed Search settings field at the right of its page
  heading. Index the actual section titles, setting names and descriptions through
  `PageSection` and `SettingRow`; do not maintain a duplicate catalogue. Match all
  query terms case/diacritic-insensitively, prioritize exact setting names, and
  retain page order otherwise. Debounce typing, rebuild the index only when copy
  changes, and never search during scrolling. Keep results in place with recessed
  highlights 4 pt inside the card edge with concentric 14 pt corners, scroll
  the active result clear of the sticky header, and support
  keyboard focus, previous/next, clear and no-match states. Search reveals conditional
  controls with their prerequisites without changing settings. Result jumps are
  never animated: an animated `scrollTo` leaves SwiftUI's stored offset behind and
  the next focus or accessibility update pulls the result out of view, so Reduce
  Motion needs no separate branch. The settings-search fixture asserts that walking
  the accessibility tree leaves a settled result in place; other pages remain unaffected.
  Keep settings copy purposeful: do not add descriptions that merely restate the
  selected provider, that a list is showing models, or other facts already obvious
  from the control. Keep concise text when it changes a decision or explains an
  actionable error, unavailable state, permission, or cost. Put related heading
  actions immediately beside their selector rather than separating them with a
  fixed-width invisible frame. Provider selection uses one compact picker, not
  a grid of decorative provider cards. Models lists speech in one Speech models
  section (AD-108): its heading holds a location picker (On this Mac or Cloud,
  opening on this Mac, with no page-level filter) and, right of it, that location's
  provider picker defaulting to All. Both filter browsing without changing the
  active speech config; only choosing a model selects its provider. The local view opens with a
  compact set from `LocalModelShortlist`: the recommendation plus at most two
  curated Verified alternatives (never Qwen3-ASR 0.6B), deterministic per language
  and memory, then Your models (app default, active profile binding, installed and
  downloading models it does not already show). Show All Models (N) reveals the
  full table; choosing a local provider lists all of that provider's models and
  hides the button. The choice persists
  in `AppSettings.showsAllLocalModels` without counting as an existing setup, and the
  button hides while searching. Search always covers the whole catalogue, including
  language names. Each row shows one strength label, never an accuracy claim
  Airdraft has not measured, and its languages as one compact tag
  (`ModelLanguageTag`, AD-122): "30 languages", "English only", or for lists Airdraft
  does not have "Languages set in macOS", "Detects languages" or "Languages
  unverified", never an invented list; a long tag wraps rather than widening the
  row past the window. Local and cloud rows read the tag from
  `SpeechLanguagePolicy.capabilities` through `ModelLanguageInfo`. Its tooltip names
  every language (the user's language first); clicking a tag with more than one
  language opens `ModelLanguagesSheet` from the page (Your languages, then all A to Z,
  with search past 12), and VoiceOver reaches it through the row's Show Languages
  action. Clicking anywhere else in a row chooses its model (an installed one for
  local rows); the tag, the pin and the download, cancel and delete buttons keep
  their own clicks. Every local and cloud row has a pin button (`ModelPinButton`,
  AD-124) with a name, Pinned/Not pinned value and tooltip. Pins are
  `AppSettings.pinnedSpeechModels`, keyed by `ModelEntry.id` or
  "<preset id>/<model id>", a view preference outside the `settings.` keys that
  Reset All clears; unknown IDs are ignored. Outside search, pinned local models
  lead under a Pinned heading (`ModelCatalogue.localItems`, catalogue order) and
  pinned cloud models come first (`ModelCatalogue.pinnedFirst`), in the compact
  set, the full table and a provider filter; each row is listed once (a pinned
  shortlist row keeps its label) and pinned retired or Experimental models stay
  listed. Search keeps the normal order. Language summaries state the model's own
  coverage, never support relative to Chinese; Chinese-only strengths (Qwen3-ASR
  1.7B's mixed Chinese and English) show only to users with a Chinese language
  (`ModelCatalogue.speaksChinese`). Local rows whose model shows live text with the
  Selected speech model source (`ModelSpeechPreview.showsLiveText`) carry an accent
  Live text badge below their tags. Keep table headers fixed and cap the
  scrolling rows of the full and cloud lists, and of any compact list over six
  rows, at `Theme.modelTableMaxHeight` (300 pt); shorter lists show every row
  without an inner scroll. The full local table opens with Recommended for your
  language, then Verified and built-in models, then a collapsed Experimental
  disclosure that search opens.
  Collapsed, it still lists Experimental models in use: the app default, the active
  profile's binding, installed files (checked on a worker) and running downloads;
  `models-performance` asserts this. Tiers
  are data in `ModelCatalogue.verificationEvidence` with a source per ID (GigaAM v3
  E2E RNN-T cites `eval/intl-asr`); promote a
  model only after an actual download, load and transcription.
  Long model tables use native List virtualization; group each row with its
  separator as one cell. Short lists measure an eager stack and clamp geometry
  observations to the viewport cap. Preserve native accessibility scrolling;
  do not expose SwiftUI lazy-stack identity traversal for end-of-list actions. Check installation on a worker,
  cancel stale UI updates on row eviction, and refresh after download completion.
  Use the model's official brand icon, falling back to its creator's company logo,
  never a color-coded waveform. Show the hosting provider beneath cloud models so
  the same model on different services stays distinguishable. Bundle brand assets
  locally and document their sources in `docs/model-brand-assets.md`. Render brand
  icons in 24-point white tiles clipped to 6-point continuous rounded corners,
  keeping transparent artwork on white in both appearances. Keep compact
  13-point model names and 11-point secondary text, with equal 16-point row insets.
  User-facing summaries (Home readiness, the Profiles speech row) name models
  through `ASRConfig.displayName` / `LLMConfig.displayName`: catalogue titles with
  local runtime/quantization or cloud host, and the refinement provider with a
  readable model name. Unknown or custom models fall back to their raw ID.
  `engineLabel` and `engineID` are diagnostic: help text and logs only.
  Profiles uses the same compact picker in its
  Profile section heading instead of a profile list; names carry it, without icons.
  Each profile may bind a speech model; nil means Use App Default. Store only the
  provider/model selection and custom-server endpoint/key reference, never key values
  or copies of shared language/script settings. Resolve the active profile for
  preflight, loading, recording limits, transcription and Home/menu status without
  overwriting `AppSettings.asr`. Capture the profile and resolved speech config at
  recording start together with refinement and output settings; use that same snapshot
  for preflight, prewarming and processing. Changes apply to the next recording;
  explicit retry resolves current processing settings while keeping the original
  delivery target and policy. Keep Speech model visible with refinement off, preserve
  bindings on duplication, and clear them on reset. Models edits the app default
  and shows when the active profile overrides it. Missing models or credentials
  require setup; never silently fall back to another speech model.
  Keep Apple Speech locale available for an active Apple binding. Protect the app
  default, the active profile's model and, with Choose profile by app on, every
  model an app rule's profile binds from deletion; re-measure SetupFacts after
  deleting files. Downloads must not
  change the app default while a profile override is active.
  Choose profile by app (`ProfileStore.choosesProfileByApp`, off by default) applies
  `AppProfileRule`s stored in profiles.json: one app by bundle ID, or an
  `AppProfileRule.selectableFamilies` family (code editors, terminals, email, work
  chat, personal messages, documents) classified from the bundle ID alone, never
  from window content and independent of Read app context. Browsers have no family:
  classifying them would need their URL. Rules point at existing profiles; never
  ship preset rules or invent profiles for them. An app's own rule beats its
  family's, which beats the chosen profile. Recording start resolves the frontmost
  app before preflight and snapshots that profile, including its speech binding and
  refinement opt-out; a rule change during startup is rejected as changed setup. It
  follows a different captured destination only when that needs the same speech
  model and no unchecked refinement. Retries resolve current rules for the
  recording's original app; practice ignores rules. Deleting a profile removes its
  rules; Reset All clears them and turns the switch off; resetting a built-in keeps
  them. Unreadable rules are skipped without setting the file aside and written back
  unchanged on save (deleting their profile or Reset All removes them); rules for
  missing profiles and duplicates are dropped on load. The menu titles an automatic
  profile `Profile: <name> (auto: <app>)` through `MenuTitle.profile`, from a
  frontmost-app tracker that ignores Airdraft, shortening the app name before the
  profile name. `AppContainer.speechConfig`, Models and Profiles labels and
  preloading still follow the chosen profile.
  The sidebar microphone overlay contains device choices with a live ten-cell
  meter at each row's trailing edge. Omit decorative descriptions and a separate
  meter card; retain actionable permission and device errors. Keep it compact:
  336 points wide with an 8-point inset, a 28-point title row and 32-point rows on
  the sidebar's scale, aligned with the microphone capsule and 8 points above it.
  Monitor each eligible device once and share its level with System Default.
  Identify wired/wireless Continuity microphones by Core Audio transport type;
  preview them only when selected, including when System Default resolves to them.
  Opening the picker must not connect unselected iPhones. Stop their previews on
  deselection, and stop all previews when closed or the aggregate pipeline is busy,
  including pending startup, media work, meeting capture and maintenance. Guard
  device/channel setters with the same aggregate state.
  Sidebar destination selection is an opaque recessed well: 2.5-point depth,
  top-left inner shade and bottom-right inner light. The microphone button is its
  deliberate inverse, so a control never reads as a selected page: a raised
  38-point button (`NavigationStyle.microphoneHeight`) in the sidebar's tone with
  top-left light and down-right shade, its symbol in a recessed 32-point socket
  (`MicrophoneIconSocket`), plain rather than carved, with a trailing chevron;
  pressing sinks it into a well. Both use `NavigationStyle.wellShape`, 12-point
  continuous corners, and the same 4-point inset from the sidebar content edges
  (`NavigationStyle.destinationInset`), so the same width. Destinations are
  34 points high (`NavigationStyle.destinationHeight`) with a 28-point icon island.
  Destination and microphone labels share a 44-point start
  (`NavigationStyle.labelStart`). Destinations have no chevron, so their trailing
  padding is 6 points and titles stay on one line. Hover and press fills on
  destination rows use the same radius. One well serves both destination groups: rows publish their
  bounds with `.sidebarSelectionAnchor`, and `.sidebarSelectionWell` slides it to
  the selected row on a 0.36-second ease-in-out curve (`SelectionMotion.curve`,
  cubic-bezier 0.65, 0, 0.35, 1), whatever changed the
  page. Rows never draw their own selected well; Reduce Motion moves it instantly.
  Inside the well, the selected icon rests on a flat raised island built like a
  switch knob on its track (`SoftWellIsland`): a solid square face whose corners
  follow the well's, concentric at 9 points (`NavigationStyle.iconIslandShape`), and
  that touches the well's top, bottom and leading edges 3 points in
  (`NavigationStyle.iconIslandInset`). Its highlight and shade stay clipped inside
  the well, never leaking out. Rows publish their icon bounds with
  `.sidebarSelectionIconAnchor`; the icon frame equals the island's side. The well and island animate independently: the well
  moves first and the island follows on the same curve 300 ms later
  (`SelectionMotion.islandCurve`), visible only inside the moving well. The selected
  symbol is carved deep into the island (`SidebarIcon`): a dark glyph with a shade rim
  up-left and a highlight rim down-right, appearing as the island arrives.
  Home summary fills use one solid neutral gray, raised inside their inset track
  with a top-left highlight and down-right shade; never a brand hue.
  Sidebar destination, microphone and account symbols use
  `Theme.sidebarIconSize` (13 points).
  Keep the main window 784 points wide with resizable height (minimum 600 points).
  Hide its green zoom/full-screen button; preserve Close and Minimize.
  Inset the native window buttons 16 points from the top and leading edges
  in the 46-point titlebar. Page
  titles use 18-point semibold type. Headings and actions use a separate
  32-point row with 16 points above it inside
  the island and 12 points below, inside one 60-point sticky header. Its backdrop
  blur is 80 points tall, extending 20 points below the header without moving
  the heading row or controls. The bottom 5 points feather into a visible 1 pt
  blur; increase quadratically to 32 pt at the top. Do not leave a
  nearly sharp lower region or obscure entering text immediately.
  Use `ProgressiveHeaderBlur`; never simulate this with material opacity, a tint
  gradient or a short edge fade. Keep header labels and controls sharp. The
  undocumented compositor filter is isolated and capability-checked, with a
  standard material fallback on unsupported systems. Suppress native hard
  scroll-edge separators; only Reduce Transparency gets an opaque header. Keep
  the 24-point content inset inside scrolling content, including both History
  columns, and preserve vertical positions on collapse.
  History has a compact 52-point timeline (widened by the Text size scale)
  beside its independently scrolling cards. Timeline day headings always show calendar dates such as Sep 25;
  reserve Today and Yesterday for the main card column. One time-and-tick button
  jumps to each entry; the current entry stays
  highlighted as the cards scroll. Returning the cards to the top also restores
  the timeline's first day heading, even when its first entry is already active.
  History prepares grouping, formatted labels, text previews and audio availability
  once per database page off the main actor. Keep timeline scroll state separate
  from page data, and find the first visible record through the snapshot ID index.
  Scroll the timeline only when the highlighted row reaches its visible edge,
  leaving room ahead; selection updates per-row marks. Never scroll it or
  re-evaluate its body for every current-record change; the fixture checks this.
  Never scan or regroup all loaded records during scrolling or check files from
  row bodies. Keep accessibility scrolling independent of SwiftUI lazy-row identity
  traversal; its lightweight representation exposes visible rows, shares row actions
  and provides first/last, page and record navigation. Track timeline visibility
  per rendered row so programmatic jumps expose the visible timestamps to
  accessibility. Remove visibility when lazy rows disappear as well as when their
  visibility callbacks change; returning to the top must not retain offscreen
  timestamps. The navigation fixture asserts this cleanup. Exclude zero-visibility
  prefetched rows from active-entry tracking, and reveal the real row before
  presenting Details or Delete. Collapsed text uses bounded native layout with sizing
  cached across lazy-row recreation and Show More created only when needed, not
  hidden full transcripts or geometry-to-state height feedback. Preserve full text
  for Copy and expansion, and keep expansion/version state outside lazy rows.
  Explicitly clip the native transcript field to its measured bounds so long text
  and selection cannot draw over Show More, the version picker or card actions.
  Verify the drawing boundary as well as the six-line measurement.
  Keep day groups, search, lazy card loading
  and native card actions. Home Recent and History show durations through
  `DurationLabel`: seconds, with one decimal below 10 s. A failed History read
  shows only its Reload History notice, never the empty state;
  `AIRDRAFT_RENDER_HISTORY_ERROR` applies to Home and History. The timeline follows the same filtered records. Refresh sidebar word totals after single/all history
  deletion and every completed save retry; reject stale asynchronous count results.
  Home's waveform well is 60 points tall with 24-point minimum horizontal inner insets.
  The hero card itself is raised: `SurfaceShadows` casts a soft highlight up-left
  and a shade down-right from the top-left light. Never leave it flat. Keep its
  surface gradient and top-left sheen subtle (a 0.02 gray ramp); the cast
  shadows carry the depth, with a clearly darker light-mode shade.
  Keep light-mode bars visibly darker than the well, with raised highlights and
  down-right shadows. Preserve bar heights and hover behavior. The caret and the
  hovered bar are neutral gray, a step darker in light mode and brighter in dark
  mode than the bars, raised with the same lighting; never violet, cyan or a glow.
  The hero card's edge highlight stays faint; its cast shadows carry the depth.
  Home waveform entrance waits for initial history, then animates rendered scale
  once; never animate placeholder replacement or per-frame bar layout height.
  Each real waveform bar is a keyboard-accessible button keyed by its saved
  record ID. Clicking toggles that dictation's delivered text inside the hero;
  another bar switches it, and Close or Escape dismisses it. Keep the selected
  bar highlighted with a small dot while retaining hover magnification. Reuse
  History's selectable six-line transcript with Show More and full-text Copy.
  Clear selection when the period changes or the record leaves the overview.
  Empty-state strokes are decorative. The four headline values use 23-point type.
  Before the first saved dictation, the hero replaces its zero metrics with a
  same-height first-dictation headline; the metric row stays hidden until history
  loads. Only a loaded, empty History is a first run (`HomeHistoryContent`): a failed
  read or missing store shows History Unavailable and an error-aware Recent card.
  Home's readiness card, hero and the sidebar footer share `SetupReadiness`, which
  also reports the pipeline's blockers (`DictationBlocker`): an official build's
  missing trial/license (Trial & License…) and full kept-recording bounds (retry or
  discard). A pending license read is not a blocker. The footer opens Home (Finish
  Setup, or Recordings Waiting when that is the only issue), or the Trial & License
  sheet (Start Trial / License) when the license is the only issue. File and system
  checks behind readiness come from `SetupFacts`, measured off the main actor,
  never in view bodies; readiness reads only stored results (up to eight recent
  ones per input combination), and a fact not yet measured shows as Checking
  (busy, not a setup step) until the background refresh lands. Debug renders may
  measure directly; the architecture fixture asserts this.
  With Choose profile by app on, readiness also checks profiles that app rules
  choose whose speech setup, model binding or refinement differs from the chosen
  profile's (`AppRuleReadiness`, the same checks as the recording prerequisites),
  measuring their model files through `SetupFacts` and checking rule keys for
  presence only. An App rules row names the first blocked app and profile with the
  existing setup action and counts toward the summary and sidebar footer.
  Home's pipeline summary wraps at every text size instead of truncating, keeping
  its ` · ` and ` → ` separators at the end of the line they follow. Home's
  overview totals, longest dictation and per-app shares are aggregated in SQL from
  stored word counts; only the latest waveform bars and uncounted rows read text.
  Reuse the shared components in `Theme.swift` (`StatusDot`, `RefreshButton`,
  `EmptyNote`, `OverlayPanel`, `.settingsDisclosure()`) and the `APIKeyField` row
  for every provider key instead of page-specific variants. English buttons and menu
  items use title case; section headings use sentence case. Other languages follow
  their own capitalization.
  Read the interface consistency rules in `docs/PRODUCT.md` and inspect light/dark
  renders of the pages a change touches at the fixed 784-point width, adding the
  minimum height or lower sections only when the change reaches them. For a released
  UI fix, verify the app built from the committed release sources, not only the dirty
  workspace.
- Neumorphism covers the whole window. Page cards and controls use
  `SoftRaisedSurface` from `SoftControls.swift`: the Home hero's light and shade at
  full strength (white highlight up-left, shade down-right), with a smaller spread,
  half for `Card` sections and a quarter for controls. Render each face and its edges
  in one `drawingGroup`, cast shadows outside it. Faces are one flat tone, like the
  microphone button: never a gradient across the face, including the tinted
  prominent fill. Edge rims and hairlines stay barely visible (half their former
  strength: white rim 0.024 dark, 0.135 light; hairline 0.0175, inset tracks 0.02) so light and shade, not an outline, shape them; Increase
  Contrast keeps its explicit edges. Never lower their contrast to
  make them subtle; shrink the spread instead. Controls are raised: `SoftButtonStyle`
  and `SoftIconButtonStyle` sink into an inset well while pressed; text fields use
  `.softField()` with an accent ring while editing; menu pickers use `SoftPicker`;
  segmented choices use `SoftSegmentedPicker` (a raised thumb sliding on an inset
  track with `SelectionMotion.curve`); switches use `.toggleStyle(.softSwitch)`, whose
  on state fills the inset track with the system accent. Objects inside a track or
  well (thumbs, knobs, icon islands) keep their light and shade clipped inside it.
  Sliders use `SoftSlider` with shared focus, arrow-key and accessibility adjustment.
  Set its keyboard step independently where seeking needs coarser steps; do not
  add a second per-consumer move handler. Steppers use raised minus and plus buttons beside the typed value.
  Buttons, menu buttons, pickers, segmented tracks, search fields and text inputs
  share one shape, `SoftControl.shape` (8-point continuous corners); never
  capsules or circles. Segmented thumbs stay concentric inside their track; only
  switch and slider tracks stay round.
  The main window root applies `.focusEffectDisabled()`, which its sheets and
  popovers inherit: keyboard navigation never draws the system's blue focus ring
  around soft controls. It must sit on an ancestor; inside a `ButtonStyle` it has
  no effect, and `\.isFocused` does not reach a style either.
  Every primary action, including onboarding, License, Settings and Transcribe's
  Record Audio, Start Recording, Stop and Save, Transcribe and Save Changes, uses
  `.primaryButtonStyle()`, which applies `SoftButtonStyle(prominent: true)`: blue
  fill, white type and the same raised, pressed and disabled geometry as secondary
  buttons, keeping its color when the window is not key. Header actions share the
  28-point control height. Native link buttons and the menu-bar menu stay native. Reuse `NeumorphicSurface` for the sidebar wells,
  keycaps, meters, preview frames and Home tracks. Light comes from the top left in both appearances: raised surfaces
  highlight their top-left edge and cast shadows down-right; recessed surfaces
  shade the inner top-left edge and light the inner bottom-right edge.
  Use `SurfaceShadows` for outer shadows: AppKit bitmap capture can invert the
  vertical offset of SwiftUI's direct shadow modifiers. Check the live window
  as well as saved renders. Keep selection/focus cues, card insets and live waveform
  contrast. Model table rows and text lists stay inside their raised cards without
  extra per-row depth. Scroll views must not clip raised cards' light and shade:
  History's card column extends into the timeline gap and the page's trailing and
  bottom margins, with matching content margins that keep the cards in place.
- Recording window offers Classic, Cube, Sonic, Orbit, Silk and None; Classic is
  the default. Migrate saved Mini selections to Classic and retain older Classic
  selections without changing timer preferences. Every visible preset uses the
  same 82-by-22-point well, 34-point capsule and six-point outer insets. The timer is an independent
  module, off by default for every preset, with a persisted Left/Right position.
  Settings shows Show timer and, when enabled, Timer position; previews
  reflect both settings. Hide these controls for None without resetting them.
  Timer-free recording reserves no label space; processing labels remain visible
  in all five visible presets. Cube uses shaded rotating face plates; Sonic shows only
  braided ribbons, with no cube. Orbit uses interlocking silver gyroscope rings;
  Silk is one folded metallic ribbon. Settings > Appearance offers Disco, an
  independent persisted switch,
  off by default and shared by all five visible styles. Hide it for None without
  resetting it; search reveals it disabled with prerequisite guidance. Color only
  the animated artwork, retaining neutral capsule, well, timer and status text.
  Use the shared HUDDiscoMotion/HUDDiscoFrame palette: voice energy controls
  saturation, smoothed syllable attacks add an accent, and gated accumulated
  energy advances continuous ice/sapphire/amethyst/coral/amber/mint color bands.
  Silence settles and holds color; do not use random jumps or a wall-clock hue loop.
  Preserve each style's directional shading. Reduce Motion stops color travel
  while retaining static level-driven color, and delivery freezes the palette
  together with geometry. Previews use the same palette and synthetic levels.
  Disco intensity (`AppSettings.hudDiscoIntensity`, 0–1, default 0.5, the original
  palette exactly) sits under Disco as a Gentle–Vivid `SoftSlider`, shown while Disco
  is on and revealed disabled by search. `HUDDiscoFrame` carries it: low stays pastel
  (a lower saturation cap and gain), samples a narrower band of the ring and travels
  slower; high saturates sooner, purifies the pigments, spreads more of the ring
  across the artwork and travels faster. Silence still holds color, Reduce Motion
  keeps static level color at the chosen intensity, and the lit palette keeps its
  contrast in the dark well at every intensity.
  Drive spatial motion from those same recent microphone
  levels, with bounded fast attack and slower release; never open another audio
  input or call it a frequency spectrum. Keep motion in the visualization well and
  freeze its phase and energy during delivery fade. Reduce Motion stops rotation and travelling
  waves while retaining a static level response. Settings previews use
  synthetic input for every visible style, including the Classic waveform, and
  pause in renders, inactive scenes and Reduce Motion. Keep specimens at the same
  0.78 scale (1.2 times the former spatial specimen), in 115.2-by-72-point preview
  faces, with three columns below the setting title. Theme previews retain their size.
- After successful text delivery, freeze the recording HUD's final processing
  display and fade the capsule out over 0.5 seconds. Start at delivery, before
  clipboard restoration and history saving; never return to the recording timer
  or reopen it for a later success notice. New recording cancels the old fade.
  Exception (AD-104): a dictation that asked to send, or whose flags will be
  listed, keeps the window through its send window and shows the outcome as a
  notice (`DictationPipeline.holdsRecordingWindow`).
  Failures and recovery notices expand the native panel over 0.28 seconds to show
  complete wrapping text centered vertically in the panel. Only errors show
  Copy Message at the far right, centered beside the text. Notices and informative
  confirmations have no copy action or reserved button space, preserving the
  delivered transcript on the clipboard. Bound the
  panel to the current screen and scroll oversized diagnostics without truncation.
  All error, recovery and informational messages show for five seconds from
  presentation, then fade over 0.5 seconds. Keep their snapshot through the
  pipeline's earlier idle reset without restarting the deadline. A new operation
  cancels the old timer; expired messages must not reopen on idle or style changes.
  Keep recovery details on Home and in History where applicable. Copy must preserve all text without activating the panel;
  recording remains click-through. Reduce Motion disables spatial expansion.
  Size the capsule to its enabled timer or current status label, with six-point outer
  insets on every side of the waveform well. Timer and status text have a fixed
  12-point inset at the exposed capsule edge: leading for a left timer, trailing
  for a right timer or status label. Do not reserve a fixed label width;
  grow the native panel when the timer gains a digit and keep it centered.
- Native menu items never wrap, so the widest title sets the menu-bar menu's
  width. Keep that menu about 270 points wide: pass every dynamic title (status,
  issues, notices, device, profile and provider names) through `MenuTitle.fit`,
  which measures the menu font against a 190-point limit. Never show full
  diagnostics in a menu item; keep them in tooltips and Home's recovery notice.
  Keep three groups: recording (Start Dictation, Record Audio)/History/Settings, current microphone/profile/refinement
  choices plus Models, then app commands. Show current choices in submenu titles.
  Do not add a permanent status header; display the shortcut as a native badge on
  the recording action without registering another shortcut. Processing replaces
  that action with a disabled stage label and keeps Cancel available. Put model
  status and maintenance inside Models, label Speech and Refinement explicitly,
  and use the active profile's speech binding and refinement opt-out. Only current
  provider health marks Refinement unavailable; keep prior issues in Review Last
  Dictation and retained audio in Recover Last Dictation with retry/discard.
- Speech language compatibility is owned by `SpeechLanguagePolicy`, keyed by the
  exact model and provider/runtime. Models shows choices for the active profile's
  effective speech model; model/profile changes never rewrite the shared language.
  Preflight, file/history transcription, retry and the factory validate the same
  snapshot before credentials, model loading or capture. Known unsupported choices
  fail with a Models recovery action; unknown custom models stay explicitly unverified.
  Cohere's pinned runtime requires an explicit supported language; never let Auto
  or an unknown code become English. Experimental unknown-language prompts are not
  a production Auto contract. SenseVoice rebuilds its recognizer when its effective
  language changes; preparation builds it for the recording's anticipated language.
  Two SenseVoice artifacts exist: the original multilingual SenseVoiceSmall
  (`senseVoiceMultilingual`, shown as SenseVoice) and the 2025-09-09 WSYue Cantonese
  fine-tune, which keeps the `senseVoice` IDs, is shown as SenseVoice Cantonese, is
  listed only while in use and offers no Japanese or Korean. Qwen uses upstream language names in decoder options. Apple
  exposes its effective fixed locale and asks the OS for supported equivalents;
  Apple Speech Mandarin follows the Chinese script (zh-CN for Simplified, zh-TW for
  Traditional). A bare speech language takes the Mac's region where the language
  has a locale there; English only in its own regions (`englishRegions`), otherwise
  en-US. Joint-language models validate the user's intent without sending an
  ignored forced-language parameter. Mandarin, Cantonese and Chinese script stay distinct.
- Local speech output passes `LocalASROutputGuard` inside the engine lease before
  refinement. Decoder loops are cut to one copy (one token repeated 8 times, two
  tokens 6 times, longer blocks 4 times) for dictation and media windows; ordinary
  emphasis survives. Qwen3-ASR chunk caps scale with audio (16 tokens per second
  plus 48, at most 1024). Retries reuse the same model and lease, never switch
  models, run only when the first decode was fast enough, keep the first result on
  failure and propagate cancellation: an empty result on audible audio gets one
  relaxed retry (Whisper without its no-speech gate or prompt, rejecting filler-only
  output), and only under Auto a result mostly in a script none of the system
  languages plus English use, or a Latin-only Whisper result whose own probability
  for a system language written in another script (not Serbian) reaches that
  language's threshold (0.1 unless `measuredTranslationProbabilities` sets one), is
  decoded once more with the best explicit language the model supports, kept only
  when it fits better. With Whisper's probe the retry language is the most probable
  system language, a non-English one first when it reaches its threshold; without a
  probe, the first non-English system language. Record each correction on the transcript
  and log it without text. SenseVoice and FireRedASR2 output gets natural-case
  English (keeping dictionary spellings, known acronyms and spelled letters) and one
  sentence-final mark for three or more tokens inside `SherpaTranscriber`, before
  refinement, the Chinese script converter and the dictionary. Re-measure guard
  changes with `eval/mixed-asr/run_guards.py` and `score_guards.py`, including the
  English control set.
- On-device vocabulary biasing goes only through `TranscriptionHints.onDeviceVocabulary`,
  controlled by Settings > Behavior > Vocabulary in speech recognition (default on)
  and captured at recording start. It sends preferred spellings only, never misheard
  aliases, capped at 50 terms of at most 40 characters and four words, 600 characters
  in total, without markup and limited to the scripts the speech language uses, each script separately
  (`WritingScript.nativeScripts`). Only
  Qwen3-ASR context and sherpa-onnx transducer hotwords (Parakeet, Orukeet) receive
  it. Qwen drops the terms on near-silent chunks (about -50 dBFS) and decodes again
  without them when the output is only the term list. Parakeet switches to its
  hotword search mode only when terms apply, writes the spelling list to a temporary
  file outside the model folder, and skips terms the model cannot spell. Whisper,
  including GGUF Whisper, stays term-free: a guarded glossary prompt dropped and
  translated utterances and slowed decoding (measurements in
  `eval/vocab-bias/results/summary.json`). Apple Speech, SenseVoice, FireRedASR2, Cohere and FluidAudio
  get no biasing. Cloud keyword fields and dictionary post-processing are unchanged.
- Both stages are provider-agnostic. New engines implement `Transcriber` or `Refiner`,
  get a `*ProviderKind` case, and are wired in `EngineFactory`. Never hard-code a provider
  in the pipeline or views.
- `ASRConfig.engineID` must equal the `id` of the transcriber `EngineFactory` builds for it
  (`EngineFactoryTests` checks this); the UI looks up load state by it.
- Local engines load only from `LocalModels` folders and never download on their own.
  Starting dictation automatically loads an installed but unloaded speech model,
  showing Loading in all visible HUD styles before opening the microphone.
  Join an existing load through `EngineFactory`; cancellation or changed setup
  must not start stale recording. Missing model files still require installation.
  Home treats an installed but unloaded local model as ready ("Loads when you
  dictate", optional Load Model); only missing files, keys, bindings, language
  issues or a failed load count as setup steps.
  Bound speech-model preparation to 120 seconds. Cancellation and timeout release
  the selection lease even when a native loader ignores cancellation. Retire that
  engine instance until its preparation returns, then unload it without publishing
  late readiness. Block another load of the same model until retirement completes;
  other models remain selectable. Keep its files protected through
  `EngineStatus.hasPendingLoad`, and let reset/quit wait for retirement within their
  existing deadlines. Active inference and its unload still share the factory lease.
  Resolve one request-scoped transcriber for preparation and inference; cloud
  credentials are read once for that operation and remain fresh on later calls.
  ASR timings include lease wait, model preparation and inference. Refinement
  timings include discovery, loading, retries and failed attempts; timing logs
  contain durations and engine identifiers, never audio, text or credentials.
  LM Studio readiness and UI status use one fresh model inventory snapshot per
  check, preserving exact instance IDs and external unload visibility.
  Refinement preparation starts during recording (or before ASR for file/retry
  work). Keep one refiner per captured session and join in-flight LM Studio
  discovery/loading for the same endpoint/model. Preparation may continue for
  the native 300-second load lifetime while recording; the configured final
  deadline still bounds its remaining wait plus inference. A cancelled waiter
  cannot cancel another session's shared load or publish late results. Reset and
  quit drain pending loads within their deadlines while independently stopping
  speech engines and CLI children. Do not cache completed model readiness.
  The same discovery result identifies LM Studio for best-effort prompt-prefix
  warmup during recording: use the captured empty-transcript request with the
  same model/options and a one-token output cap. Keep the formal request intact;
  warm output never reaches fidelity, delivery or history. Skip this request on
  cloud/unmanaged servers. Ordinary warmup failure cannot fail final refinement;
  ASR completion cancels unfinished prefix work without awaiting it or consuming
  the final request's deadline. Cancellation still discards the session. Do not
  introduce a second discovery.
  Capture base rules, vocabulary and app-context consent with the recording's
  configuration. CLI warm sessions belong to one recording generation; discard
  them on cancellation, skipped refinement, ASR failure and short/empty capture.
  Expose separate model/prompt-prefix preparation, remaining wait, request, postprocess,
  delivery and history durations. Stop-to-delivery ends at confirmed delivery or a sent caretless paste,
  excluding clipboard restoration and history; file/review fixtures leave it nil.
  Idle speech unload defaults to 30 minutes. Models > Memory keeps user-selectable
  5, 10, 30 minutes and Never; preserve explicitly saved choices. An active
  dictation pins its local speech engine (`EngineFactory.pinForSession`) from
  recording start until processing ends, bounded by the model-load timeout, the
  effective recording limit and 300 processing seconds; releasing it restarts the
  idle countdown. Pins block only idle unloading, never explicit switch, reset or
  quit unloads. Warm CLI sessions owned by a recording live for the 600-second cap
  plus 300 seconds; unowned sessions expire after 180 seconds.
  System memory pressure (`MemoryPressure`: warning or critical, repeated events at
  the same or a lower level within 60 seconds dropped, a critical event during a
  warning pass run once afterwards) unloads ready, unpinned local speech models
  idle for at least 120 seconds (15 seconds when critical) and LM Studio instances
  the app itself loaded, never ones the user loaded. A pass never waits behind the
  factory lease: any running or queued load or inference skips it. It also skips
  while dictation, media, meeting or cleanup work is busy and during quit or reset
  (quit stops listening), never reloads, and logs only engine IDs, counts and
  durations. A skipped pass is not debounced: its highest level runs again when that
  work ends or a lifecycle model load finishes, with the grace periods measured then. The next dictation loads the model again as usual.
  Downloads go through `ModelDownloader` (Models page). Qwen3-ASR and WhisperKit
  files come from `local-pinned-models.json` (immutable revision, bytes, SHA-256),
  regenerated only with `scripts/pin-hub-models.py`; unpinned IDs are refused. A
  missing, malformed, empty or duplicate-ID pinned manifest never crashes: those
  downloads fail with a localized reinstall message while installed models keep
  working. The Models table is data in
  `ModelCatalogue`; installed, loaded, download and delete all derive from each entry's `select`.
  Model downloads report received bytes during each file, and Whisper includes tokenizer
  files in its byte total. Preparing, verification and unpacking use an indeterminate
  indicator; never assign made-up percentages to these stages. Models and onboarding
  share the progress view. Before data arrives, show activity without zero percent;
  positive progress below 0.1% reads <0.1%. Interpolate the measured percentage
  and bar together over 0.2 seconds, without extrapolating during network pauses;
  Reduce Motion updates directly. Keep callbacks ordered and bound pending UI updates.
- Refinement providers are native, not shims: `LLMProviderKind` carries the endpoint, Keychain
  key ref, default model and `wire` (OpenAI chat, Anthropic messages, Gemini generateContent),
  and `EngineFactory.refiner` switches on the wire. A new provider is a new case plus, for a new
  wire, a `Refiner` and a request-shape test in `RefinerWireTests` (a wrong field name otherwise
  only shows up as a 400 mid-dictation). Cloud keys live under `llm.<provider>` in the Keychain.
- Apple Intelligence refinement uses Foundation Models on macOS 26+ with a fresh
  on-device session per dictation. Check system availability before recording;
  never read a key or contact an endpoint for it. Keep the shared prompts and
  raw-transcript fallback for unavailable, refused, oversized or timed-out requests.
- Every provider speaks a different contract; the differences that have bitten us are:
  OpenAI-compatible (`Authorization: Bearer`, system as `messages[0]`, `reasoning_effort`),
  Anthropic (`x-api-key` + `anthropic-version`, top-level `system`, required `max_tokens`,
  `output_config.effort`, and **no `temperature`**: Claude 4.7+ reject it with a 400),
  Gemini (`x-goog-api-key`, `systemInstruction`, `generationConfig.thinkingConfig`).
  Every refiner retries a 400 once with a minimal, spec-core body, so a provider that rejects
  an optional field costs a little latency instead of the user's dictation. Keep that fallback.
  A complete successful minimal response after a full-body 400 may remember that
  negotiation for five minutes, scoped to endpoint, wire, model, credential and
  inference options. Store only an opaque digest, never keys or prompt/response contents.
  Failed/incomplete negotiations are not remembered; expiry or a rejected cached
  request restores the full contract. Keep the cache bounded.
- `ThinkingEffort` is one setting mapped per provider (`reasoning_effort`, `output_config.effort`,
  `thinkingBudget`, `--effort`, `model_reasoning_effort`). Cleanup needs none; `off` is the default.
- Subscription CLIs (Claude Code, Codex) are refinement providers too: `CLIRefiner` runs them
  non-interactively in a temp directory. Keep Claude Code's `--tools ""  --restricted
  --strict-mcp-config --disable-slash-commands`: without them the CLI ships its tool schemas,
  skills and user settings on every call (15k tokens of subscription usage instead of ~400).
  `--bare` is not an option: it disables OAuth, which is the whole point.
  Claude Code is started while the user is still speaking (`CLIWarmPool`, streaming stdin), which
  hides its ~1.3 s session setup behind recording and ASR. Codex `exec` has no streaming input and
  always runs cold. Launch and read CLI processes only through `CLIProcess` / `PipeLineReader`
  (output drained while running, wall-clock deadline, cancellation, SIGKILL fallback).
- Each dictation owns a generation and cancellable release timer. Stale asynchronous
  work must never change a newer session or insert text. Capture the local insertion
  target independently of optional LLM context. When the editor exposes a caret,
  require the same focused field and selection before inserting, then post exactly
  one paste. Editors that draw their own text (Zed, Warp, GPU terminals) usually
  expose no caret: verify the same process, its focused window and no foreign system
  focus instead; a missing caret alone must not block paste. One that does publish
  a field and caret (Ghostty 1.3) keeps the normal field and caret validation; an
  echoed paste is confirmed, and one its field never shows is sent unverified, not
  failed (`testSelfDrawingEditorWithCaretIsSentUnverifiedWhenReadBackFails`). Only the bundle prefixes in
  `TextInserter.selfDrawingEditorBundlePrefixes` (Warp, Zed, Ghostty, kitty,
  Alacritty, WezTerm; keep the list there alone) count as such editors. Every
  other caretless target (Finder, Preview, System Settings, a page without a
  focused field, an Electron app that never exposed its caret) still gets its one
  paste but keeps the transcript on the clipboard with the recovery notice. Never probe editor
  compatibility with an AX text write; both saved insertion methods use paste.
  Read application and system-wide focus with matching process ownership. When
  Electron has not exposed its editor, request `AXManualAccessibility` and await
  its field and caret before recording. Wait for native focus too, even when the
  web attribute is unsupported, but accept the app-level target once such an app
  keeps the same caretless focus for 250 ms. Accept one valid `AXSelectedTextRanges`
  entry when the singular attribute is unsupported; unknown selections never match
  a captured caret.
  Wait briefly for the original field and selection to settle before delivery,
  including when the same app is already frontmost. Before recording begins,
  follow an in-flight app switch within one 1.5-second capture deadline and require
  the field and caret to remain stable across run-loop turns. Prefer the system
  editor over stale application AX focus; a foreign system focus cannot authorize
  paste. After capture, keep the original destination fixed. Allow asynchronous
  activation to settle and retry transient final validation reads before posting.
  Keep `TextDeliveryRegressionTests` exercising production capture and insert
  entry points through an injected OS boundary and disposable pasteboard. Cover
  both persisted insertion settings, unavailable AX values, caretless editors,
  web/native focus, changed destinations, cancellation and context-off pipeline
  delivery through History.
  Local and release core runs must pass `verify-insertion-regressions.py` against
  their actual xcresult; its 71 mandatory insertion cases cannot be missing or skipped.
  A posted paste is not delivery confirmation. Read back the expected text from
  the original field before reporting success or restoring the old clipboard;
  compare the full value or the inserted UTF-16 range with the resulting caret.
  These reads stay local, independent of optional refinement context. When a
  receiver with a caret is slow, ignores paste or exposes no readable text, keep
  the transcript on the clipboard and show a recovery notice instead of silently
  dismissing the HUD. Record the reason with undelivered History status. Every
  case where the text could not be pasted but is on the clipboard (destination
  changed or unknown, paste not posted or not confirmed, a copy-only retry)
  shows only `TextInserter.copiedNotice` ("Dictation copied") in the HUD; the
  reason (`InsertionResult.detail`) goes to History and the log, never the HUD. A
  validated self-drawing editor cannot confirm its one paste: report it as sent
  unverified, never as failed. The HUD finishes as after delivery with no notice
  or error (a refinement fallback says the raw text was pasted, not inserted); History stores `inserted` false with cursor `outputSucceeded` true
  (`deliveryStatus` `.sentUnverified`, shown as Pasted, unconfirmed), and the
  displaced clipboard returns after `unverifiedRestoreDelay` (2 s) unless newer
  content replaced it. Read-back accepts only editor-normalized line endings,
  curly quotes and non-breaking spaces. Statistics count every dictation
  regardless of delivery status. Never
  repeat a posted paste. Once posted, confirmation and the restoration delay
  survive cancellation; preserve newer clipboard ownership and report copy
  failures accurately. Confirmed delivery releases the pipeline immediately: the
  inserter owns the delayed clipboard restore, and a newer paste takes over the
  clipboard the old one displaced, so an earlier restore never overwrites a newer
  dictation; after an unverified paste, the next insertion, including a copy-only
  retry, waits out that paste's receiver window before writing the clipboard.
  Cancel and the automation cancel are accepted during that wait: nothing is then
  pasted or copied, and the earlier paste keeps the clipboard and its delayed
  restore. A fresh dictation is saved to History as not delivered (Cancelled before
  delivery), with audio when retention allows; a cancelled retry keeps its recording. Once writing starts, cancellation waits as before. History saving and the outcome run in an ordered delivery tail
  (`isFinishingDelivery`); quit waits for it (bounded) and restores a confirmed
  paste's clipboard at once, but waits out an unverified paste's remaining 2 s
  delay so a busy receiver never reads the old clipboard; data cleanup and meeting start wait for it too. A shortcut rejected
  by media, meeting or maintenance work shows its reason in the HUD; a copy blocked
  by another copy's data lease names that cause. Every quit request waits for
  pending delivery again; no flag may persist across a cancelled quit. From 0.4.2, release preparation checks actual TextEdit
  and Chrome delivery for both saved insertion preferences, with fixture binary
  hashes matching the committed Debug build. Follow the Local releases policy
  when acceptance is unavailable: publish with a commit-bound unverified reason
  and report it afterward. See `docs/local-e2e.md`.
  Reject incomplete refinement responses and bound discovery, model loading and
  compatibility retries by one end-to-end refinement deadline.
- The LLM is best-effort. Any change to `DictationPipeline` must keep the fallback:
  LLM error or timeout still inserts the raw transcript.
- Read app context defaults to off when no choice is saved; preserve saved on/off
  choices. Reading context can turn dictation into selected-text editing, so it
  requires opt-in. Browser URL metadata is captured as HTTP(S) origin only: scheme,
  host and explicit port, with no userinfo, path, query or fragment. New prompts
  and history receive that minimized value; do not rewrite existing history.
  Cursor insertion remains independent of this setting. The Edit shortcut is the
  one explicit exception: pressing it reads only the focused selection, once,
  through `AppContextReader.readSelection` (no title, URL or nearby text).
- Sensitive provider requests use `ProviderTransport`: no persistent cache, cookies
  or credential storage, and redirects stay on the original scheme, normalized
  host and effective port. Injected test sessions remain supported. Anonymous model
  downloads keep their separate CDN-capable transport.
- `DictionaryPostProcessor.apply` runs last, after the LLM. Do not move it.
- Refinement output passes `RefinementFidelity` before delivery. A result that
  repeats an earlier same-app dictation the new speech does not resemble, or that
  changes the transcript's language without a profile TASK or selected text (losing
  every kana or Hangul character, or gaining them from Chinese speech, losing or
  gaining another non-Latin script such as Cyrillic, Arabic or Devanagari, or a
  confident `NLLanguageRecognizer` change between Latin-script languages on 30 or
  more letters, closely related pairs exempt, counts), is discarded for the raw transcript and recorded as a refinement error. Prompts get
  recent dictations only as `<recent_terms>` (names and technical terms), never
  sentences: small models returned them instead of the new speech, and each copy
  fed the next prompt. Recent dictations include delivered ones the delivery tail
  has not saved yet; read saved rows off the main actor. The OUTPUT LANGUAGE rule is assembled in `PromptBuilder`
  code so edited base rules keep it. Base rules are language-neutral; per-language
  writing notes (Chinese, Japanese, Spanish) are assembled in code from
  `ASRConfig.refinementLanguages` (the selected speech language, or the first three
  preferred languages under Auto), computed the same way for the warm-up prefix and
  the final request. An unedited copy of an older default loads as the current
  default (`PromptBuilder.retiredDefaultBaseRulesDigests`); add the outgoing default's
  digest whenever the default changes. Whisper prompts carry only the script
  sentence; Whisper repeats bare dictionary terms on silence, so terms go only to
  dedicated keyword or context fields. Send that sentence only when Chinese is the
  selected speech language: under auto-detect it pulled English speech into a
  Chinese translation. `ChineseScriptConverter` still normalises the script; text
  containing kana is Japanese and is never converted.
- Secrets go in `Keychain` (service `com.lstudlo.app.airdraft`), never in UserDefaults,
  files, or logs.
- Passive credential access must never prompt. Badges use `Keychain.presence`;
  reads distinguish missing from denied/locked. Only a selected-key Allow access
  action may authorize reading. Use `CredentialEditor` for key fields; never report
  Saved after a failed write or migrate over an inaccessible current item.
  Non-interactive searches, updates and deletes carry an `LAContext` with
  `interactionNotAllowed`; adds carry none. Saved keys are file-based Keychain
  items, which ignore that context (FB16959400), so the scoped
  `SecKeychainSetUserInteractionAllowed` switch stays, called only from
  `CredentialStore.withInteraction`, where `@diagnose(DeprecatedDeclaration, as:
  ignored)` silences its warning; new deprecated calls elsewhere still warn. Leave
  `kSecUseDataProtectionKeychain` unset: moving would hide every saved key until a
  separate migration. Keep the real signed-identity fixture test in
  `scripts/verify-keychain.py` in the release gate, including its silent add/update
  step and no deprecation warning in `Keychain.swift`. See `docs/keychain-access.md`.
- The bundle ID and Keychain service are `com.lstudlo.app.airdraft`. Import legacy
  `com.lightiichen.transcribar` preferences and credentials without overwriting current
  values. Keep `Application Support/Transcribar` for existing models and history.
- `Packages/AirdraftCore` (library, CLI and tests), the app target and
  `AirdraftAppTests` build in Swift 6 language mode, so data races are compile
  errors; keep App sources at zero warnings in Debug and Release. AppKit, Carbon and
  CoreGraphics callbacks delivered on the main thread enter the main actor with
  `MainActor.assumeIsolated`; main-actor classes whose deinit touches non-Sendable
  observer or listener state use `isolated deinit`. Debug fixtures reach AppKit's
  informal accessibility attribute API only through `LegacyAccessibility`. Keep `@MainActor` on UI-facing classes and `Sendable` on
  protocol types. Prefer actors, `Mutex` and `sending` to locks. Every
  `@unchecked Sendable` or `nonisolated(unsafe)` names the lock or queue that
  confines its state. Engine actors publish non-Sendable SDK models into their own
  state instead of returning them from a `Task`; do not silence SDKs with
  `@preconcurrency`. Test fixtures share mutable state through `Locked`.
- Prompt changes bump `PromptBuilder.version` so history records stay comparable, and must be
  scored with `eval/run_correction_eval.py` on `correction_cases.json`, the held-out
  `holdout_cases.json` and the Spanish, Japanese and English `multilingual_cases.json`
  (LM Studio running). Do not ship a prompt that loses a held-out or multilingual case.
  Clean profiles and coding destinations must still correct recognition errors,
  including technical-name spelling and word boundaries. Preserve valid words and
  literal identifiers, commands and paths. Also run `context_correction_cases.json`
  when changing correction rules to check both corrections and literal preservation.
- Quitting must go through `ModelLifecycle.shutdown()` (unloads speech engines and the LM Studio
  instances the app used). Never return `.terminateLater` from the app delegate: it deadlocks.
- LLM behaviours are `RefinementProfile`s in `ProfileStore`, never hard-coded modes.
  Built-ins have stable ids and must stay resettable to `RefinementProfile.defaults`.
- Profiles shows the selected profile's Name, Dictation and Refine transcript card,
  then its speech model, Output (Send to, file and Send automatically) and
  instructions, then Profile by app (the switch, rule rows
  with a profile picker and remove button, and a Rule priority row holding the Add
  Rule menu of families, open apps and Choose App…; rules stay saved but hidden while
  the switch is off), with the shared base system prompt in a separate last section.
  Show a warning before opening its editor; keep edits in a draft until Save, with
  Cancel and Restore defaults. Use the existing `ProfileStore.baseRules` pipeline.
- Setup stays preset-driven: providers come from `EndpointPreset`, models from
  `ModelCatalog`. Do not add UI that requires typing a prompt to get a good result.

## Localization

The app ships the interface languages listed in `Config/languages.json`: English
(source), Spanish (es), Japanese (ja), Simplified Chinese (zh-Hans) and
Traditional Chinese (Taiwan, zh-Hant), following the macOS language (the
2026-10-25 interface-language decision; another language needs a new decision). `scripts/localization.py`, `LocalizationCatalogTests`, the
menu fixture and project.yml's `CFBundleLocalizations` follow that one list; add a
language there first, and to `InterfaceLanguage.shipped` (English first, then the
list's order and own names; `LocalizationCatalogTests` compares them).
Settings > Appearance > Language (AD-137) offers System Default plus each shipped
language by its own name, never translated. It stores the choice where macOS keeps
a per-app language, `AppleLanguages` in Airdraft's own preferences domain
(`InterfaceLanguageStore.Storage.appDomain`; System Settings' per-app choice writes
the same value, System Default removes it), never the global domain. The running
interface keeps its launch language: when the next launch would differ, the row
says so and offers Relaunch (`AppRelaunch`), which quits through the normal path
and opens the bundle again from `applicationWillTerminate` once the process is
gone, so the new copy never meets the old data lease; a cancelled quit relaunches
nothing. Isolated containers keep the choice in memory. The interface language
never changes speech: speech defaults, recommendations, refinement languages and
guards read the Mac's languages through `SystemLanguages.preferred`, never
`Locale.preferredLanguages`, which a per-app language narrows to that one language
(a `-AppleLanguages` launch argument still stands in for the Mac's languages). Strings live in String Catalogs: `Sources/App/Localizable.xcstrings`, `Sources/App/InfoPlist.xcstrings`
and AirdraftCore's `Resources/Localizable.xcstrings`. Write user-facing copy as
localizable literals: SwiftUI `Text`/`Button` literals, the shared components'
resource parameters, `String(localized:)` in the app and
`String(localized:, bundle: .module)` in AirdraftCore. Pass runtime text through
`detail:`, `.verbatim(_:)` or the `String` overloads. Wrap every branch of a
ternary explicitly: the compiler extracts only the first branch of a
`LocalizedStringResource` ternary. Never localize prompts, identifiers, persisted
values, model or provider names, or keycap names, and never compare against
displayed text. Native menus (`MenuBarExtra`, `NSHostingMenu`, app commands)
resolve SwiftUI keys with an empty environment locale, so their titles, items and
tooltips must be `String(localized:)` values; the menu fixture checks every
shipped language, including the Quit title, and fails when a requested language
falls back to another. `.verbatim(_:)` resolves in a table that never exists. Fixtures and accessibility identifiers stay English. Built-in profiles keep
their stored English names; the interface shows `RefinementProfile.displayName`
(History: `displayName(forSavedName:)`), localized until renamed. Renaming goes
through `ProfileStore.rename`, which sets `nameIsCustom` so a typed name (even
"Clean" in zh-Hant) shows as typed, and refuses a name another profile already
shows or stores. Modifier-only
shortcut labels localize only their side word through
`Hotkey.displayCaps`/`localizedDisplayString`; `keyCaps`/`displayString` stay
English for logs and matching. `Sources/App/AppShortcuts.xcstrings` holds App
Shortcut phrases, and every translation keeps `${applicationName}`. After a Debug
build, run `python3 scripts/localization.py sync`, translate new keys into every
shipped language and run `check`, which reports counts per language; `audit`
lists literals that bypass localization. `export <lang> <file>` writes a
language's untranslated keys with English, comments and es/ja/zh-Hant references;
`import <lang> <file> [--dry-run]` merges a translator's file after checking
placeholders, plural categories and `${applicationName}`. Keys whose only number
is a count may use CLDR plural variations; a plural form may spell out its number,
`other` keeps every argument. Spanish and Japanese glossaries are `Config/glossaries/<code>.json`
(`docs/localization.md` summarizes conventions); reuse their terms. Translate
zh-Hans directly with Mainland interface terms (设置, 默认, 菜单, 剪贴板, 快捷键,
复制, 润色 for refinement, 模式 for profile), never by converting zh-Hant; zh-Hant
uses Taiwan terms. Japanese uses モード for profile, matching 模式. Follow Apple's
macOS terminology in each language; Spanish uses tú and sentence case, Japanese
です／ます and 「」 quotes. The es and ja catalogs are machine-drafted and
render-reviewed and need native review. When one English word needs different translations in different places,
use a keyed entry with `defaultValue` (`TextSizeDefault`, `HomeSummaryHeading`,
`OnboardingStepShortcut`, `ModelTierVerified`/`ModelGroupVerified`,
`OnboardingStep*`). Layouts stretch to their translations: `SoftSegmentedPicker`'s
`width` is a minimum and segments share the widest label, `SoftPickerWidth.fitting`
sizes menus with a bounded set of choices, model table columns measure their
localized headers and values, soft buttons stay on one line and grow, and the
sidebar footer may take two lines; native menu titles still fit 190 points.
Shortcut instructions come only from `ShortcutCopy`, one complete sentence per
gesture (Hold, Press, and Hold with a trigger delay), with key caps as a `%@`
marker rendered by `KeyCapsSentenceView`; never compose a verb with fragments or
call `lowercased()`/`capitalized` on translated text. Numbers in user-facing copy
are arguments (`%lld`, plural variations where needed; memory through
`MemoryAmount`), never digits inside a string. Language names use `languageName`
inside sentences and `languageLabel` as standalone labels. `LocalizationCatalogTests` fails on missing,
stale or placeholder-mismatched entries in any shipped language and when the
bundle localizations differ from the list. Verify UI changes with the
`-AppleLanguages '(<code>)' -AppleLocale <locale>` renders of every shipped
language at Default and Larger text size (es_ES, ja_JP, zh_CN, zh_TW), including
Spanish at Larger. Letter-spacing applies only through
`scriptAwareTracking`, which tracks Latin, Greek and Cyrillic interface scripts only.
Right to left: no right-to-left language ships, but the interface stays ready for
one. When the bundle resolves a right-to-left language,
`AirdraftApp.registerInterfaceDirection` adds `AppleTextDirection` to the volatile
argument domain so AppKit mirrors even when only the app is set to that language.
Page structure mirrors (sidebar on the right; leading and trailing follow the
language). Light stays at the physical top left: draw lit gradient faces through
`physicalLight()` and physical offsets through `physicalOffset`, since SwiftUI
mirrors `.topLeading` gradients, `.offset(x:)` and custom paths while Canvas and
`SurfaceShadows` stay physical. The brand mark, app icon, Home waveform, HUD
capsule (Timer position names a physical side), audio bars and media transports
stay left to right; `SoftSlider(timeline: true)` marks a media position and value
sliders mirror. Key caps and shortcut strings keep modifier-first order (`KeyCaps`
lays out left to right; `localizedDisplayString` carries Unicode isolates). Use
forward/backward SF Symbol variants for direction. The window buttons keep their
16-point inset from the leading edge; renders assert it in both directions.
Read-only user content aligns by its own writing direction (`naturalAlignment(for:)`,
`WritingDirection` for AppKit text); editable fields keep AppKit's interface
alignment, since changing it while editing disturbs the field editor. Check RTL
readiness with `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`
English renders and the RTL cases of `verify-native-shadows.swift` and
`verify-sidebar-selection.swift`.
An unsaved Chinese script follows the first Chinese preferred language
(`ChineseScript.systemDefault`: Simplified with zh-CN, otherwise Traditional, and
Auto when no Chinese language is listed). Unsaved Apple Speech and live-preview
locales are Mandarin in that script when a Chinese language is listed, otherwise the
first preferred language with its region (`ASRConfig.systemAppleLocale`), which
`AppleSpeechTranscriber.resolvedLocale` resolves to a supported locale of the same
language; never rewrite saved choices. `ASRConfig.effectiveChineseScript` applies
the saved script only to Mandarin, Cantonese and Auto (Apple Speech: its locale);
every other selected speech language gets Auto for refinement, speech hints,
previews, media windows and the deterministic converter: under the Traditional rule
models translated Japanese into Chinese, kanji-only text has no kana for the
converter's guard, and no other language may receive a Chinese rule. Models shows
Chinese script only where it applies: Mandarin or Cantonese selected, or Auto for a
user with a Chinese language or a saved script. Apple Speech and live-preview
language pickers list every locale the OS supports, the user's languages first.

## Trigger Delay

Settings > Keyboard shortcuts owns Trigger Delay: 0–1000 ms, default 0,
with typed entry and 50 ms steps. Delay only shortcut starts; Toggle stop/cancel
and menu/App Intent actions stay immediate. Delayed shortcuts use the Accessibility
event tap instead of Carbon. Buffer ordinary shortcut key events and return them
in order on a short press; discard them only when the hold qualifies. Modifier
events pass through so normal chords remain usable. Typing another key, changing
the chord or setup, focus changes and monitor interruptions cancel pending holds.
Never start model loading, microphone capture or the HUD before the threshold.
Keep repeat, release, cancellation and persistence regressions in the core suite.
Profile and Edit shortcuts (AD-104) use the same delay and Hold/Toggle behavior.

## First-run setup

The optional, replayable onboarding has six steps on the sidebar's sliding
selection well: Welcome, Speech, Permissions, Shortcut, Try It and Ready. It
teaches non-technical users by doing; keep copy plain, name keys in words beside
their symbols (Control, Option) and never require typing a prompt or command.
It uses the normal permissions, model downloader, shortcut and dictation pipeline.
Persist skip separately from successful practice; typed text must never mark a
dictation complete, and only Try It's real pipeline delivery records success.
Existing setups do not open the flow automatically; replay after success starts
at Welcome. Old three-step progress migrates without reopening a skipped setup.
Speech offers On this Mac (recommended) or an online service with the user's key.
`LocalSpeechRecommendation.rules` is the data: one measured rule per primary system
language (choice above and at or below the 8 GB threshold, each alternative's Models
label, curated shortlist extras, whether the recommendation measured most accurate,
and its evidence); `unmeasuredRule(for:)` is the documented default. Chinese gets
Qwen3-ASR 1.7B with SenseVoice as the smaller choice, reversed at 8 GB or less;
English gets Parakeet TDT v2 with Qwen3-ASR 1.7B as the multilingual choice; Japanese
and Korean get Qwen3-ASR 1.7B with Whisper Large v3 Turbo as the lower-memory choice,
reversed at 8 GB or less (`eval/eja-asr`). Spanish, French, Portuguese, Russian,
Arabic, Hindi and Indonesian get Qwen3-ASR 1.7B (`eval/intl-asr`); at 8 GB or less
Spanish, French and Portuguese get Parakeet TDT v3 (Core ML), Russian GigaAM v3 E2E
RNN-T and Arabic and Indonesian Whisper Large v3 Turbo, each with Qwen3-ASR as the
alternative; Hindi keeps Qwen3-ASR on every Mac. Models that need an explicit speech
language (Canary, Cohere, Cohere Transcribe Arabic) are never first-run choices.
Other languages get Whisper Large v3 Turbo. Onboarding copy follows the rule's
labels and says "Most accurate for <language> in Airdraft's tests" only where the
rule records it. A new language needs a measured rule with its evidence and Core
tests. Never recommend Qwen3-ASR 0.6B as a lighter
default. Never recommend or shortlist SenseVoice Cantonese (the WSYue fine-tune);
the Chinese 8 GB choice is the original multilingual SenseVoice. Each choice shows its download size and a one-line trade-off.
Try It's read-aloud sentence follows the chosen speech language
(`PracticeSentence`), using the interface catalog's sentence when they match;
the Refinement Test sample follows the speech language too (`RefinementSample`).
A local download starts only from an explicit action, continues through later
steps with progress in the rail, and becomes the app default only when complete
while setup is open; Set Up Later discards that pending choice. Shortcut practice
lights the real key caps through local event monitors and pauses dictation through
`HotkeyService.rehearsing`, independent of the recorder's suspension; Try It also
pauses until the chosen engine is usable. Permissions preview only the microphone
dictation will use and update Accessibility by themselves. Practice temporarily
disables refinement and uses cursor insertion. It resolves the explicitly selected
app-default speech config through the shared AppSettings resolver, temporarily
ignoring saved profile bindings without mutating them. Restore returning users'
refinement and output settings on exit and after restart. Ready offers refinement
after practice: when the system reports Apple Intelligence available and it can
write the speech language (`AppleIntelligenceRefiner.unsupportedLanguageName`, the
selected language or the first preferred one under Auto), one click selects it
(Turn Off reverts it); otherwise explain the system reason or the unsupported
language plainly and keep Open Models (renders inject a language code with
`AIRDRAFT_RENDER_APPLE_INTELLIGENCE_UNSUPPORTED`); when Apple Intelligence is not enabled, offer Open System Settings
(Apple Intelligence & Siri) and keep setup open. When the saved active profile skips refinement (Verbatim), say
it keeps exact words and that the provider tidies profiles that refine; never
change profiles there. Never ask for a key, download or prompt there, and never replace
a returning user's other provider. `AppSettings.chooseRefinement` updates the
practice restore snapshot while practice runs. Availability uses
`AppleIntelligenceRefiner.availability`; renders and fixtures inject it with
`AIRDRAFT_RENDER_APPLE_INTELLIGENCE` (`onboarding-done-ai-*` render states; a
`-verbatim` suffix activates Verbatim). Home renders take `AIRDRAFT_RENDER_LICENSE`,
`AIRDRAFT_RENDER_PENDING_RECORDINGS` and `AIRDRAFT_RENDER_HISTORY_ERROR`.
Onboarding key caps size to their printed key name and never truncate it. Never execute a saved
script during practice: Try It hides Retry, and a retry while practice runs only
copies. Airdraft never pastes into itself, so Try It's editor receives practice
dictations through the pipeline's explicit `PracticeDeliveryTarget` channel
(`PracticeEditorChannel`), chosen at recording start only while Airdraft is active
and that editor has focus; only that delivery or a real paste elsewhere completes
the step. Outside practice a self-target stays copy-only. Renders and fixtures
never load models. Use isolated preview containers for the `onboarding-*` Debug
renders; `native-ui` walks the production flow with injected permissions and real
key events, and completes Try It through the real pipeline with fake capture and
speech (`AppContainer.DictationBoundary`). It never proves a real microphone or
shortcut.

## App telemetry

Opt-in anonymous product events and crash reports go to PostHog only from an
official, non-Debug build whose Info.plist carries a valid `AirdraftTelemetryToken`
(`phc_…`) and `AirdraftTelemetryHost` (US or EU ingestion origin), and only after
the user chose Share Anonymous Usage Data. Source, community, isolated, Sandbox and
Debug builds never construct the client (`TelemetryService` returns none under
`#if DEBUG`); prove this with the fake client, never by sending. `project.yml`
keeps both settings empty; only `release.py` passes them from
`scripts/telemetry-config.json` and verifies the built app, and `build-sandbox.py`
verifies their absence. Switching PostHog projects changes only that file; the app
shares the website's US project and tags every event `app=airdraft-mac`.
`AppSettings.telemetryConsent` (`telemetry.consent`, outside the `settings.` keys)
is undecided until answered. Ask with equal-weight Don’t Share and Share Anonymous
Usage Data on onboarding's Ready step and Home, listing what is and is never sent
with the privacy link; send nothing before an answer. Settings > Behavior holds the
switch. Granting opts in and reports the grant; denying reports the denial, then
flushes, opts out and closes. Launches without consent purge the SDK's local queue,
anonymous ID and pending crash report. Events are the closed `TelemetryEvent` enum
with enumerated or bucketed properties; `TelemetrySanitizer` validates them when
recorded and again in `beforeSend`, which also drops other SDK events and strips
device name, model, locale, time zone and similar SDK properties. Never send
transcripts, audio, vocabulary, prompts, app names, bundle IDs, window titles, URLs,
paths, endpoints, keys, custom model IDs or the Mac's name. Person profiles,
identify, lifecycle/screen events, flags, swizzling and GeoIP stay off. Recording
an event is fire-and-forget; pipeline behavior and timing must not change. Adding
an event updates the enum, sanitizer schema, tests, `docs/telemetry.md` and the
website privacy page together. IP discarding is a PostHog project setting; record
its verified state in the vault. See `docs/telemetry.md`.

## Official-build licensing

Self-built editions are fully unlocked and do not install paid official Sparkle
updates automatically. Official builds use a full-feature trial followed by a
Polar license-key activation. Start the trial only on explicit user action,
not during onboarding or model downloads. Gate new work through the pipeline's
access check; access checks join the launch receipt read (or start the same
passive read) and wait at most five seconds. `.loading` reports
`LicenseError.loading` and never presents the License sheet; never interrupt an active recording or lock history and recovery.
Keep license receipt writes explicitly non-interactive (`allowInteraction: false`).
Preserve activation IDs across key rotation; a rejected old key does not prove a
remote device was removed. Show the same anonymous device label in the app and
Polar portal. Keep license receipts in Keychain, use public customer-portal endpoints without
merchant tokens, validate organization/benefit/activation, and preserve verified
licenses during transient outages. Persist an uncertain activation before the
request; require customer-portal recovery instead of automatically retrying.
`release.py` requires `scripts/licensing-config.json` and verifies the embedded
configuration. Empty merchant IDs/URLs intentionally block official release.
Debug selects Polar Sandbox at compile time; Release selects production.
Never switch through launch arguments, preferences or a network-error fallback.
`scripts/licensing-sandbox.json` owns separate sandbox merchant IDs and URLs;
`moon run airdraft:build-sandbox` builds the official license flow as Debug.
Ordinary source builds remain community editions. Sandbox receipts use a separate
Keychain account; preserve the existing production account without migration.
Production checkout links allow HTTPS on `polar.sh` and `buy.polar.sh`; its portals
allow only `polar.sh`. Sandbox portals allow only `sandbox.polar.sh`; checkout also accepts the exact
`sandbox-api.polar.sh/v1/checkout-links/polar_cl_…/redirect` route generated by Polar.
Keep runtime and build validation aligned, verify the embedded environment, and
never release a Sandbox artifact. Record completed sandbox checkout separately
from production payment evidence; mocks do not prove either.
The `benefit_ids` allowlist contains the two configured plan benefits; Polar owns their device limits.
Validate membership before activation and persist the returned benefit ID;
never accept an arbitrary benefit from the same organization.
The License sheet is plain text: the sidebar's `SidebarBrandMark` at 32 points
(its `height` parameter; the sidebar size is unchanged) with Done, one headline,
one sentence, then the buttons that apply. Use one prominent action per state and
the shared soft button for the rest. Do not add cards, status dots, badges,
helper lines or footnotes. It is 440 points wide and as tall as its content,
scrolling only past 520 points. Put an unfinished activation's recovery before
trial, purchase and key entry. Sandbox builds keep the Sandbox tag and Test
Purchase.
See `docs/licensing.md`; dashboard setup, mocks and renders do not verify an actual purchase.

## Local releases

For an authorized end-to-end release request, use the project-local
`.agents/skills/push-and-release/SKILL.md`. It coordinates tests, scoped repairs,
commits, committed-source E2E, push and published-artifact verification through
the existing scripts. Creating, editing or inspecting the skill does not run a release.

When the user says "push and release", invoke that skill and execute through
publication without another approval request or verification blocker unless the
user explicitly specifies one. Missing permissions, hardware, services or other
unverified checks do not suspend the release. Record their status and reason,
complete the available work, then notify the user after pushing and releasing.
Fix actionable failures and continue; never label failed or missing checks as passed.
For incomplete live insertion acceptance, use `--unverified-live-insertion REASON`
as documented in `docs/updates.md`, without asking for additional permission.

Choose the display version before release preparation. Below 1.0, substantial
features or broad UI/workflow redesigns increment the minor version and reset the
patch; focused fixes increment the patch. Reserve an unchanged display version
for rebuilds or packaging-only revisions. The Git-derived build number never
substitutes for a product-version bump. Update `project.yml`, run XcodeGen and
commit the regenerated `Sources/App/Info.plist`. See the version policy in
`docs/updates.md`; the provider, recovery and interface overhaul is 0.2.0.
Apple Intelligence, saved audio, live preview and dictation automation are 0.3.0.
Guided onboarding and official-build licensing are 0.4.0.
Profiles by app, live text from local models, Simplified Chinese and the
English/Japanese/Korean recommendations are 0.12.0.
Spanish and Japanese interfaces, language-neutral internationalization (defaults,
prompts, guards, layouts that fit translations, right-to-left readiness) and the
measured per-language speech recommendations are 0.14.0.
Official-build opt-in usage data and crash reports are 0.13.0.
Send after pasting, flagged words, profile destinations and the profile and
Edit shortcuts are 0.15.0.
Live text styles, lines and size, the Live text model badge and the single
Speech models table are 0.16.0.
Live text animations and live text that keeps scrolling are 0.17.0.
The Transcribe page (formerly Meetings) is 0.18.0.
Live text that becomes the transcript when it matches the model, and cloud live
text through providers' real-time APIs, are 0.19.0.
The in-app interface language, Disco intensity and the 600-second default
recording limit are 0.20.0.

When API-key or credential testing is explicitly excluded, prepare with
`--test-scope credential-free` and push with
`AIRDRAFT_RELEASE_TEST_SCOPE=credential-free`. The release records its exact test
scope and exclusions in `release.json` and release notes. This replaces only
credential/cloud tests and the cross-identity Keychain fixture with the local
allowlist; signing, licensing configuration, updater installation, packaging and
downloaded-artifact checks remain required. Updater fixtures use disposable
Sparkle seeds through `--ephemeral-key`; packaging still uses the existing signing key.

Never override release signing with `CODE_SIGN_IDENTITY=-`. macOS permissions
require a stable certificate-bound designated requirement; Sparkle signatures do
not provide that identity. Keep `scripts/release-signing.json` pinned. Certificate
or team changes need an explicit migration review, not an automatic fallback.
Verify the app inside the DMG and run the real updater identity checks. Do not
claim that signing tests prove permission continuity on an untested second Mac.
Keep Hardened Runtime on every build we sign with a team and ship: an unsandboxed
app holding Microphone and Accessibility access must not load injected code.
`Config/Signing.xcconfig` derives `ENABLE_HARDENED_RUNTIME` from the team (YES with
one, NO for team-less ad-hoc builds, whose own frameworks library validation would
refuse); never set it in `project.yml`. Ad-hoc contributor builds are
development-only. Releases pass `ENABLE_HARDENED_RUNTIME=YES` and verify the flag;
`scripts/verify-adhoc-launch.py` must launch a fresh ad-hoc clone. Renders and self-tests compile
only into Debug builds; never ship an environment- or argument-triggered path.

The DMG installer uses `scripts/build-dmg.py` through `package-update.py`.
Keep its locked `uv` dependencies, `scripts/dmg-layout.json` and the code-rendered
Retina artwork in `scripts/render-dmg-background.swift` together. Reuse the
outlined wordmark and silver capsule geometry. Inspect the actual mounted Finder
window, including installation copy when path/status bars remain visible. Never
add FinderInfo to the signed app to hide its extension; strict signing rejects
it. See `docs/installer/DESIGN.md` and `docs/updates.md` for the local preview path.

## Validation

Run the smallest set of checks that covers the change, in one batched pass;
never repeat checks for areas the change did not touch. `release.py` runs
everything, including the full-length tests (`AIRDRAFT_LONG_TESTS=1`).

| Change | Run |
| --- | --- |
| Core or App logic | The affected test classes while working; `xcodebuild … test` once before committing |
| App view or layout | Build; light/dark renders of the touched pages (`--render-window <page>`). Add a11y-audit only when controls, names or focus change, and Larger text only when copy length changes |
| Copy or localization | `localization.py check`; one render in each affected language |
| Delivery or insertion | `TextDeliveryRegressionTests`, then `verify-insertion-regressions.py` on that xcresult |
| A component with its own script (header blur, shadows, sidebar selection, download progress, app icons, data-cleanup quit, menu, native UI, settings search, models performance, History navigation) | That script or fixture, only when the component changes |
| Website only | `pnpm check:marketing`, `pnpm build:marketing`, one desktop and one phone browser pass |
| Docs or vault only | `check-vault.py` when the vault changed; nothing else |

Tests use injected time instead of waiting: `EngineFactory`'s `now`,
`DictationPipeline.recordingLimitSeconds` and `resetDelayScale`,
`TextInserter`'s delays and `HUDPreviewNotice`'s `sleep`. A timer-driven type
takes an injected sleep, and its tests drive a manual clock; never assert after
a real sleep that races a real deadline (they pass locally and fail on slower
CI runners). Where a real delay remains, leave a margin of seconds, not
milliseconds, between the action and the deadline. A unit test that sleeps longer than a second needs a
stated reason, and tests that model hours of audio shorten unless
`LongTests.enabled`. Do not add a UI-operation fixture for behavior a logic test
can cover.
Both test bundles run in parallel test clones (`parallelizable` in `project.yml`,
`-parallel-testing-enabled YES` in the scripts), so every test owns its fixtures:
temporary directories, defaults suites, pasteboards and servers, never shared
paths or global state another test can see. Prefer one scenario test with
independent phases over many near-identical methods; keep the method names that
scripts and docs cite.

- App icons: after a Debug build, run `python3 scripts/verify-app-icons.py --app <Debug.app>`.
  It checks real AppKit icon images, theme changes, independent preferences and
  restart/Auto resolution using a disposable settings suite. Inspect the native
  Settings pickers and light/dark renders as well.
- Vault: run `python3 scripts/check-vault.py` after writing to the Obsidian vault and
  `python3 -B scripts/test-vault-check.py` after changing `scripts/vault_check.py`.
- For a repeated insertion bug, verify the actual running build with
  `scripts/verify-running-app.py --app <intended-app>` before claiming a fix.
  On-disk Info.plist/build success cannot prove an old process loaded new code.
  Quit duplicate/stale copies normally, preserve recovery prompts, relaunch and
  compare loaded executable/core/UI UUIDs. A release does not update running Debug.
  Debug may load Core from Xcode's adjacent PackageFrameworks directory; require
  its loaded UUID to match the embedded framework instead of rejecting the path.
  Run the `LocalE2E insert` fixture against a disposable external editor field;
  require actual resulting text, not only a posted key event or simulated AX result.
  Missing Accessibility access blocks that live check and must remain explicit.
- Credential-free checks: `pnpm test:local` excludes API-key and cloud-provider
  suites, including fake keys. It includes onboarding and isolated public licensing
  fixtures. Run `python3 scripts/verify-local-e2e-errors.py --app <Debug.app>` after
  changing the E2E harness: failed actions and failed report writes must exit nonzero.
  It also runs the whole `AirdraftAppTests` target; the runner requires executed,
  passing App cases (`app-tests.json`).
- Tests: `xcodebuild -project airdraft.xcodeproj -scheme airdraft -configuration Debug -skipPackagePluginValidation -skipMacroValidation test`
  (runs `AirdraftCoreTests` and `AirdraftAppTests` inside the app's DerivedData). `cd Packages/AirdraftCore && swift test` also
  works but builds a second ~6 GB tree in `Packages/AirdraftCore/.build`.
- Build: the same command with `build`. Do not pass `-derivedDataPath`: a build tree inside the
  repo duplicates Xcode's and is how the repo grew to 10 GB.
- Shadow direction: compile `Sources/App/Views/SurfaceShadows.swift` with
  `scripts/verify-native-shadows.swift` using `xcrun swiftc`, then run the result.
  It checks raised, inset and translucent inset directions in both appearances
  through NSHostingView bitmap capture and ImageRenderer, and keeps translucent
  inner shadows inside their shape. `--legacy` reproduces the old outer-shadow failure.
- Sidebar selection: compile `NavigationStyle.swift`, `NeumorphicSurface.swift` and
  `SurfaceShadows.swift` with `scripts/verify-sidebar-selection.swift`, then run it.
  It captures its own window through the compositor and asserts that the well
  passes through intermediate positions, across a group gap, and settles on the row,
  with the icon island absent when the well settles, then on the new row's icon,
  gone from the old one and its shade clipped inside the well.
- Header blur: compile `Sources/App/Views/ProgressiveHeaderBlur.swift` with
  `scripts/verify-progressive-header.swift` using `xcrun swiftc`, then run it.
  Use `--live` for the compositor fixture: 13-point text must remain recognizable
  but visibly softened at the bottom of the header, then blur upward while
  its foreground label stays sharp. Do not judge onset using only broad stripes.
  `--island <png>` captures the fixture's own window through the compositor, which
  needs no Screen Recording access, and asserts the island clip, chrome-free blur
  and sharp content below the header; look at the saved PNG as well.
- Download progress: `python3 scripts/verify-download-progress.py --output <dir>`
  checks live fill interpolation, paused transfers, stage changes and the Reduce
  Motion branch in both appearances, using the production view in a disposable window.
- Accessibility (Debug): `airdraft --e2e-local <disposable-dir> --render-window a11y-audit <out>`
  walks the real AX tree of every page, overlay, onboarding step, License and the
  meeting transcript editor at Default and Larger text sizes (the Larger pass sets
  the preview settings' text size) and fails on unnamed or symbol-named controls,
  unnamed images, role-less elements, pickers without names and values, and missing
  headings/labels. Expected labels come from the string catalogs, so it runs in
  every shipped language. Renders accept
  `AIRDRAFT_RENDER_TEXT_SIZE=standard|large|larger`, `AIRDRAFT_RENDER_CONTRAST=1`,
  `AIRDRAFT_RENDER_REDUCE_MOTION=1` and `AIRDRAFT_RENDER_REDUCE_TRANSPARENCY=1`.
  A live VoiceOver walkthrough remains manual.
- Menu (Debug): `airdraft --e2e-local <disposable-dir> --render-window menu <out>`
  verifies the production native menu, provider/profile state, width fitting,
  processing and retained-recording actions; captures light/dark menu windows.
- UI (Debug builds): `airdraft --render-window all <dir>` and `--render-hud <png>`, then look at the PNGs.
  `airdraft --e2e-local <disposable-dir> --render-window settings-search <dir>`
  exercises Settings search, conditional controls, result scrolling,
  cancellation and idle scroll work in live light/dark fixture windows.
  `transcribe --e2e-recording-ms <0...120000>` replays a supplied file through
  production recording/preparation/stop with a silent recorder. It requires
  isolated local models, no context/preview and disabled insertion. Report its
  stop-to-outcome endpoint after history separately from confirmed delivery;
  it never proves microphone capture or external-editor insertion.
  Views check `RenderMode`, never process arguments or `AIRDRAFT_RENDER_*` directly.
  `AIRDRAFT_RENDER_WIDTH` / `AIRDRAFT_RENDER_HEIGHT` set the window size (use a tall height to
  see lower sections); `AIRDRAFT_RENDER_EMPTY_HISTORY=1` shows Home's first-run state.
  `profiles-by-app` and `home-by-app` render app rules; `home-by-app` takes
  `AIRDRAFT_RENDER_RULE_SPEECH=<kind>[:model]` for a blocked rule's speech model.
  `AIRDRAFT_RENDER_SIDEBAR_COLLAPSED=1` renders the compact icon rail; compare
  it with the expanded sidebar at the same window height.
  `AIRDRAFT_RENDER_INTERFACE_LANGUAGE=<code>` chooses a next-launch language in the
  isolated store, so Settings shows the Language row's Relaunch state.
  `AIRDRAFT_RENDER_HUD_DISCO=1` with `AIRDRAFT_RENDER_HUD_DISCO_INTENSITY=<0…1>`
  renders the recording-window previews at that Disco intensity.
  `AIRDRAFT_RENDER_SAMPLE_DATA=1` uses isolated preview records. Verify the
  progressive header blur in a live window; bitmap captures do not reproduce
  compositor backdrop blur. Check the full-height radius ramp, not just opacity.
  `AIRDRAFT_RENDER_VERIFY_NAVIGATION=1` with `--render-window history <dir>` checks
  bottom-to-top timeline synchronization, including an unchanged first active
  record, and pointer focus dismissal versus editing selection.
  `AIRDRAFT_RENDER_HISTORY_COUNT=2000` uses an isolated large-history fixture and
  checks pagination, search, native text sizing and scroll work. Combine it with
  navigation verification to assert zero regrouping and bounded card updates
  during scrolling; see `docs/history-performance.md`. Use enough
  history to overflow both columns; it does not modify records.
- Interactive `--preview-profiles` windows must call `startAppearanceUpdates()` so
  Auto, Light and Dark affect the window without starting hotkeys, models or the updater.
- Xcode previews (`#Preview`, Debug only) are for fast iteration, not a substitute for the renders
  above. Build them from `Debug/PreviewData.swift` (throwaway history, settings suite and data
  directory); never from `AppContainer.shared`, which would read the user's real data.
- Pipeline (Debug builds): launch with `AIRDRAFT_SELFTEST=<wav>` (or `mic`, `lifecycle`, `window`), optionally
  `AIRDRAFT_SELFTEST_ASR=<ASRProviderKind raw value>[:model]` (e.g. `senseVoice`, `qwen3:<id>`), and read
  `/usr/bin/log show --predicate 'subsystem == "com.lightiichen.airdraft"'`.
  Synthetic key events and screenshots from this shell do not work (no Accessibility /
  Screen Recording); do not rely on them. The user presses the real shortcut.
- Use `/usr/bin/log`, not `log`: zsh has a `log` builtin.
- `AVAudioEngineConfigurationChange` is not proof of a disconnected microphone:
  output changes can trigger it too. Check the actual input route and format,
  recover the same input without clearing captured samples, and leave the Core
  Audio notification queue before engine operations. The microphone self-test
  must check interruption callbacks and resumed capture, not sample count alone.
- Source builds sign ad-hoc through `Config/Signing.xcconfig` unless the git-ignored
  `Config/Local.xcconfig` names a team (`Config/Local.xcconfig.example`).
  `scripts/generate-project.py` creates it for the pinned team when that certificate
  is installed; keep running it in new worktrees so Debug builds keep a stable
  identity and Accessibility grants. Never put a team in `project.yml`. Release
  builds pass the pinned identity, team and Hardened Runtime from
  `scripts/release-signing.json` on the command line and never read the local file.
  `AIRDRAFT_LOCAL_SIGNING=ad-hoc` reproduces a contributor build;
  `python3 scripts/verify-adhoc-launch.py` builds one in a disposable clone and
  launches it (CI runs it with `--app` on its ad-hoc build).
- MLX (Qwen3-ASR, Cohere) only works in Xcode-built products; `swift build` has no Metal library.
- sherpa-onnx (FireRedASR2, SenseVoice) is linked through `Packages/SherpaOnnxKit`, whose
  `Vendor/` xcframeworks are generated by `scripts/make-sherpa-xcframeworks.sh` (run once after
  clone; git-ignored). Preparation verifies committed native input hashes before
  unpacking and records the derived tree. Release export must verify the input
  identities, recipe and every generated file with `scripts/native_inputs.py`.
  Never generate a trusted manifest from an unverified Vendor tree. All three
  fixed Sherpa model archives use the existing hash-before-unpack path.
  Do not depend on the upstream sherpa-onnx package directly: its static
  `.framework` bundles get embedded by Xcode and break code signing. `SherpaTranscriber` calls
  the C API directly; do not re-add the 2,300-line upstream Swift wrapper.
  Keep the `AirdraftCore` product dynamic and explicitly embedded in `project.yml` so its
  engines stay out of Xcode's preview JIT linker. Linking them there causes duplicate Sherpa symbols
  and can exceed the preview launch deadline. Use normal Canvas execution; legacy previews
  can drop the installed Metal toolchain from dependency builds on Xcode 27.
- speech-swift has no releases and is pinned to a revision in `Packages/AirdraftCore/Package.swift`.
  Move the pin deliberately and re-run the Qwen3 and Cohere self-tests.
- Speech engines kept on purpose: Parakeet TDT 0.6B v3 INT8, Qwen3-ASR 1.7B/0.6B, FireRedASR2-AED, Cohere Transcribe 2B,
  SenseVoice-small (original) and SenseVoice Cantonese (retired), Whisper Large v3, standard and compressed Turbo, Apple SpeechAnalyzer. Cloud APIs are Soniox v5, Groq Turbo,
  ElevenLabs Scribe v2, OpenAI GPT-Transcribe, Deepgram Nova-3, AssemblyAI Universal-3.5 Pro
  and Universal-3.6 Pro batch preview (`universal-3-6-pro-preview`),
  Cartesia Ink-Whisper, Speechmatics Enhanced, xAI Grok Voice Transcribe 2.0,
  Mistral Voxtral Mini Transcribe and Gemini 3.5 Transcribe, plus OpenRouter
  (see `docs/transcription-apis.md`). Each direct provider uses its native speech API.
  Cartesia file transcription requires an explicit language. AssemblyAI requests
  include only the selected batch model; never send the 3.6 streaming ID to the
  batch endpoint or silently replace it with 3.5 Pro. Batch jobs/files are
  deleted on success, failure and cancellation when reachable; never send Gemini
  speech through a chat prompt or enable its smart mode as implicit refinement.
  Core ML speech choices use `CoreMLSpeechModelCatalog` / `FluidAudioTranscriber`
  and FluidAudio's explicit `AsrModels.loadLocal` only; SDK auto-download/recovery is
  forbidden. Redux uses the upstream CPU/GPU encoder path to avoid its lengthy
  first ANE compile. Every component is pinned and verified. Decode windows are at most
  15 seconds, with exact variant/precision, European/English/Japanese language rules
  and session-owned model retention through unload/cancel. Orukeet reuses the verified
  sherpa-onnx transducer path. Distil-Whisper is English only (including Auto), uses
  `distil-whisper_` directories and shares the v3 tokenizer and native word timing.
  GGUF local choices are bundled in `local-gguf-models.json` and routed through
  `GGUFModelCatalog` / `GGUFTranscriber` with the pinned transcribe.cpp XCFramework.
  Show runtime/quantization in local rows and provider/runtime in profile choices
  so same-family variants stay distinguishable. Each artifact uses an immutable Hub
  revision, byte size and SHA-256. Verify both
  cached and new bytes before installation; failed or cancelled downloads keep the
  incomplete marker. Never copy a competitor's benchmark score into app ratings.
  `BundledModelCatalog` reviews every GGUF and Core ML catalogue entry (safe IDs and
  paths, owner/repo, 40-hex revision, positive sizes, SHA-256, languages, a buildable
  URL). A missing or invalid bundled catalogue, or one failing entry, makes that
  catalogue unavailable with a reinstall message in downloads, the recording check
  and Home's Speech row instead of crashing; nothing from it is downloaded and other
  engines keep working.
  Decode on a worker with one native compute operation per loaded model; retain the
  model until sessions end, signal cancellation through the abort callback and reject
  aborted/truncated prefixes. Native diarization is off; Transcribe owns SpeakerKit
  and reports segment timing for GGUF models. Auto requires the exact model's language
  policy, including explicit source language for Canary, Cohere and Granite.
  Whisper choices are defined by `WhisperModelVariant`; keep Models, Profiles, language
  validation and Transcribe aligned. Retain existing model selections and exact engine IDs.
  Whisper decodes sequential windows of at most 25 seconds, disables the SDK's
  one-second tail clipping, and preserves cancellation/errors across every chunk.
  Check both sub-second speech and final words beyond 30 seconds after changes.
  Both synchronous and async audio chunk decoders check cancellation before and
  after each chunk, so cancelled recordings never continue into later windows.
  Apple Speech cancellation must cancel its result collector and explicitly finish
  the analyzer, so cancelled inference releases the engine lease without waiting
  for final results from a stopped input sequence.

## Production gate evidence

Release preparation runs `scripts/test-prompt-gate.py` and `scripts/verify-prompt.py`
against the committed export before packaging. It also runs
`test-acknowledgements.py` and `acknowledgements.py check` against the release's
SourcePackages. Keep `eval/results/prompt-validation.json`
bound to the current prompt assembly and all four evaluation datasets; no per-case
regressions are accepted, and every context-correction run must pass. Rebuild the CLI before collecting fresh three-run reports.
Artifact signing checks require Hardened Runtime as well as the pinned identity.
Public distribution additionally requires `scripts/verify-public-distribution.py`
on the final app and DMG. Do not relabel Apple Development builds as public-ready
or change the pinned identity without the explicit migration review.

## Dictation automation

App Intents control the existing pipeline in the background. Start must await
actual capture, with cancellation and a bounded startup wait. Reject commands
after approved shutdown. Never activate the app on successful automation.
Snapshot the output destination, script path and insertion method when recording
starts; keep that snapshot through speech recovery. Scripts receive only the
final text after conversion and dictionary processing, as literal UTF-8 stdin
through `CLIProcess`, without shell interpolation. Bound pipes and execution.
Never retry uncertain delivery or fall back to pasting. Keep final text and
accurate delivery status in history. Review-only transcription and disabled
insertion must never execute scripts. See `docs/automation.md`.

## Send after pasting, profile destinations and shortcuts

AD-104 (`docs/automation.md`). Every part is off or unset by default and never
part of first-run setup or practice (`AppSettings.effectiveProfile` clears a
profile's output and send). Settings, profile output and the request are captured
at recording start (`RecordingSnapshot.request`, `.speed`, `OutputSnapshot`).
- Return is pressed once, only after a paste the original field confirmed and
  while focus is still there (`TextInserter.pressReturn`, no modifier flags,
  never retried). Shift pressed while recording toggles a lock (`sendLocked`,
  polled modifier flags) unless the shortcut uses Shift; a profile's
  `sendsAutomatically` sends to AI chats and agents only. `sendDecision` is the
  only place the rules live: never automatic in browsers (web apps with their
  own bundle IDs count as apps), email, work chat or personal messaging; email
  never sends; editors that cannot confirm send only with a Shift lock and
  `sendsWhenUnconfirmed`; retries, edits and practice never send. The cancel
  window counts from the release and overlaps processing (1 s Shift, 0.5 s
  automatic); Esc during it keeps the paste and sends nothing.
- `HighRiskFlags` (version 0, no engine confidence) flags numbers and negations
  refinement changed, names it introduced, code-like words not in Vocabulary
  (`identifiersHoldSend`) and speech-guard corrections. Holding flags keep the
  text pasted and unsent; the HUD lists at most three snippets
  (`FlagHandling.showAndWait`) or only says it was not sent. Ordinary cleanup
  never flags. History stores `flags` (JSON), `sendRequest` and `submitted`
  (migration `v9-speed`); edits and practice store no flags.
- A profile's `output` overrides Output and automation: Insert at Cursor, Copy
  Only or Add to File (`FileAppendDelivery`: `{date}`, `{time}`, `{app}` only,
  coordinated writes, one line per dictation; a missing folder blocks recording
  before capture). History stores `copy` and `file`; both count as delivered
  when they succeed.
- At most two profile shortcuts and one Edit shortcut (`HotkeyService.applyExtras`,
  one Carbon or event-tap channel each; duplicates are refused). A profile
  shortcut replaces app rules and the captured-destination follow. The Edit
  shortcut needs refinement, refuses to open the microphone without a selection,
  edits with Clean's instructions when the profile skips refinement, always
  replaces the selection at the cursor and never sends or flags.
- `SpeedMetricsStore` keeps `speed-metrics.json` beside History: accepted and
  ignored presses, capture timing by input transport and cursor delivery outcomes
  per destination bundle ID. Counts only, never sent; History cleanup and Reset
  remove it. `scripts/speed-metrics.py` and `eval/speed/` read copies only.

## Live transcription preview

Settings > Live preview chooses a Preview source (`LivePreviewSource`): Apple
Speech (the default) or Selected speech model. AD-123 (the 2026-10-28 decision):
live text that is expected to equal the recording model's own output becomes the
transcript that refinement, the dictionary and delivery receive; any other live
text is display only and the recording is transcribed again after release. A
session that matches conforms to `LiveTranscriptSession` with
`reusesForTranscript`; release hands it to processing (`takeLiveTranscript`), and
`finishTranscript(capture:)` returns the transcript for the whole capture or nil
(failed, cancelled, missed audio, other model), when `transcribe` runs the normal
final path on the full capture. Kept-audio retries always use the final path.
Matching sessions: local Parakeet, SenseVoice and Orukeet with the model source
(`ModelPreviewFinals`: committed windows decode through
`EngineFactory.transcribeLiveSegment`, the guarded final path at preview priority,
only once the uncommitted audio exceeds a full `SherpaTranscriber.chunkSeconds`
window plus `AudioChunker.minimumTailSeconds`, cutting where `AudioChunker.split`
cuts, so segments equal the final path's; the tail after the last commit is decoded
at release; such sessions never drop audio); Apple Speech when it is the recording's
model, with either source in that model's own locale
(`SpeechPreview.startTranscript`: final transcription's `.transcription` options
plus volatile reporting, never `fastResults`; the capture supplies audio still in
flight and the analyzer finalizes through the end); and cloud providers whose
real-time model is the batch model with the same options
(`StreamingSpeechProvider.matchesBatchModel`). Apple Speech preview with another
recording model stays display only, analyzing on macOS 26+ in its own language
(independent of the selected final ASR provider; Models shows its language section
only while it is the source) with `.progressiveTranscription`. Install assets
explicitly in Models through `ModelDownloadStore`; preview never downloads. Bound
display-only audio queues and displayed text, replace provisional phrases, and
cancel without waiting before final ASR. Reject callbacks from old sessions.
Preview errors are nonfatal; display-only text never reaches history, refinement,
clipboard or scripts.
Cloud live text (`CloudLiveTranscriptSession`, `CloudStreaming`): with the model
source, a cloud model with a real-time adapter streams the recording to its
provider over a WebSocket on `ProviderTransport`'s ephemeral session (keys only in
headers or subprotocols, a short-lived token where a provider takes one in the URL;
`EngineFactory.cloudLiveTranscript` reads the key once, never interactively). Audio
is buffered until the connection opens; at release the rest of the capture and the
provider's end frames are sent and `CloudLiveTranscript.finishSeconds` (10 s) bounds
the wait for its final words. Matching adapters' final text is the transcript;
display-only adapters are cancelled at release and the batch request runs, so the
provider bills both, as Settings says. Settings names what live text costs: audio
streams to the provider while recording, including recordings that are then
cancelled. Groq, OpenRouter and custom endpoints have no live text. Adapters are
data in `ASR/Streaming/` with fake-socket tests; never reach a provider in tests.
Transcribe's live transcript stays on-device. Selected speech model with Whisper,
Qwen3-ASR, Cohere, FireRedASR2, GGUF or Core ML models opens no live-text window:
the HUD shows a one-line notice naming the
model without its runtime (`ModelSpeechPreview.recordingNotice`, no icon, shown
1.2 s by `HUDPreviewNotice`) above the capsule while recording continues, once per
profile and speech model until a recording previews or either changes, and Settings shows the active profile's
model with its readiness or reason and Open Models, reading installed state from
`SetupFacts`, and whether live text becomes the transcript or, for cloud
display-only adapters, is billed twice. The live-text window (`LivePreviewCard`) sits above the capsule and
follows `AppSettings.liveText` (`LiveTextOptions`, AD-108): Live text style (Glass,
the default 280-point translucent smoked glass of `HUDGlass`; Solid; light Frost;
a 420-point centered Subtitle bar; Text Only), Lines (1–4, default 2) and Live text
size (Small, Medium 12.5 pt default, Large), set in Settings > Live preview with
specimen tiles on a flat mid-gray backdrop. Reduce Transparency makes the
translucent styles opaque. It stays one line tall until text wraps, then shows the
newest lines with an older one fading under its top edge; one line keeps only the
newest words. Several lines lay out the whole text and show its bottom, so each new
line pushes the earlier ones up; never cap them with a line limit, which pins the
oldest lines and truncates the newest (AD-110). It never becomes a fixed-size box.
Text animation (`LiveTextOptions.reveal`: Fade default, Rise, Focus, Pop,
Typewriter, Wave, Glow, None) animates only newly arrived letters:
`LiveTextRevealTimeline` aligns each update with the last (grown, rewritten tail or
dropped head) and stamps only changed text, and `LiveTextRevealRenderer` draws each
letter's frame; its timeline stops once every letter settles. Reduce Motion turns
Rise, Pop and Wave into Fade; renders set `liveTextStill`. Settings shows a looping
specimen tile per effect that rests on the whole sentence in renders, inactive
windows and Reduce Motion. Dictation preview never loads, downloads or queues: it skips its tick while
any lease operation runs or waits, never rebuilds a recognizer, and every other
lease operation (load, final inference, media, unload) cancels it. Keep one decode
in flight, at least 1 s (or twice the last decode) between decodes, a 10 s window
committed at its quietest frame (display only), a 20 s buffer and 500 displayed characters
(1,500 in meetings); a decode slower than 3 s stops the preview with a message.
Shortcut release quiesces display-only local preview inside the existing 0.35 s
release grace, so final ASR runs once on the full capture; a matching session keeps
decoding through the grace instead. Transcribe recordings follow the same setting with a display-only
Live transcript row (six lines, no animation) fed by `MeetingPreviewMixer`; with
the model source, starting a recording prepares the installed model but never
downloads it, and the saved transcript still comes from Transcribe.

## Saved recording history

Audio retention is opt-in and independent of text history. `HistoryStore` owns
private UUID WAV sidecars and their SQLite references, including deletion,
retention and orphan cleanup. Audio assets have an independent lifetime: deleting
text must not orphan or remove retained recordings. Keep asset metadata free of
transcripts and app context, and clear links when audio is deleted. Recording
queries filter before pagination and count missing files in continuation offsets.
Export stored bytes under the deletion writer lease; exported copies are user-owned.
See `docs/recording-storage.md`. Preserve audio in pending-save recovery. Run full audio
cleanup at launch, hourly and after retention changes, never after each save; it
reloads audio views only when it changed something. Word totals sum the stored
`dictation.wordCount` (nullable; uncounted rows are counted from their text and
backfilled on open). `approximateWordCount`, also the refinement threshold, counts
Chinese and Japanese characters, Korean and alphabetic words by spaces, and Thai,
Lao, Khmer and Myanmar by dictionary word breaks. Playback has one owner
and stops when recording, deleting, leaving History or cleaning up audio. History
uses All/Recordings filters over one timeline; audio-only cards contain no deleted
transcript. Play/pause and seek share one transport, and only the selected progress
view observes its clock. Keep drag seeking fine enough for subsecond recordings;
keyboard seeking uses five-second steps. Verify using a silent injected transport,
never system playback. Save Audio uses NSSavePanel and preserves source bytes;
Show in Finder selects the managed file. Recording-only deletion preserves text.
Settings exposes four independent cleanup scopes through the shared
`DataCleanupCoordinator`. Preview errors retry the preview and must still reach
confirmation; only an already confirmed interrupted cleanup can resume directly.
A blocked data-directory copy shows Data Unavailable and can quit without an
unfinished-history warning for a database it never opened. Recovery and completed
reset sheets must permit AppKit termination; only actively running cleanup blocks
it. Verify with `python3 scripts/verify-data-cleanup-quit.py`, including `--legacy`
for the silent negative check.
Keep new work fenced while its durable journal is pending. Strip deleted content
from pending saves/recovery so retries cannot resurrect it. Require the app-data
lease and reject running sibling copies before deleting shared data. One app copy
holds an exclusive lifetime data lease; cleanup/reset never downgrades it. A
blocked copy cannot read or repair shared JSON or start work. Fresh cleanup
prepares remote media jobs and staging before journaling or deleting their IDs;
preparation failure preserves recovery data and leaves Settings usable.
Journaled retries repeat idempotent preparation while History is open, including
legacy journals, without repeating completed destructive phases. Failed preparation
with retained remote IDs exposes an explicit Repair Provider Access action using
the existing key editor. Keep the maintenance fence and mount no editor until asked.
Reset closes writers before removing app-owned files, removes provider keys without reading
values, preserves license/trial accounts, and targets only the current app's TCC
identity. Never promise to remove old path-based Accessibility entries. Tests use
disposable roots and fake credentials/permission steps. See `docs/data-cleanup.md`.
Retranscription uses a review-only pipeline policy, including explicit retries;
it never inserts, runs delivery scripts, replaces the original entry or adds to
history/statistics. Only the user's Copy action changes the clipboard.

## Recording and recovery invariants

Microphone dictation has a hard 600-second maximum. Keep Settings and persisted
settings within `SpeechInputLimits.recordingSecondsRange` (10–600 seconds), with the
600-second default (`SpeechInputLimits.defaultRecordingSeconds`; 300 before 0.20.0)
and saved shorter choices preserved. Clamp older saved values.
The recording timer stops capture and processes once at the effective limit;
shorter provider limits still apply. Recording limits and the kept-audio checks use
the recording snapshot's speech config. Imported audio keeps its provider input limits.

Check recording prerequisites before opening the microphone or prewarming a
refiner: permission, insertion access, selected device/channel, model installation
and readiness, endpoint validity, and required speech/refinement credentials.
Never prompt for a credential implicitly. A blocked attempt opens Home with an
actionable reason, even when the HUD is hidden. Open the microphone as soon as the
prerequisites pass and capture the insertion target and app context while audio
buffers; any other exit before the recording state stops capture and discards
that audio. A hold released after at least 0.3 s of captured audio while the
destination is still being captured defers the stop: once the destination
resolves, the speech is processed, trimmed to the release plus the 0.35 s grace.
A shorter tap, a release before capture starts, the toggle's second press and an
explicit cancel still cancel. The timer and limit count from capture start. Log
`pressToCaptureMs` (acceptance to first buffer). Refinement Off and Verbatim do not
require refinement credentials; unexpected refinement errors still preserve raw text.
Recording callbacks, release timers and asynchronous results belong to their session.
Keep failed speech audio in memory for explicit retry or discard, and warn before
quitting with recoverable audio or unsaved changes. A kept recording never blocks
new dictation: keep at most `DictationPipeline.maximumPendingRecordings` (3)
dictation recoveries or `maximumPendingRecordingSeconds` (900) of audio.
Each entry keeps its own failure text, insertion target and delivery policy; Home,
the menu and retry act on the newest entry by ID, and a failed retry keeps the
same entry as the newest. The bound is hard but shortens rather than blocks: a
new recording captures at most min(its effective limit, 900 s − kept audio), stops
there with a notice saying why (appended to the failure and its recovery issue
when speech recognition then fails), and is refused (message, Home) only when three
dictations are kept or less than 10 s remain. Never drop kept audio. A retry for a
caretless target copies with a notice instead of re-activating and pasting into
whatever that window shows now; caret targets are still verified by read-back.
A retry resolves its entry only once the result is delivered and held for History
(or set as the review outcome), so cancelling during refinement keeps the audio. Cancellation never discards kept audio; only Discard
Recording or audio cleanup does. History's failed review is a single separate
entry cleared when its sheet closes. Saving failures must stay visible.
Engine loading, inference and unloading share the factory lease. Downloads belong
to `ModelDownloadStore`, survive page navigation, and cannot select incomplete files.
A late download must not replace a newer provider choice. Release builds exclude
sample account data. Overlay focus stays inside the modal. Keyboard and VoiceOver
dismissal returns focus to its trigger; pointer dismissal clears it. Clicking
elsewhere clears stale control focus without interrupting clicks within an active
text editor. Cancel pending focus restoration when another pointer action begins.

Microphone choices exclude hidden Core Audio devices and temporary `CADefaultDeviceAggregate` bridges created by audio engines; user-created aggregate inputs remain available.

## Credential-free E2E verification

Use `scripts/test-local-e2e.py` for the explicit local-only test selection; the
whole core suite also includes API credential tests.
E2E and release runners use `-packageAuthorizationProvider netrc` so public
package downloads do not request Keychain access.
`LocalE2E` is Debug-only, uses a supplied data directory and optional
`AIRDRAFT_E2E_MODEL_ROOT`, and injects a nil credential reader.
GUI fixture bundles ending in `.e2e` must refuse startup
without `--e2e-local`, including automatic relaunch after a crash. Check the process
before UI operations. Never use normal preferences/history as E2E fixtures.
Use `scripts/verify-native-behaviors.py` and `scripts/verify-model-lifecycle.py`
for native regression fixtures. HUD fixtures run off-screen by default so
synthetic errors never interrupt normal use. Pass `--show-hud` only for an
intentional visual check; keep the default native layout, animation, timeout
and disposable-pasteboard assertions active. `verify-updater.py --ephemeral-key` uses a
disposable Sparkle seed and temporary update target. Record live, fixture,
source-review and unavailable coverage separately. See `docs/local-e2e.md`.
`--e2e-action capture-latency` is the one fixture that opens a real input: it reads
the microphone authorization status before any audio API, runs on the default
input only when access is already authorized (otherwise it reports unverified),
never requests access or switches devices, and keeps no audio or history.
`scripts/verify-insertion-matrix.py` is the optional live matrix across installed
editors (TextEdit, Chrome, Safari, Notes, VS Code, Slack, Warp, Zed, Ghostty,
Terminal, iTerm2), one case per saved method with a fresh marker. It first asks the
Debug app through `--e2e-action accessibility` (never prompting) whether it is
trusted and marks every case unverified otherwise. It reads both the older and the
macOS 27 `lsappinfo` formats, places the caret after the marker in opened documents
with `--e2e-insertion-place-caret` (a selection change on the disposable field
before capture, never a text write), and starts Terminal's receiver itself. Never launch Ghostty (or any terminal)
with a command: Ghostty asks the user to allow command execution, so its receiver
is a printed manual step. `--e2e-insertion-field` modes are `exact` (the release gate), `suffix`
(terminals) and `none` (self-drawing editors). Terminal receivers record bracketed
pastes and a pass needs exactly one. Self-drawing editors pass when sent
unverified, or confirmed when they publish a caret. It uses no AppleScript, System
Events or synthetic input. Release `--insertion-matrix` (or
`AIRDRAFT_INSERTION_MATRIX=1`) runs it before the unchanged four-case TextEdit/Chrome
gate; other editors only add `insertionMatrix` to `release.json` and the notes.
`.github/workflows/ci.yml` runs the unsigned build, `test-local-e2e.py
--unsigned`, `verify-adhoc-launch.py` and the release, insertion-regression,
live-insertion, parallel-work and acknowledgement script tests on the `xcode-27` GitHub image
with Xcode 27.0. `--unsigned` is CI-only; release builds keep the pinned identity.
The ad-hoc negative control (a Hardened Runtime re-signed copy that dyld must
refuse) is mandatory where a tiny ad-hoc + Hardened Runtime probe shows the host
enforces library validation; hosted VMs that do not record it as not applicable in
`negative-control.json`, a probe that disagrees with the app fails either way, and
`--require-library-validation` makes a non-enforcing host fail. CI verifies its
XcodeGen download against the release pin. Archives are cached, but the
Sherpa Vendor tree is rebuilt with hash checks each run. Lint workflows with
actionlint plus shellcheck; `.github/actionlint.yaml` declares new hosted labels.

## Media documents

Media import uses the independent document/job contracts in `docs/media-transcription.md`.
Keep audio ownership independent of text, preserve original words and times, and
checkpoint completed windows before continuing. Transcribe owns media import, saved
recordings, every transcript version and draft recovery; History owns dictations.
The page was Meetings before 0.18.0 (AD-113): user-facing copy says Transcribe,
Record Audio and recording, never meeting (Meeting Minutes is only a summary
template); internal types, the `meetings` route, identifiers, fixtures, telemetry
events and storage keep their meeting names.
Keep Transcribe after History and before the Models/Settings group, with Models first.
The user-facing page name is Settings; the internal configuration route stays stable.
Local media supports every `MediaConfiguration.LocalModel` with shared language
validation and explicit setup. Whisper retains native word times; other engines use
frame-aligned speaker segments and persist diarization before resumable ASR. Never
label segment times as word times or silently switch providers. Cloud IDs persist until scoped cleanup succeeds.
Share visual and accessibility recovery actions. Test with direct files or injected
PCM and silent transports; never make the system play sound for verification.
A Transcribe card shows its title, one metadata line (date, duration, engine and
transcript count), a status dot and an actions menu, then at most a two-line
preview and one player row ending in the single next step: Transcribe, Resume or
Open Transcript. Versions, Save Audio, Show in Finder and deletion stay in the
menu. New transcripts take the library's default title; the date stays in the
metadata. The transcript editor keeps a fixed header (title, metadata, playback,
version, Copy, Export) and footer (Delete, Summarize, Save Changes) around
Summary, Speakers and a single Transcript card, and never opens with a focused title.
Renaming a speaker renames every passage of that speaker ID in Edited, Original
and exports without touching original words or assignments; a cleared name shows
Speaker N. Each Speakers row offers a Recent menu from `SpeakerNameLibrary` (a
`speakerName` table in history.sqlite): names only, matched ignoring case, width and
accents, with last-used times, capped at 100 names of up to 60 characters, never
transcript text, speaker IDs or voice embeddings. Save Changes records typed
single-line names except default labels; a failed name write keeps the save and
shows a notice. Recent omits names other speakers in the transcript already use and
offers Forget Recent Names. Remove History and Remove History and Audio Files delete
the names and Reset removes their database; audio-only cleanup keeps them.
Summarize is a menu of four `MeetingSummaryTemplate`s (Brief Summary, Action Items,
Decisions & Follow-ups, Meeting Minutes); the last choice is checked and saved in
`AppSettings.meetingSummaryTemplate`, and a confirmation names the template and
says when it replaces the current summary. Template names are localized; prompts
stay English, ask for plain text in the transcript's own languages and never invent
owners, dates or names. Keep the 8,000-character sections without a final merge
request. Each summary records its template beside the Summary heading. A cancelled,
failed or empty response leaves the transcript and earlier summary unchanged.

## Recording capture (Transcribe)

Transcribe's audio recording uses ScreenCaptureKit audio/microphone outputs with no screen
frames or playback. Preserve a common timestamp axis, separate raw source PCM,
bounded conversion and recoverable drafts. Finalize new and recovered recordings
as 16 kHz stereo WAVs with the same microphone-plus-app mix in both channels.
Divide the source sum by the number of source files containing samples: average
two sources for headroom, and keep a single source's level when the other is
missing. Previously saved WAVs retain their bytes; Save Audio copies them without
remixing. Drain converters before publishing an asset; never discard captured
data on failed finalization.

App audio opens a 320-point chooser with 32-point rows and 4-point gaps. Give its
list an explicit content-derived height capped at seven full rows, 248 points;
omit an empty scroll view. Resize for loading, empty and error messages, and keep
loaded rows visible while refreshing. Verify visible rows in the expanded popup,
not only Accessibility entries or the closed setup sheet. Recording meters reuse
`MicrophoneLevelMeter` with ten fixed-height cells. Both capture paths apply
`AudioLevel.meter` once: linear RMS times 8 clamped to 0...1. Add no view gain or
logarithmic curve; Receiving/Waiting is independent of amplitude.

Capture, media processing, dictation and cleanup are mutually exclusive. Stop and
save before quit or sleep, and keep recovery available from Transcribe. Use injected
capture sessions and direct PCM for tests. See `docs/meeting-recording.md`.
