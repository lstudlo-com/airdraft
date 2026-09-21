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
| 1 | Airdraft branding throughout the app, CLI and developer tools; Superwhisper-style main window (sidebar, cards, key caps, theme + HUD tiles); dark recording pill at bottom centre with Classic / Mini / None. Existing settings and data survive the rename. Onboarding still missing. |
| 2 | Done: `Transcriber` / `Refiner` protocols, `EngineFactory`, per-stage config. Ten speech engines kept (see `docs/model-atlas.html`); everything else was removed on purpose. |
| 3 | Provider presets, `/models` picker, one-click anonymous model downloads. Codex and Claude Code discover their model lists and per-model thinking levels from the installed CLI; custom model IDs remain available. CLI model and effort choices survive provider switches. First-run onboarding not yet built. |
| 4 | Done: `RefinementProfile` + `ProfileStore`, Profiles tab, prompt preview. |
| 5 | Done: add / delete in Profiles tab; built-ins cannot be deleted. |
| 6 | Done: per-profile reset, base-rules reset, "Reset all profiles to defaults". |
| 7 | Sparkle 2.10.0 adds manual checks, daily checks and optional automatic downloads. Main pushes test committed sources and build the DMG locally; GitHub publishes the verified draft for the matching commit. See `docs/updates.md`. |
| 8 | Device pickers in the toolbar, menu bar and Configuration save a persistent device UID. Missing devices fail visibly without selecting another input; interruptions stop recording. `com.lstudlo.app.airdraft` imports legacy settings and credentials. |
| 9 | Live Accessibility/microphone state, shared setup and recovery instructions, running-copy diagnostics, and a separate Airdraft Debug identity. Ad-hoc public updates still require reauthorization when their signing identity changes. Developer ID signing and verification on the affected second Mac remain outstanding; see `docs/accessibility.md`. |

## Verification rules

- Every UI change is rendered with `--render-window all` and looked at before it is reported.
- Every pipeline change is exercised with `AIRDRAFT_SELFTEST=<wav>` and confirmed in the log and history.
- Shortcut backends log their registration; "Carbon hotkey registered" must appear at start.

## Non-goals for now

Windows / iOS, App Store distribution (Accessibility rules it out), team features.
