# Airdraft — product goals

Owner: Light. Personal macOS dictation app. This file states what the mature
version must be; read it before changing UI, settings, or prompt handling.

## Goals (from Light, 2026-09-13)

1. **Quality feel.** The interface is well designed and friendly. Minimal HUD,
   no alarming colours, consistent typography, nothing that looks like a debug tool.
2. **Local and remote, independently.** The Transcriber and the LLM each choose
   local or remote on their own; changing one never affects the other.
3. **Convenient, unified setup.** Configuration is preset-driven: pick a provider,
   pick a model from a list the endpoint reports, done. Users are never required to
   write a custom prompt to get a good result.
4. **Editable profiles.** Every LLM behaviour (Clean, Concise, Summary, …) is a
   Refinement Profile whose instructions the user can read and edit. The shared
   base system prompt is also editable in Profiles, after a warning about its
   effect on every profile that uses AI refinement.
5. **User-defined profiles.** Users can add, duplicate, and delete their own profiles.
6. **Safe to experiment.** One button restores every built-in profile and the shared
   base rules to defaults; a per-profile reset exists too.

Added 2026-09-18:

7. **A matching marketing website.** A minimal Astro site on Cloudflare that
   carries AirDraft's neumorphic identity and explains the app's model choices.

Added 2026-09-21:

8. **App updates.** Manual checks and optional automatic downloads, with verified
   updates installed on quit without interrupting dictation.

9. **Microphone choice.** Select an input and save it as the app default, independent
   of the system input. Preserve the choice across restarts and reconnects.

10. **Clear permission setup.** Show permissions for the running copy, refresh
    after changes, and explain recovery from stale grants and duplicate builds.

Added 2026-09-24:

11. **Accessible account and microphone controls.** Keep a translucent sidebar;
    place account settings at its lower left, and show a compact device list with
    a live ten-cell input-level meter beside every microphone option.

## Installation experience

The DMG carries Airdraft's visual identity, presents an obvious drag to Applications,
and keeps the installation instructions legible within Finder.

## Status

