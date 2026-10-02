# Airdraft

Personal macOS menu-bar dictation app: speech ▸ LLM refinement ▸ insert at cursor.
Not a Printage company repository; the workspace `dev-guidelines` skill does not apply here.

## Product goals

`docs/PRODUCT.md` lists the goals the mature app must meet (quality UI, independent
local/remote engines, preset-driven setup, editable and resettable refinement
profiles). Read it before touching UI, settings, or prompt handling, and keep its
status table current. That table records implemented behavior only; release and
verification status belong in the vault (see below).

## External project resources

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

## Structure

- Moon is a small task runner around the existing Xcode layout. `.prototools` pins
  moon; `.moon/workspace.yml` maps one `airdraft` project; `moon.yml` defines
  `prepare` (once after clone), `generate`, `build`, and `test`. Use
  `moon run airdraft:build` / `moon run airdraft:test` for routine validation.
  Keep Xcode tasks uncached in moon and serialized by the shared mutex.
  `pnpm build:app` resolves the pinned local Moon binary; `pnpm test:local` runs
  the credential-free regression allowlist through the same Xcode mutex. Project
  generation uses installed XcodeGen or an existing `dist/tools/xcodegen` binary,
  and fails with an installation hint when neither exists.
- `project.yml` is the source of truth for the Xcode project. After changing it run
  `xcodegen generate`. `airdraft.xcodeproj` is generated and git-ignored.
- `Packages/AirdraftCore` holds all engine-agnostic logic and is the only place with tests.
  Run the tests (see Validation) before finishing any change there.
- `Sources/App` is the SwiftUI shell: `App/` (entry point, `AppContainer`, `ModelLifecycle`),
  `Hotkeys/`, `HUD/`, `Views/` (one file per page, shared components in `Theme.swift`),
  `Debug/` (offscreen renders, self-tests).
- `apps/marketing` is the Astro marketing website, initialized from Cloudflare's
  official Astro Framework Starter and deployed with Workers static assets.
  Read its `PRODUCT.md` and `DESIGN.md` before changing content or design, and
  build pages from its reusable components in `src/components/ui/`. JavaScript packages
  use the root pnpm workspace and lockfile; do not add nested repositories or lockfiles.
  `pnpm dev:marketing`, `pnpm check:marketing`, `pnpm build:marketing`, and
  `pnpm preview:marketing` run its independent Moon tasks. Website-only changes
  require those checks and desktop/mobile browser verification, not Xcode tests.
- The app icon is code: edit `scripts/render-app-icon.swift` (neumorphic bar with a waveform
  ending in a text caret) and run `swift scripts/render-app-icon.swift` from the repo root; it
  rewrites every PNG in `Sources/App/Assets.xcassets/AppIcon.appiconset`. Do not hand-edit the PNGs.
  `swift scripts/render-app-icon-variants.swift [dir]` renders candidate icons and a comparison
  sheet (current icon first, with 64, 32 and 16 px sizes) to a scratch directory without touching the
  asset catalogue; port the chosen variant into `render-app-icon.swift`. The icon script also
  writes the website's `airdraft-icon.png` and `favicon.png`. After changing the icon, run
  `uv run apps/marketing/scripts/render-brand.py` (coloured capsule SVGs) and update
  `apps/marketing/src/data/icon.ts`, which the website's 3D hero object is built from.

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
  The expanded sidebar is 170 points wide.
  Collapsing the sidebar keeps an icon rail. Derive its width from the unchanged
  brand width plus equal 20-point side insets. Center destination, microphone
  and available account icons horizontally while preserving their expanded
  vertical positions and row heights. Hide text, retain tooltips and accessible
  names, and keep the titlebar toggle available to expand it again. In the collapsed
  state, place the toggle outside the rail in the page island's heading row, with
  its symbol aligned to the page leading inset and its center on the heading row.
  Inset the page heading beside the collapsed toggle so their hit areas stay separate.
  The outlined `SidebarWordmark.imageset` SVG remains the website and installer
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
  corners) and `Theme.islandBackground`: 0.86 white in light mode and 0.15 in
  dark mode. In both appearances the island must stay darker than the chrome and
  at the Home hero's surface gray (light hero 0.87–0.85 around it; dark hero
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
  conventional commit for that task unless the user asks to leave it uncommitted.
  Stage only task-related files or hunks; preserve unrelated worktree changes.
  If the task cannot be committed cleanly, explain why. Push or release only
  when the user requests it.
