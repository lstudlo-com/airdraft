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
   Refinement Profile whose instructions the user can read and edit.
5. **User-defined profiles.** Users can add, duplicate, and delete their own profiles.
6. **Safe to experiment.** One button restores every built-in profile and the shared
   base rules to defaults; a per-profile reset exists too.

Added 2026-09-21:

7. **App updates.** Signed updates installed on quit without interrupting dictation.
8. **Microphone choice.** Save a specific input as the default across restarts and reconnects.

9. **Clear permission setup.** Show permissions for the running copy, refresh
   after changes, and explain recovery from stale grants and duplicate builds.

## Status

| Goal | State (2026-09-21) |
|---|---|
| 1 | Airdraft branding throughout the app, CLI and developer tools; compact Codex-inspired sidebar with monochrome symbols and quiet selection; native cards, key caps and theme/HUD previews; dark recording pill at bottom centre with Classic / Mini / None. Configuration and Models share equal 16-point card insets, 8-point heading gaps and 20-point section gaps; settings rows add no extra vertical inset. Existing settings and data survive the rename. Onboarding still missing. |
| 2 | Done: `Transcriber` / `Refiner` protocols, `EngineFactory`, per-stage config. Ten speech engines kept (see `docs/model-atlas.html`); everything else was removed on purpose. |
| 3 | Provider presets, `/models` picker, one-click anonymous model downloads. Codex and Claude Code discover their model lists and per-model thinking levels from the installed CLI; custom model IDs remain available. CLI model and effort choices survive provider switches. First-run onboarding not yet built. Refinement includes dedicated Cerebras and Groq options with separate Keychain keys, live model discovery, provider-specific reasoning parameters, and migration of the former Groq server preset. |
| 4 | Done: `RefinementProfile` + `ProfileStore`, Profiles tab, prompt preview. |
| 5 | Done: add / delete in Profiles tab; built-ins cannot be deleted. |
| 6 | Done: per-profile reset, base-rules reset, "Reset all profiles to defaults". |
| 7 | Sparkle checks and verified installation on quit, with local builds for each main push. From 0.1.5, the release gate requires a pinned Apple Development certificate and a stable designated requirement, inspects the packaged DMG, and exercises real certificate-signed and legacy-migration updates. Developer ID/notarization and M5 permission continuity remain unverified; see `docs/updates.md`. |
| 8 | Device pickers in the toolbar, menu bar and Configuration save a persistent device UID. Multi-input devices also save an input channel in Configuration. Explicit channel mapping preserves microphone audio on discrete-channel interfaces without mixing loopback; unavailable channels fail visibly. Missing devices fail visibly without selecting another input; same-input audio reconfiguration recovers without clearing captured audio. Missing or changed inputs report a specific error; see `docs/microphones.md`. `com.lstudlo.app.airdraft` imports legacy settings and credentials. |
| 9 | Live Accessibility/microphone state, running-copy diagnostics, and a separate Debug identity. The ad-hoc release defect is removed from 0.1.5; users migrating from older builds may need to grant access again. Later releases must preserve the approved signing identity. Verification on the affected M5 remains outstanding; see `docs/accessibility.md`. Keychain navigation/background reads are silent; selected-key approval is explicit, migration preserves inaccessible current entries, and key editors report write failures. Pending microphone requests cancel with shortcut release. See `docs/keychain-access.md`. |

## Interface consistency

Standing requirement from Light, reaffirmed 2026-09-21:

- Section cards have equal padding on all four sides: 16 pt, defined once as
  `Theme.cardPadding`. Vertical and horizontal padding must be the same.
- The card owns its outer insets. Settings rows inside it add no vertical padding;
  otherwise the first and last rows make the card look taller than its side insets.
- Configuration and Models use `PageSection` and `SettingsCard`, including
  microphone, updates, permissions, refinement and provider settings. New settings
  sections must use these components too.
- Use shared spacing: 8 pt from a section heading to its content, 20 pt between
  sections, and 12 pt between settings-card children. Keep content spacing separate
  from the card's outer padding. Table headers and rows own their equal 16 pt insets
  inside a zero-padding table container.
- Verify both light and dark appearances and scroll through lower sections. Before
  reporting a released fix, inspect the app built from the exact committed sources;
  a correct rendering of uncommitted changes does not prove the DMG contains them.

## Verification rules

- Every UI change is rendered with `--render-window all` and looked at before it is reported.
- Every pipeline change is exercised with `AIRDRAFT_SELFTEST=<wav>` and confirmed in the log and history.
- Shortcut backends log their registration; "Carbon hotkey registered" must appear at start.

## Non-goals for now

Windows / iOS, App Store distribution (Accessibility rules it out), team features.