| Goal | State (2026-09-25) |
|---|---|
| 1 | All page content cards share an 18-point continuous corner radius. Airdraft branding throughout the app, CLI and developer tools; the sidebar brand is a compact neumorphic capsule scaled proportionally by 1.25 to about 51 by 25 points in a 30-point branding row, with an outline-only raised rim and an unfilled interior that exposes the sidebar directly, five raised waveform bars and a separated caret, without visible lettering; native materials adapt to light/dark and increased contrast, and its accessible name is Airdraft; compact Codex-inspired sidebar with monochrome symbols, quiet selection and a subtle half-point divider. Collapsing keeps an approximately 91-point icon rail derived from the unchanged brand width plus equal 20-point side insets; navigation, microphone and available account icons are centered horizontally without changing their vertical positions. Control + Option is the default hold-to-dictate shortcut; saved shortcuts are preserved. The main window stays 784 points wide, allows vertical resizing from 600 points, and keeps only the close and minimize traffic lights. The native window buttons have 16-point top and leading insets, and the sidebar toggle shares their centerline in a 46-point titlebar; its bottom holds the microphone picker above the dictation word count. Every page header shows its name on the left and controls on the right. Page filters and search share a compact style; Profiles actions stay together on the right. Selected sidebar destinations use translucent raised neumorphic surfaces that transmit the sidebar blur, with outer shadows confined outside the face and a solid fallback for Reduce Transparency. The microphone capsule retains its opaque material. Both appearances use top-left lighting, with shared outer shadows that preserve their direction in live windows and saved renders. Neumorphic accents also extend to the sidebar microphone capsule, per-device level meters, shortcut keycaps, appearance previews, Home summary tracks and the recording HUD; selection cues, shared insets and live waveform contrast are preserved. The microphone capsule rests recessed, becomes raised on hover, and does not change on press. Home summary fills use solid violet. Native cards, key caps and theme/HUD previews with an edge-to-edge Auto theme split; dark recording pill at bottom centre with Classic / Mini / None. Configuration, Models and History share 16-point card insets on every side, 32-point minimum heading rows with a 4-point leading text inset, 12-point heading gaps and 28-point section gaps. Page content and section controls use the available width consistently; visible picker edges align with their card insets, and stepped numeric settings accept typing. History creates only visible cards as the user scrolls and has a fixed 52-point timeline column with one timestamp and horizontal tick per transcription. Selecting a tick jumps to its entry; the active tick follows scrolling, and search filters both columns. Model tables share their columns, selection controls and segmented meters. The menu bar keeps status labels compact and shows Unload models only when a managed model is loaded; full model details remain in the main window. Existing settings and data survive the rename. Home always opens with its hero: the four headline metrics use 26-point numbers in one row of equal-width columns above the icon's pressed-in capsule, whose raised neumorphic bars are built from the user's own dictations on a grayscale surface; bars stay neutral and only the hovered one takes the brand colour. The entrance waits for the first history load, then scales the real bars once without animating their layout height or replacing animated placeholders. A collapsible readiness card follows, then a locally computed summary (top apps, streak, active days, longest dictation); the hero's empty state doubles as a first-dictation prompt. A setup problem opens the readiness card below the hero rather than displacing it; the shortcut hint says Hold or Press to match the selected behavior, and refinement that is off reads as off rather than as a problem. Status dots, refresh buttons, disclosure headers, overlays and API-key rows each use one shared component; buttons use title case and headings sentence case. ⌘, opens Configuration and ⌘1–⌘6 switch pages; profile, history and vocabulary rows have context menus. Deleting a model or a history entry asks first, and downloads can be cancelled. Auto, Light and Dark update both the main app and isolated interactive preview windows immediately. Onboarding still missing. |
| 2 | Done: `Transcriber` / `Refiner` protocols, `EngineFactory`, per-stage config. Seven local model choices plus five direct cloud APIs: Soniox v5, Groq Turbo, Scribe v2, GPT-Transcribe and Nova-3. OpenRouter is a sixth cloud speech choice through its dedicated transcription endpoint and live STT model catalog. Speech and refinement selections are independent; both can use the same OpenRouter Keychain key. See `docs/transcription-apis.md` for roles and evidence. |
| 3 | Cloud speech providers have API-key connection tests and model comparison tables with source links and billing details. Eleven direct-provider file-transcription choices/modes are curated; OpenRouter adds a filtered live STT catalog with documented fallback choices. Its model prices can use audio duration or tokens, so the UI links to current pricing without an unsupported hourly conversion. Cloud meters use documented numeric benchmarks where available and explicitly show Not rated otherwise; local ratings remain relative guidance. Speech and refinement providers now use matching compact section pickers; each provider still shows its own model and settings below. Model choices survive provider switches and reloads. Connection tests check authenticated API access without uploading audio; they do not certify billing or speech permissions. Refinement includes dedicated Cerebras and Groq options with separate Keychain keys, live model discovery, provider-specific reasoning parameters, and migration of the former Groq server preset. OpenRouter refinement adds a model-specific inference-provider picker with remembered routing and optional host fallback; transcription does not support those per-request routing controls. Selected refinement endpoints show reported output speed, latency, uptime, token pricing, context/output limits and precision; missing data is explicit. Provider restrictions survive compatibility retries. Response metadata identifies the served host when available; authenticated live routing and transcription remain unverified. Refinement retains its `/models` picker; local models retain one-click anonymous downloads. Codex and Claude Code discover their model lists and per-model thinking levels from the installed CLI; custom model IDs remain available. CLI model and effort choices survive provider switches. First-run onboarding not yet built. |
| 4 | Done: `RefinementProfile` + `ProfileStore`; Profiles pairs a compact text-only list with an open editor. The base system prompt is visible above the profile list and editor, with a warning before editing. The list provides the only profile title; the editor starts with Refine transcript, Profile instructions and optional Task. One menu holds profile actions. The sidebar uses a document-and-pencil symbol. Inline names commit on Return or when focus leaves the field. The p6 prompt candidate reduces the default Clean system prompt by 50–52%. Local Qwen evaluation is 30/30 correction and 30/36 held-out versus 31/36 held-out for p5; the held-out release gate remains unresolved. See `eval/results/p6-validation.json`. |
| 5 | Done: create, rename, duplicate and delete in Profiles. Duplication copies the selected profile, including Verbatim behavior, without activating it. Built-ins cannot be deleted. |
| 6 | Done: confirmed per-profile and full resets; the base system prompt editor supports Save, Cancel and Restore defaults. Changes apply only on Save; empty prompts cannot be saved. |
| 7 | Astro marketing project at `apps/marketing`, initialized from Cloudflare's official starter. Shared pnpm workspace and independent Moon tasks; interactive sample, local/cloud explanation, source-build CTA, and responsive neumorphic UI. Shared navigation now contains Changelog and a GitHub icon, with a real changelog page distinguishing unreleased changes from public source history. The Buy Me a Coffee action awaits the owner's confirmed URL. Updated on `airdraft.app` in the `lstudlo` Cloudflare account with Google-only Access preserved. Anonymous page and asset requests redirect to Access; the authorized browser verified the live homepage and changelog. Worker development and preview URLs are disabled. Local build, desktop/mobile browser checks, and Wrangler dry run pass. |
| 8 | Sparkle checks and verified installation on quit, with local builds for each main push. From 0.1.5, the release gate requires a pinned Apple Development certificate and a stable designated requirement, inspects the packaged DMG, and exercises real certificate-signed and legacy-migration updates. Developer ID/notarization and M5 permission continuity remain unverified; see `docs/updates.md`. |
| 9 | Device pickers in the sidebar, menu bar and Configuration save a persistent device UID. Multi-input devices also save an input channel in Configuration. Explicit channel mapping preserves microphone audio on discrete-channel interfaces without mixing loopback; unavailable channels fail visibly. Missing devices fail visibly without selecting another input; same-input audio reconfiguration recovers without clearing captured audio. Missing or changed inputs report a specific error; see `docs/microphones.md`. The new bundle ID `com.lstudlo.app.airdraft` imports legacy preferences and credentials. |
| 10 | Live Accessibility/microphone state, running-copy diagnostics, and a separate Debug identity. The ad-hoc release defect is removed from 0.1.5; users migrating from older builds may need to grant access again. Later releases must preserve the approved signing identity. Verification on the affected M5 remains outstanding; see `docs/accessibility.md`. Keychain navigation/background reads are silent; selected-key approval is explicit, migration preserves inaccessible current entries, and key editors report write failures. Pending microphone requests cancel with shortcut release. See `docs/keychain-access.md`. |
| 11 | Implemented: the sidebar uses macOS frosted material beneath a darker neutral layer that stays 70% opaque through the upper half and fades to fully opaque at the bottom; Reduce Transparency makes the whole background opaque; Debug builds include a sample account overlay; Release omits the account button and sample subscription data. The microphone capsule opens a compact list of device choices, each with a live ten-cell input meter on its right. Decorative descriptions and the separate meter card are removed; permission actions and device errors appear only when needed. Each device is monitored once, System Default shares its device's meter, and previews stop when the overlay closes or dictation starts. Device choice remains persistent; the level preview retains no audio. |
| Production repairs | Local remediation adds recording prerequisites, session ownership, verified insertion targets, incomplete-response rejection, bounded refinement, audio retry, explicit storage failures, engine leases, persistent downloads, complete history pagination and calendar-day statistics. Known missing permissions, credentials, devices and models block capture before it starts. Core regression tests and render checks pass; public notarization and physical end-to-end acceptance remain separate release requirements. See `production-repairs.md`. |
| Installer | Implemented locally: a silver capsule installer with the shared outlined wordmark, real app and Applications icons, Retina background, and saved Finder positioning. Packaging verifies the image layout and signed app. The Finder preview uses an existing signed Release build; this change is not yet published. |