- Interface consistency is a product requirement. Native section cards must have
  equal top, bottom, leading and trailing insets: `Theme.cardPadding` (16 pt).
  All page content cards use `Theme.cardRadius` (18 pt) for continuous corners.
  Use `PageSection` and `SettingsCard` for settings sections, including Configuration
  and Models. The card owns the outer padding; rows inside it must not add another
  vertical inset. Use shared spacing tokens instead of page-specific values.
  Descriptions use the shared `.supportingText()` style: 11-point regular,
  secondary text below 13-point setting titles. Keep each description to one short
  phrase when possible; retain essential privacy, cost and recovery information.
  Remove redundant descriptions and place longer explanations in existing details
  disclosures. Error notices keep the message and action in one horizontal row;
  long diagnostics may wrap beside the action. Separate every Home readiness row
  with `RowDivider`, including rows without a trailing action.
  Section headings use a shared 32-point minimum row height, a 12-point gap to
  their content and 28-point section spacing. Center titles and trailing controls
  vertically within the row, including provider pickers. Inset only the heading
  text by `Theme.sectionTitleLeadingInset` (4 pt) for optical alignment.
  Page content must fill its available width after `Theme.pagePadding`; do not add
  a left-aligned maximum width that strands section controls far from the window's
  right edge. Section headings, their trailing controls and cards share one right
  edge. Use `SoftPicker(title, selection:, width:)` for menu pickers in settings rows or
  section headings so the visible capsule aligns with that edge. Numeric settings with a
  stepper must also support direct keyboard entry through `SettingsNumberStepper`.
  Keep settings copy purposeful: do not add descriptions that merely restate the
  selected provider, that a list is showing models, or other facts already obvious
  from the control. Keep concise text when it changes a decision or explains an
  actionable error, unavailable state, permission, or cost. Put related heading
  actions immediately beside their selector rather than separating them with a
  fixed-width invisible frame. Provider selection uses one compact picker, not
  a grid of decorative provider cards. Profiles uses the same compact picker in its
  Profile section heading instead of a profile list; names carry it, without icons.
  The sidebar microphone overlay contains device choices with a live ten-cell
  meter at each row's trailing edge. Omit decorative descriptions and a separate
  meter card; retain actionable permission and device errors. Keep it compact:
  336 points wide with an 8-point inset, a 28-point title row and 32-point rows on
  the sidebar's scale, aligned with the microphone capsule and 8 points above it.
  Monitor each eligible device once and share its level with System Default.
  Identify wired/wireless Continuity microphones by Core Audio transport type;
  preview them only when selected, including when System Default resolves to them.
  Opening the picker must not connect unselected iPhones. Stop their previews on
  deselection, and stop all previews when closed or dictating.
  The microphone capsule stays recessed, with no hover or pressed treatment.
  Sidebar destination selection replicates the microphone well exactly: the same
  opaque recessed material, 2.5-point depth, top-left inner shade and bottom-right
  inner light. Both wells use `NavigationStyle.wellShape`, 12-point continuous
  corners, so their radii match while the microphone stays taller (38 points)
  than destination rows (32 points). Hover and press fills on destination rows use
  the same radius. One well serves both destination groups: rows publish their
  bounds with `.sidebarSelectionAnchor`, and `.sidebarSelectionWell` slides it to
  the selected row on a 0.36-second ease-in-out curve (`SelectionMotion.curve`,
  cubic-bezier 0.65, 0, 0.35, 1), whatever changed the
  page. Rows never draw their own selected well; Reduce Motion moves it instantly.
  Home summary fills use one solid neutral gray, raised inside their inset track
  with a top-left highlight and down-right shade; never a brand hue.
  Sidebar destination, microphone and account symbols use
  `Theme.sidebarIconSize` (13 points).
  Keep the main window 784 points wide with resizable height (minimum 600 points).
  Hide its green zoom/full-screen button; preserve Close and Minimize.
  Inset the native window buttons 16 points from the top and leading edges;
  align the sidebar toggle with their centers in the 46-point titlebar. Page
  headings and actions use a separate 32-point row with 24 points above it inside
  the island and 12 points below, inside one sticky header. Extend its backdrop blur through the
  24-point content inset below it, plus a 4-point outer feather. Text at the
  bottom of that inset must already be lightly but visibly blurred at about
  1 pt radius; increase quadratically to 32 pt at the top. Do not leave a
  nearly sharp lower region or obscure entering text immediately.
  Use `ProgressiveHeaderBlur`; never simulate this with material opacity, a tint
  gradient or a short edge fade. Keep header labels and controls sharp. The
  undocumented compositor filter is isolated and capability-checked, with a
  standard material fallback on unsupported systems. Suppress native hard
  scroll-edge separators; only Reduce Transparency gets an opaque header. Keep
  the 24-point content inset inside scrolling content, including both History
  columns, and preserve vertical positions on collapse.
  History has a compact 52-point timeline beside its independently scrolling
  cards. Timeline day headings always show calendar dates such as Sep 25;
  reserve Today and Yesterday for the main card column. One time-and-tick button
  jumps to each entry; the current entry stays
  highlighted as the cards scroll. Returning the cards to the top also restores
  the timeline's first day heading, even when its first entry is already active.
  History prepares grouping, formatted labels, text previews and audio availability
  once per database page off the main actor. Keep timeline scroll state separate
  from page data, and find the first visible record through the snapshot ID index.
  Never scan or regroup all loaded records during scrolling or check files from
  row bodies. Keep accessibility scrolling independent of SwiftUI lazy-row identity
  traversal; its lightweight representation exposes visible rows, shares row actions
  and provides first/last, page and record navigation. Track timeline visibility
  per rendered row so programmatic jumps expose the visible timestamps to
  accessibility. Remove visibility when lazy rows disappear as well as when their
  visibility callbacks change; returning to the top must not retain offscreen
  timestamps. The navigation fixture asserts this cleanup. Exclude zero-visibility
  prefetched rows from active-entry tracking, and reveal the real row before
  presenting Details or Delete. Collapsed text uses bounded native layout with cached sizing, not
  hidden full transcripts or geometry-to-state height feedback. Preserve full text
  for Copy and expansion, and keep expansion/version state outside lazy rows.
  Explicitly clip the native transcript field to its measured bounds so long text
  and selection cannot draw over Show More, the version picker or card actions.
  Verify the drawing boundary as well as the six-line measurement.
  Keep day groups, search, lazy card loading
  and native card actions. The timeline follows the same filtered records. Refresh sidebar word totals after single/all history
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
  Reuse the shared components in `Theme.swift` (`StatusDot`, `RefreshButton`,
  `EmptyNote`, `OverlayPanel`, `.settingsDisclosure()`) and the `APIKeyField` row
  for every provider key instead of page-specific variants. Buttons and menu items
  use title case; section headings use sentence case.
  Read the interface consistency rules in `docs/PRODUCT.md` and inspect light/dark
  renders at the fixed 784-point width and minimum/taller heights, including lower sections. Check every
  page for the same alignment and input pattern. For a released UI fix, verify the app built
  from the committed release sources, not only the dirty workspace.
