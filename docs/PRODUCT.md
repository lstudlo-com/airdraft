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

11. **Accessible license and microphone controls.** Keep a translucent sidebar;
    place license settings at its lower left, and show a compact device list with
    a live ten-cell input-level meter beside every microphone option.

12. **First-run setup.** Offer optional permissions, local model or BYOK setup,
    and a real shortcut exercise. Remember skipping, allow replay, and preserve
    returning users’ refinement and output settings.

13. **Official-build licensing.** Offer an explicit full-feature trial and Polar
    activation. Keep source builds fully functional and data accessible after expiry.

## Installation experience

The DMG carries Airdraft's visual identity, presents an obvious drag to Applications,
and keeps the installation instructions legible within Finder.

## Status

| Goal | State (2026-09-30) |
|---|---|
| 13 | Implemented trial, Keychain license storage, Polar public API activation/validation/deactivation and new-work access checks. Two-Mac and five-Mac products have separate allowed benefits and share a checkout link with plan selection; the live prices and device policies were read back. Debug is restricted to Sandbox and Release to production, with separate license receipts and a dedicated licensed Debug build command; ordinary source builds remain unlocked. Sandbox test-card purchases and issued keys for both plans now pass app activation, restart persistence, 2/5-device limits, rotation, portal deactivation and refund revocation. Actual disconnected restart and disposable-user Keychain denial remain separate acceptance checks. This is not a published paid release; see `licensing.md`. |
| 12 | Implemented optional three-step onboarding with explicit model downloads, reused provider credentials and real pipeline delivery. State and restoration tests accompany the implementation; live shortcut and permission approval remain device-dependent. |
| 1 | Descriptions use a shared 11-point secondary style and concise copy across pages; recovery messages share a row with their actions, and all Home readiness rows have separators. All page content cards share an 18-point continuous corner radius. Airdraft branding throughout the app, CLI and developer tools; the sidebar brand is a compact neumorphic capsule scaled proportionally by 1.25 to about 51 by 25 points in a 30-point branding row, with an outline-only raised rim and an unfilled interior that exposes the sidebar directly, five raised waveform bars and a separated caret, without visible lettering; the rim and strokes use stronger neutral contrast in both appearances; native materials adapt to light/dark and increased contrast, and its accessible name is Airdraft; 170-point expanded sidebar with monochrome symbols, quiet selection and a subtle half-point divider. Collapsing keeps an approximately 91-point icon rail derived from the unchanged brand width plus equal 20-point side insets; navigation, microphone and available account icons are centered horizontally without changing their vertical positions. Control + Option is the default hold-to-dictate shortcut; saved shortcuts are preserved. The main window stays 784 points wide, allows vertical resizing from 600 points, and keeps only the close and minimize traffic lights. The native window buttons have 16-point top and leading insets, and the sidebar toggle shares their centerline in a 46-point titlebar; the collapsed toggle sits outside the rail with its symbol aligned to the content leading inset; its bottom holds the microphone picker above the dictation word count. Page headings and actions have a 32-point row with 24 points of top breathing room and 12 points below. The sticky header blurs the entire header and the 24-point content inset beneath it, with a 4-point outer feather. Text at the bottom of the inset is lightly but visibly blurred at 1 pt radius, increasing quadratically to 32 pt at the very top; header text and controls remain sharp, with no opacity gradient or tinted plate. The isolated compositor filter is undocumented; unsupported systems fall back to standard material. Reduce Transparency provides a solid fallback. The collapsed sidebar toggle has its own space beside the heading. Every page header shows its name on the left and controls on the right. Page filters and search share a compact style; Profiles actions stay together on the right. Selected sidebar destinations use translucent raised neumorphic surfaces that transmit the sidebar blur, with outer shadows confined outside the face and a solid fallback for Reduce Transparency. The microphone capsule retains its opaque material. Both appearances use top-left lighting, with shared outer shadows that preserve their direction in live windows and saved renders. Neumorphic accents also extend to the sidebar microphone capsule, per-device level meters, shortcut keycaps, appearance previews, Home summary tracks and the recording HUD; selection cues, shared insets and live waveform contrast are preserved. The microphone capsule stays recessed, with no hover or pressed treatment. Home summary fills use solid violet. Native cards, key caps and theme/HUD previews with an edge-to-edge Auto theme split; dark recording pill at bottom centre with Classic / Mini / None. Successful delivery starts a 0.5-second fade from the final processing display, before clipboard restoration or history saving; idle never brings back the recording timer, and a new recording cancels an unfinished fade. The capsule fits the current timer or label, with equal six-point outer insets around the waveform well and no reserved status width. Configuration, Models and History share 16-point card insets on every side, 32-point minimum heading rows with a 4-point leading text inset, 12-point heading gaps and 28-point section gaps. Page content and section controls use the available width consistently; visible picker edges align with their card insets, and stepped numeric settings accept typing. History prepares each database page off the main actor, isolates timeline updates, and bounds collapsed transcript layout with explicit native clipping to keep text clear of card controls; expansion and version choices survive lazy row eviction. It creates only visible cards as the user scrolls and has a fixed 52-point timeline column with calendar-date day headings such as Sep 25, plus one timestamp and horizontal tick per transcription. Today and Yesterday remain only in the main card column. Selecting a tick jumps to its entry; the active tick follows scrolling, returning to the top restores the first day heading in both columns, and search filters both columns. Pointer clicks clear stale control focus; keyboard and VoiceOver overlay dismissal restore focus to the trigger. Model tables share their columns, selection controls and segmented meters. The menu bar keeps status labels compact and shows Unload models only when a managed model is loaded; full model details remain in the main window. Existing settings and data survive the rename. Home always opens with its hero: the four headline metrics use 26-point numbers in one row of equal-width columns above the icon's pressed-in capsule, whose raised neumorphic bars are built from the user's own dictations on a grayscale surface; bars stay neutral and only the hovered one takes the brand colour. Light-mode bars have darker silver faces, and the well is 60 points tall with 24-point minimum horizontal inner insets to bring the waveform closer to its edges. The entrance waits for the first history load, then scales the real bars once without animating their layout height or replacing animated placeholders. A collapsible readiness card follows, then a locally computed summary (top apps, streak, active days, longest dictation); the hero's empty state doubles as a first-dictation prompt. A setup problem opens the readiness card below the hero rather than displacing it; the shortcut hint says Hold or Press to match the selected behavior, and refinement that is off reads as off rather than as a problem. Status dots, refresh buttons, disclosure headers, overlays and API-key rows each use one shared component; buttons use title case and headings sentence case. ⌘, opens Configuration and ⌘1–⌘6 switch pages; history and vocabulary rows have context menus. Deleting a model or a history entry asks first, and downloads can be cancelled. Auto, Light and Dark update both the main app and isolated interactive preview windows immediately. Three-step onboarding now guides permissions, local/BYOK speech setup and real shortcut practice; see goal 12. |
| 2 | Done: `Transcriber` / `Refiner` protocols, `EngineFactory`, per-stage config. Eight local model choices plus five direct cloud APIs: Soniox v5, Groq Turbo, Scribe v2, GPT-Transcribe and Nova-3. OpenRouter is a sixth cloud speech choice through its dedicated transcription endpoint and live STT model catalog. Speech and refinement selections are independent; both can use the same OpenRouter Keychain key. See `docs/transcription-apis.md` for roles and evidence. |
| 3 | Cloud speech providers have API-key connection tests and model comparison tables with source links and billing details. Eleven direct-provider file-transcription choices/modes are curated; OpenRouter adds a filtered live STT catalog with documented fallback choices. Its model prices can use audio duration or tokens, so the UI links to current pricing without an unsupported hourly conversion. Cloud meters use documented numeric benchmarks where available and explicitly show Not rated otherwise; local ratings remain relative guidance. Speech and refinement providers now use matching compact section pickers; each provider still shows its own model and settings below. Model choices survive provider switches and reloads. Connection tests check authenticated API access without uploading audio; they do not certify billing or speech permissions. Refinement includes dedicated Cerebras and Groq options with separate Keychain keys, live model discovery, provider-specific reasoning parameters, and migration of the former Groq server preset. OpenRouter refinement adds a model-specific inference-provider picker with remembered routing and optional host fallback; transcription does not support those per-request routing controls. Selected refinement endpoints show reported output speed, latency, uptime, token pricing, context/output limits and precision; missing data is explicit. Provider restrictions survive compatibility retries. Response metadata identifies the served host when available; authenticated live routing and transcription remain unverified. Refinement retains its `/models` picker; local models retain one-click anonymous downloads. Codex and Claude Code discover their model lists and per-model thinking levels from the installed CLI; custom model IDs remain available. CLI model and effort choices survive provider switches. First-run onboarding reuses these providers and model presets; see goal 12. |
| 4 | Done: `RefinementProfile` + `ProfileStore`; Profiles is one column. A compact picker in the Profile section heading chooses the profile, followed by a card with Name, Dictation (In Use or Use Profile) and Refine transcript, then Instructions with an optional Task. The shared base system prompt is the last section, with a warning before editing. One menu holds profile actions. The sidebar uses a document-and-pencil symbol. The p13 default prompt distinguishes recognition corrections from literal identifiers and filenames, including in Clean and coding destinations. Local Qwen evaluation passes 30/30 correction, 36/36 legacy holdout and 18/18 context-preservation checks, with three runs per case. The legacy holdout was inspected during repair and now serves as a regression set. See `eval/results/prompt-validation.json`. Saved profile instructions and base rules remain editable and resettable. |
| 5 | Done: create, rename, duplicate and delete in Profiles. Duplication copies the selected profile, including Verbatim behavior, without activating it. Built-ins cannot be deleted. |
| 6 | Done: confirmed per-profile and full resets; the base system prompt editor supports Save, Cancel and Restore defaults. Changes apply only on Save; empty prompts cannot be saved. |
| 7 | Astro marketing project at `apps/marketing`, initialized from Cloudflare's official starter. Shared pnpm workspace and independent Moon tasks; interactive sample, local/cloud explanation, source-build CTA, and responsive neumorphic UI. Shared navigation now contains Changelog and a GitHub icon, with a real changelog page distinguishing unreleased changes from public source history. The Buy Me a Coffee action awaits the owner's confirmed URL. Updated on `airdraft.app` in the `lstudlo` Cloudflare account with Google-only Access preserved. Anonymous page and asset requests redirect to Access; the authorized browser verified the live homepage and changelog. Worker development and preview URLs are disabled. Local build, desktop/mobile browser checks, and Wrangler dry run pass. |
| 8 | Sparkle checks and verified installation on quit, with local builds for each main push. From 0.1.5, the release gate requires a pinned Apple Development certificate and a stable designated requirement, inspects the packaged DMG, and exercises real certificate-signed and legacy-migration updates. Developer ID/notarization and M5 permission continuity remain unverified; see `docs/updates.md`. |
| 9 | Device pickers in the sidebar, menu bar and Configuration save a persistent device UID. Multi-input devices also save an input channel in Configuration. Explicit channel mapping preserves microphone audio on discrete-channel interfaces without mixing loopback; unavailable channels fail visibly. Missing devices fail visibly without selecting another input; same-input audio reconfiguration recovers without clearing captured audio. Missing or changed inputs report a specific error; see `docs/microphones.md`. The new bundle ID `com.lstudlo.app.airdraft` imports legacy preferences and credentials. |
| 10 | Live Accessibility/microphone state, running-copy diagnostics, and a separate Debug identity. The ad-hoc release defect is removed from 0.1.5; users migrating from older builds may need to grant access again. Later releases must preserve the approved signing identity. Verification on the affected M5 remains outstanding; see `docs/accessibility.md`. Unsupported Accessibility writes can fall back to paste after verifying an unchanged destination; accepted writes get a bounded verification wait, with no replay after an uncertain result. Cross-app acceptance remains outstanding. Keychain navigation/background reads are silent; selected-key approval is explicit, migration preserves inaccessible current entries, and key editors report write failures. Pending microphone requests cancel with shortcut release. See `docs/keychain-access.md`. |
| 11 | Implemented: the sidebar uses macOS frosted material beneath a darker neutral layer that stays 70% opaque through the upper half and fades to fully opaque at the bottom; Reduce Transparency makes the whole background opaque; the sidebar opens the real License sheet in all builds, showing the self-built edition or official trial/license state without sample account data. The sheet leads with the sidebar brand mark and one state line, offers a single prominent action per state, and is 440 points wide and as tall as its content. The microphone capsule opens a compact panel of device choices (336 points wide, 32-point rows, 8-point inset), each with a live ten-cell input meter on its right. Decorative descriptions and the separate meter card are removed; permission actions and device errors appear only when needed. Each eligible device is monitored once, System Default shares its device's meter, and previews stop when the overlay closes or dictation starts. Wired and wireless Continuity microphones stay disconnected with idle meters unless selected, including when System Default resolves to them; switching away stops their preview. Opening the picker no longer starts an unselected iPhone connection. Device choice remains persistent; the level preview retains no audio. |
| Automation | Start, Stop and Cancel Dictation in Apple Shortcuts, plus an optional executable script output destination. Final text goes through standard input once, with a timeout and no automatic retries. Destination choices are fixed per recording; history keeps delivery status and failures. See `automation.md`. |
| Live preview | Optional on-device Apple Speech preview in the recording HUD, with an independent language and explicit asset installation in Models. The final transcript still uses the selected ASR provider. Bounded preview buffering, provisional-text replacement and cancellation cannot interfere with final transcription. |
| Parakeet | Local Parakeet TDT 0.6B v3 INT8 through the existing sherpa-onnx runtime. Explicit model download; English and 24 other European languages. No Chinese support. See `parakeet.md` for model attribution and validation. |
| Audio history | Opt-in local WAV retention (1, 7 or 30 days, or until deleted), playback and retranscription with current model/profile. Retranscription opens a copyable review without changing the original or inserting elsewhere. Turning retention Off removes saved audio while keeping text. |
| Offline cleanup | Apple Intelligence is available in Models → Refinement on supported Macs running macOS 26+. It uses the on-device Foundation Models system model, existing profiles and shared prompts, without keys or a separate server. Readiness is shown before capture; refinement errors preserve the raw transcript. |
| Production repairs | Local remediation adds recording prerequisites, session ownership, verified insertion targets, incomplete-response rejection, bounded refinement, audio retry, explicit storage failures, engine leases, persistent downloads, complete history pagination and calendar-day statistics. Known missing permissions, credentials, devices and models block capture before it starts. Core regression tests and render checks pass; public notarization and physical end-to-end acceptance remain separate release requirements. See `production-repairs.md`. |
| Local verification | `pnpm build:app` and `pnpm test:local` use the pinned local Moon tool and shared Xcode mutex; generation accepts installed or existing bundled XcodeGen. The credential-free suite includes onboarding and isolated licensing contracts. Debug E2E reports failed refinement separately from successful raw-text recovery and exits nonzero on verification/report failures. Credential-free Debug E2E fixtures isolate preferences, history, audio and downloaded models. The allowlisted core suite, native behavior/lifecycle fixtures and disposable updater checks support repeated testing. Live and unavailable coverage remain explicit; see `local-e2e.md` and the [2026-09-26 audit](testing/2026-09-26-local-e2e.md). |
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
- Descriptions use `.supportingText()`: 11 pt regular in the native secondary color,
  beneath 13 pt setting titles. Prefer one short phrase; remove redundant copy.
  Keep privacy, cost and recovery guidance explicit, with extended explanations
  in existing details disclosures. Do not shrink editable text or primary content.