## Interface consistency

Standing requirement from Light, reaffirmed 2026-09-21:

- Page content cards use 18 pt continuous corners, defined once as
  `Theme.cardRadius`.
- Section cards have equal padding on all four sides: 16 pt, defined once as
  `Theme.cardPadding`. Vertical and horizontal padding must be the same.
- The card owns its outer insets. Settings rows inside it add no vertical padding;
  otherwise the first and last rows make the card look taller than its side insets.
- Configuration and Models use `PageSection` and `SettingsCard`, including
  microphone, updates, permissions, refinement and provider settings. New settings
  sections must use these components too.
- Page content fills the width available after the shared 24 pt page inset. Do
  not cap it at a left-aligned width that leaves a second, unexplained right
  margin. Section headings, heading controls and cards end on the same right edge.
  Inside a card, the visible edge of each trailing control ends at its 16 pt inset;
  a fixed-width invisible picker frame must not make the control look indented.
  Native settings pickers use `.settingsPicker(width:)` for this alignment.
- Numeric settings that have stepper arrows also accept typed values. Use
  `SettingsNumberStepper` to keep keyboard entry, bounds and arrow behavior
  consistent across pages.
- Use one compact provider picker in each stage. Place a refresh action directly
  beside the picker it updates. Do not fill a selector's unused width with
  decorative provider cards or leave a large gap between related controls.