- Neumorphism covers the whole window. Page cards and controls use
  `SoftRaisedSurface` from `SoftControls.swift`: the Home hero's light and shade at
  full strength (white highlight up-left, shade down-right), with a smaller spread,
  half for `Card` sections and a quarter for controls. Never lower their contrast to
  make them subtle; shrink the spread instead. Controls are raised: `SoftButtonStyle`
  and `SoftIconButtonStyle` sink into an inset well while pressed; text fields use
  `.softField()` with an accent ring while editing; menu pickers use `SoftPicker`;
  segmented choices use `SoftSegmentedPicker` (a raised thumb sliding on an inset
  track with `SelectionMotion.curve`); switches use `.toggleStyle(.softSwitch)`, whose
  on state fills the inset track with the system accent; sliders use `SoftSlider`;
  steppers use raised minus and plus buttons beside the typed value. Keep
  `.borderedProminent` for the single primary action and native link buttons. The
  menu-bar menu stays native. Reuse `NeumorphicSurface` for the sidebar wells,
  keycaps, meters, preview frames and Home tracks. Light comes from the top left in both appearances: raised surfaces
  highlight their top-left edge and cast shadows down-right; recessed surfaces
  shade the inner top-left edge and light the inner bottom-right edge.
  Use `SurfaceShadows` for outer shadows: AppKit bitmap capture can invert the
  vertical offset of SwiftUI's direct shadow modifiers. Check the live window
  as well as saved renders. Keep selection/focus cues, card insets and live waveform
  contrast. Model table rows and text lists stay inside their raised cards without
  extra per-row depth.