- Error notices place the message and action in one horizontal row. Short setup
  errors fit on one line; long diagnostics wrap beside the action. Separate every
  expanded Home readiness row with `RowDivider`, even without a trailing button.
- Profiles uses one compact picker in its Profile section heading, like the
  provider pickers on Models, instead of a secondary list column. Names carry the
  picker; profile-specific icons add no useful distinction. The Name field commits
  on Return or when focus leaves it, and an empty draft restores the saved name.
- Every page header shows the destination name on the left and its controls on
  the right, centered in a 32 pt row with 24 pt above and 12 pt below. Keep the
  header fixed while its backdrop blur covers the entire header and the 24 pt
  content inset beneath it, with a 4 pt outer feather. Text at the bottom of the
  inset must already be lightly but visibly blurred at about 1 pt radius; increase
  quadratically to 32 pt at the top. Preserve background color instead of fading
  in a tint or opaque material. Keep header controls sharp. Suppress
  hard scroll-edge separators; Reduce Transparency uses a solid fill. Keep the 24 pt
  content inset inside each scroll view so it does not block the underlap. The collapsed sidebar toggle occupies its
  own space before the heading; collapsing does not shift content vertically.
  Search and filter controls share one compact style; Profiles keeps
  its create button and action menu together in the right-side control group.
  The sidebar microphone control is a padded capsule above the footer, without
  a separating line. It opens a compact device list (336 pt wide, 32 pt rows, 8 pt inset, left-aligned with
  the capsule) with a ten-cell live level meter at the
  right of every row, without decorative descriptions or a separate meter card. A bottom-left license button opens the native License sheet;
  it shows the actual distribution and access state, never sample subscription data, led by the sidebar brand mark and one state line with a single prominent action per state. The sidebar
  uses macOS blur beneath a darker neutral layer over a transparent window
  background. The layer stays 70% opaque through the upper half, then fades to
  full opacity at the bottom. Reduce Transparency makes the whole background
  opaque. Content stays fully opaque.
- The expanded sidebar is 170 pt wide. Collapsing leaves an icon rail whose width is the unchanged brand
  width plus 20 pt on each side, about 91 pt total. Center navigation, microphone
  and available account icons horizontally without changing their vertical
  positions, row heights or group spacing. Hide labels and footer text while
  retaining tooltips and accessible names. The expand toggle sits outside the rail
  in the content titlebar, with its symbol aligned to the page leading inset and
  its center on the window-button centerline. Page content starts below the shared
  sticky page header in both sidebar states.
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
  grouping and search results, and cards continue to load lazily. Returning the
  cards to the top restores the timeline's first day heading, including when the
  first entry was already active. Prepare and cache labels, day groups, text
  previews and audio availability outside rendering. Scrolling must not regroup
  the history, scan all records or measure hidden full transcripts. Preserve the
  complete text for Copy and expansion. Clip native text drawing and selection to
  the measured text area so they cannot cover expansion or card controls. Verify
  drawing bounds as well as line counts. See `history-performance.md` for evidence.
- Pointer clicks clear stale control focus while clicks inside the active text
  editor preserve editing and selection. Keyboard and VoiceOver dismissal of an
  overlay return focus to its trigger; mouse dismissal leaves no trigger outline.
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