- A description earns space only when it helps the user choose or act. Remove
  text that repeats the selected provider, announces that its model list is
  visible, or explains what a clearly labeled control already does. Preserve
  concise warnings, errors, permission guidance, and material cost or behavior
  differences when they affect a decision.
- Profile names carry the list; profile-specific icons and icon editing add no
  useful distinction. An inline profile name commits on Return or when focus
  leaves the field, with an empty draft handled predictably.
- Every page header shows the destination name on the left and its controls on
  the right. Search and filter controls share one compact style; Profiles keeps
  its create button and action menu together in the right-side control group.
  The sidebar microphone control is a padded capsule above the footer, without
  a separating line. It opens a compact device list with a ten-cell live level meter at the
  right of every row, without decorative descriptions or a separate meter card. A bottom-left account button opens a centered Account overlay;
  its values are explicitly sample data until account services exist. The sidebar
  uses macOS blur beneath a darker neutral layer over a transparent window
  background. The layer stays 70% opaque through the upper half, then fades to
  full opacity at the bottom. Reduce Transparency makes the whole background
  opaque. Content stays fully opaque.
- Collapsing the sidebar leaves an icon rail whose width is the unchanged brand
  width plus 20 pt on each side, about 91 pt total. Center navigation, microphone
  and available account icons horizontally without changing their vertical
  positions, row heights or group spacing. Hide labels and footer text while
  retaining tooltips, accessible names and the expand toggle.
- Keep neumorphic depth scoped to the sidebar brand capsule, selected sidebar destinations, the microphone capsule and meters, shortcut
  keycaps, appearance preview frames, Home summary tracks and the recording HUD.
  Reuse `NeumorphicSurface` for raised and inset neutral materials; retain clear
  selection, keyboard focus, disabled states and live audio contrast. The brand
  capsule keeps its interior unfilled, with outer shadows excluded from that area.
  Selected sidebar page items use translucent fills over the existing sidebar blur,
  with outer shadows excluded from the face and a solid Reduce Transparency fallback.
  The microphone capsule retains its opaque material. Light comes
  from the top left in both appearances. Raised faces cast down-right shadows;
  recessed tracks shade their inner top-left edge. Verify live and saved renders.
- History keeps a compact 52-point timeline beside the scrolling transcription
  cards, with a timestamp and horizontal tick for each entry. Clicking a tick
  jumps to its card; scrolling updates the active tick. Both columns share day
  grouping and search results, and cards continue to load lazily.
- One component per concept: `StatusDot` for every ready/attention/off state,
  `RefreshButton` beside any reloadable list, `.settingsDisclosure()` for
  collapsible settings, `OverlayPanel` for floating panels, and the `APIKeyField`
  row plus a Connection row for every provider key. Buttons and menu items use
  title case; section headings use sentence case.
- Section heading rows have a shared 32 pt minimum height, with titles and
  trailing controls vertically centered. Only the title text has a 4 pt leading
  inset for optical alignment. Use shared spacing: 12 pt from a section
  heading to its content, 28 pt between sections, and 12 pt between settings-card
  children. Keep content spacing separate
  from the card's outer padding. Table headers and rows own their equal 16 pt insets
  inside a zero-padding table container.
- Verify both light and dark appearances at the fixed 784-point window width,
  at minimum and taller heights. Inspect every page, including lower sections. Before
  reporting a released fix, inspect the app built from the exact committed sources;
  a correct rendering of uncommitted changes does not prove the DMG contains them.

## Verification rules

The marketing website is a separate surface at `apps/marketing`, with its own
`PRODUCT.md` and design system. It uses the native neumorphic icon, an illustrative
dictation preview, and a source-build CTA until a binary release exists. Its Moon
tasks and browser verification run independently of the native app.

- Every native UI change is rendered with `--render-window all` and looked at before it is reported.
- Website UI changes are inspected in the browser at desktop and mobile widths.
- Every pipeline change is exercised with `AIRDRAFT_SELFTEST=<wav>` (Debug builds) and confirmed in the log and history.
- Shortcut backends log their registration. The default Control + Option shortcut uses the event tap and requires Accessibility; key combinations such as Option + Space use Carbon.

## Non-goals for now

Windows / iOS, App Store distribution (Accessibility rules it out), team features.