- After successful text delivery, freeze the recording HUD's final processing
  display and fade the capsule out over 0.5 seconds. Start at delivery, before
  clipboard restoration and history saving; never return to the recording timer
  or reopen it for a later success notice. New recording cancels the old fade.
  Failures and recovery notices expand the native panel over 0.28 seconds to show
  complete wrapping diagnostics, with Copy Message at the far right. Bound the
  panel to the current screen and scroll oversized diagnostics without truncation.
  Keep the diagnostic snapshot visible through the pipeline's idle reset until
  the next operation. Informational confirmations such as Copied to clipboard
  show for three seconds, then fade over 0.5 seconds; classify them at the delivery
  source instead of comparing message text in the HUD. Copy must preserve all text without activating the panel;
  recording remains click-through. Reduce Motion disables spatial expansion.
  Size the capsule to its current timer or status label, with six-point outer
  insets on every side of the waveform well. Do not reserve a fixed label width;
  grow the native panel when the timer gains a digit and keep it centered.
- Native menu items never wrap, so the widest title sets the menu-bar menu's
  width. Keep that menu about 270 points wide: pass every dynamic title (status,
  issues, notices, device, profile and provider names) through `MenuTitle.fit`,
  which measures the menu font against a 190-point limit. Never show full
  diagnostics in a menu item; keep them in tooltips and Home's recovery notice.
- Both stages are provider-agnostic. New engines implement `Transcriber` or `Refiner`,
  get a `*ProviderKind` case, and are wired in `EngineFactory`. Never hard-code a provider
  in the pipeline or views.
- `ASRConfig.engineID` must equal the `id` of the transcriber `EngineFactory` builds for it
  (`EngineFactoryTests` checks this); the UI looks up load state by it.
- Local engines load only from `LocalModels` folders and never download on their own.
  Downloads go through `ModelDownloader` (Models page). The Models table is data in
  `ModelCatalogue`; installed, loaded, download and delete all derive from each entry's `select`.
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
  one paste. Editors that draw their own text (Zed, Warp, GPU terminals) never expose
  a caret: verify the same process, its focused window and no foreign system focus
  instead; a missing caret alone must not block paste. Never probe editor
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
  their actual xcresult; mandatory insertion cases cannot be missing or skipped.
  Once paste is posted, its clipboard restoration delay must survive cancellation
  so the receiving app can read the text. Never repeat a posted paste. Preserve
  newer clipboard ownership. From 0.4.2, release preparation checks actual TextEdit
  and Chrome delivery for both saved insertion preferences, with fixture binary
  hashes matching the committed Debug build. Follow the Local releases policy
  when acceptance is unavailable: publish with a commit-bound unverified reason
  and report it afterward. See `docs/local-e2e.md`.
  Reject incomplete refinement responses and bound discovery, model loading and
  compatibility retries by one end-to-end refinement deadline.
- The LLM is best-effort. Any change to `DictationPipeline` must keep the fallback:
  LLM error or timeout still inserts the raw transcript.
- `DictionaryPostProcessor.apply` runs last, after the LLM. Do not move it.
- Refinement output passes `RefinementFidelity` before delivery. A result that
  repeats an earlier same-app dictation the new speech does not resemble, or that
  changes the transcript's language without a profile TASK or selected text, is
  discarded for the raw transcript and recorded as a refinement error. Prompts get
  recent dictations only as `<recent_terms>` (names and technical terms), never
  sentences: small models returned them instead of the new speech, and each copy
  fed the next prompt. The OUTPUT LANGUAGE rule is assembled in `PromptBuilder`
  code so edited base rules keep it. Whisper prompts carry only the script
  sentence; Whisper repeats bare dictionary terms on silence, so terms go only to
  dedicated keyword or context fields.
- Secrets go in `Keychain` (service `com.lstudlo.app.airdraft`), never in UserDefaults,
  files, or logs.
- Passive credential access must never prompt. Badges use `Keychain.presence`;
  reads distinguish missing from denied/locked. Only a selected-key Allow access
  action may authorize reading. Use `CredentialEditor` for key fields; never report
  Saved after a failed write or migrate over an inaccessible current item.
  Keep the real signed-identity fixture test in `scripts/verify-keychain.py` in the
  release gate. See `docs/keychain-access.md`.
- The bundle ID and Keychain service are `com.lstudlo.app.airdraft`. Import legacy
  `com.lightiichen.transcribar` preferences and credentials without overwriting current
  values. Keep `Application Support/Transcribar` for existing models and history.
- Swift language mode is 5 on a Swift 6 compiler; keep `@MainActor` on UI-facing
  classes and `Sendable` on protocol types.
- Prompt changes bump `PromptBuilder.version` so history records stay comparable, and must be
  scored with `eval/run_correction_eval.py` on both `correction_cases.json` and the held-out
  `holdout_cases.json` (LM Studio running). Do not ship a prompt that loses a held-out case.
  Clean profiles and coding destinations must still correct recognition errors,
  including technical-name spelling and word boundaries. Preserve valid words and
  literal identifiers, commands and paths. Also run `context_correction_cases.json`
  when changing correction rules to check both corrections and literal preservation.
- Quitting must go through `ModelLifecycle.shutdown()` (unloads speech engines and the LM Studio
  instances the app used). Never return `.terminateLater` from the app delegate: it deadlocks.
- LLM behaviours are `RefinementProfile`s in `ProfileStore`, never hard-coded modes.
  Built-ins have stable ids and must stay resettable to `RefinementProfile.defaults`.
- Profiles shows the selected profile's Name, Dictation and Refine transcript card,
  then its instructions, with the shared base system prompt in a separate last section.
  Show a warning before opening its editor; keep edits in a draft until Save, with
  Cancel and Restore defaults. Use the existing `ProfileStore.baseRules` pipeline.
- Setup stays preset-driven: providers come from `EndpointPreset`, models from
  `ModelCatalog`. Do not add UI that requires typing a prompt to get a good result.

## First-run setup

The optional, replayable onboarding uses the normal permissions, model downloader
and dictation pipeline. Persist skip separately from successful practice; typed
sample text must never mark a dictation complete. Existing setups do not open the
flow automatically. Practice temporarily disables refinement and uses cursor
insertion; restore returning users' refinement and output settings on exit and
after restart. Never execute a saved script during practice. Use isolated preview
containers for the `onboarding-*` Debug renders.

## Official-build licensing

Self-built editions are fully unlocked and do not install paid official Sparkle
updates automatically. Official builds use a full-feature trial followed by a
Polar license-key activation. Start the trial only on explicit user action,
not during onboarding or model downloads. Gate new work through the pipeline's
access check; never interrupt an active recording or lock history and recovery.
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
The `benefit_ids` allowlist contains the two-Mac and five-Mac plan benefits.
Validate membership before activation and persist the returned benefit ID;
never accept an arbitrary benefit from the same organization.
The License sheet is plain text: the sidebar's `SidebarBrandMark` at 32 points
(its `height` parameter; the sidebar size is unchanged) with Done, one headline,
one sentence, then the buttons that apply. Use one prominent action per state and
the shared soft capsule for the rest. Do not add cards, status dots, badges,
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

When API-key or credential testing is explicitly excluded, prepare with
`--test-scope credential-free` and push with
`AIRDRAFT_RELEASE_TEST_SCOPE=credential-free`. The release records its exact test
scope and exclusions in `release.json` and release notes. This replaces only
credential/cloud tests and the cross-identity Keychain fixture with the local
allowlist; signing, licensing configuration, updater installation, packaging and
downloaded-artifact checks remain required. Updater fixtures use disposable
Sparkle seeds through `--ephemeral-key`; packaging still uses the existing signing key.

Run `moon run airdraft:release-setup` once per release Mac. The installed pre-push
hook builds committed sources locally for every origin/main push. The GitHub
workflow publishes the verified draft after the push succeeds. See `docs/updates.md`.
Never override release signing with `CODE_SIGN_IDENTITY=-`. macOS permissions
require a stable certificate-bound designated requirement; Sparkle signatures do
not provide that identity. Keep `scripts/release-signing.json` pinned. Certificate
or team changes need an explicit migration review, not an automatic fallback.
Verify the app inside the DMG and run the real updater identity checks. Do not
claim that signing tests prove permission continuity on an untested second Mac.
Keep `ENABLE_HARDENED_RUNTIME: YES`: an unsandboxed app holding Microphone and
Accessibility access must not load injected code. Renders and self-tests compile
only into Debug builds; never ship an environment- or argument-triggered path.

The DMG installer uses `scripts/build-dmg.py` through `package-update.py`.
Keep its locked `uv` dependencies, `scripts/dmg-layout.json` and the code-rendered
Retina artwork in `scripts/render-dmg-background.swift` together. Reuse the
outlined wordmark and silver capsule geometry. Inspect the actual mounted Finder
window, including installation copy when path/status bars remain visible. Never
add FinderInfo to the signed app to hide its extension; strict signing rejects
it. See `docs/installer/DESIGN.md` and `docs/updates.md` for the local preview path.

## Validation

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
- Tests: `xcodebuild -project airdraft.xcodeproj -scheme airdraft -configuration Debug -skipPackagePluginValidation -skipMacroValidation test`
  (runs `AirdraftCoreTests` inside the app's DerivedData). `cd Packages/AirdraftCore && swift test` also
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
  passes through intermediate positions, across a group gap, and settles on the row.
- Header blur: compile `Sources/App/Views/ProgressiveHeaderBlur.swift` with
  `scripts/verify-progressive-header.swift` using `xcrun swiftc`, then run it.
  Use `--live` for the compositor fixture: 13-point text must remain recognizable
  but visibly softened at the bottom of the content inset, then blur upward while
  its foreground label stays sharp. Do not judge onset using only broad stripes.
  `--island <png>` captures the fixture's own window through the compositor, which
  needs no Screen Recording access, and asserts the island clip, chrome-free blur
  and sharp content below the header; look at the saved PNG as well.
- UI (Debug builds): `airdraft --render-window all <dir>` and `--render-hud <png>`, then look at the PNGs.
  Views check `RenderMode`, never process arguments or `AIRDRAFT_RENDER_*` directly.
  `AIRDRAFT_RENDER_WIDTH` / `AIRDRAFT_RENDER_HEIGHT` set the window size (use a tall height to
  see lower sections); `AIRDRAFT_RENDER_EMPTY_HISTORY=1` shows Home's first-run state.
  `AIRDRAFT_RENDER_SIDEBAR_COLLAPSED=1` renders the compact icon rail; compare
  it with the expanded sidebar at the same window height.
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
- Keep `DEVELOPMENT_TEAM` in `project.yml`; ad-hoc signing breaks Accessibility on every rebuild.
- MLX (Qwen3-ASR, Cohere) only works in Xcode-built products; `swift build` has no Metal library.
- sherpa-onnx (FireRedASR2, SenseVoice) is linked through `Packages/SherpaOnnxKit`, whose
  `Vendor/` xcframeworks are generated by `scripts/make-sherpa-xcframeworks.sh` (run once after
  clone; git-ignored). Do not depend on the upstream sherpa-onnx package directly: its static
  `.framework` bundles get embedded by Xcode and break code signing. `SherpaTranscriber` calls
  the C API directly; do not re-add the 2,300-line upstream Swift wrapper.
  Keep the `AirdraftCore` product dynamic and explicitly embedded in `project.yml` so its
  engines stay out of Xcode's preview JIT linker. Linking them there causes duplicate Sherpa symbols
  and can exceed the preview launch deadline. Use normal Canvas execution; legacy previews
  can drop the installed Metal toolchain from dependency builds on Xcode 27.
- speech-swift has no releases and is pinned to a revision in `Packages/AirdraftCore/Package.swift`.
  Move the pin deliberately and re-run the Qwen3 and Cohere self-tests.
- Speech engines kept on purpose: Parakeet TDT 0.6B v3 INT8, Qwen3-ASR 1.7B/0.6B, FireRedASR2-AED, Cohere Transcribe 2B,
  SenseVoice-small, Whisper Large v3 Turbo, Apple SpeechAnalyzer. Cloud APIs are Soniox v5, Groq Turbo,
  ElevenLabs Scribe v2, OpenAI GPT-Transcribe and Deepgram Nova-3 (see `docs/transcription-apis.md`).
  Do not re-add the removed Whisper variants or Voxtral without a reason.
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
against the committed export before packaging. Keep `eval/results/prompt-validation.json`
bound to the current prompt assembly and all three evaluation datasets; no per-case
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

## Live transcription preview

Live preview uses a separate Apple Speech analyzer on macOS 26+ and the same
16 kHz microphone chunks as final transcription. Its language is independent of
the selected final ASR provider. Install assets explicitly in Models through
`ModelDownloadStore`; preview never downloads or uses a cloud provider. Bound its
audio queue and displayed text, replace provisional phrases, and cancel without
waiting before final ASR. Reject callbacks from old sessions. Preview errors are
nonfatal; preview text never reaches history, refinement, clipboard or scripts.

## Saved recording history

Audio retention is opt-in and independent of text history. `HistoryStore` owns
private UUID WAV sidecars and their SQLite references, including deletion,
retention and orphan cleanup. Preserve audio in pending-save recovery. Run cleanup
at launch, hourly, after saves and after retention changes. Playback has one owner
and stops when recording, deleting, leaving History or cleaning up audio.
Retranscription uses a review-only pipeline policy, including explicit retries;
it never inserts, runs delivery scripts, replaces the original entry or adds to
history/statistics. Only the user's Copy action changes the clipboard.

## Recording and recovery invariants

Check recording prerequisites before opening the microphone or prewarming a
refiner: permission, insertion access, selected device/channel, model installation
and readiness, endpoint validity, and required speech/refinement credentials.
Never prompt for a credential implicitly. A blocked attempt opens Home with an
actionable reason, even when the HUD is hidden. Refinement Off and Verbatim do not
require refinement credentials; unexpected refinement errors still preserve raw text.
Recording callbacks, release timers and asynchronous results belong to their session.
Keep failed speech audio in memory for explicit retry or discard, and warn before
quitting with recoverable audio or unsaved changes. Saving failures must stay visible.
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
for native regression fixtures. `verify-updater.py --ephemeral-key` uses a
disposable Sparkle seed and temporary update target. Record live, fixture,
source-review and unavailable coverage separately. See `docs/local-e2e.md`.
