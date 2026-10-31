# Airdraft for iPhone

The iPhone app (AD-141): speech ▸ optional refinement ▸ text, recorded in the app
or requested from the Airdraft keyboard in any app. It is not a port of the Mac
app: iOS has no cursor insertion, global shortcuts or other apps' audio.

This file is the iOS contract. These root `CLAUDE.md` sections apply here too:
Maintainer environment, Checkouts and branches, Localization (languages, catalog
rules, terminology), Recording and recovery invariants (recording limits),
Speech language compatibility, Local speech output guards, Refinement fidelity,
Secrets, and the Swift 6 rules in Rules. These do not: Local releases, Sparkle,
official-build licensing, telemetry, hotkeys, cursor insertion and delivery,
the HUD, the menu bar, onboarding steps, and the Mac window and sidebar rules.

Read `PRODUCT.md` before changing behavior and `DESIGN.md` before changing UI.

## Layout and commands

- `project.yml` (XcodeGen) defines `Airdraft` (app), `AirdraftKeyboard`
  (keyboard extension), `AirdraftWidgets` (Live Activity and controls) and
  `AirdraftiOSTests`. `AirdraftiOS.xcodeproj` is generated and git-ignored;
  `scripts/generate-project.py` uses the root's pinned XcodeGen and restores the
  root `Package.resolved` into it, so both apps build the same pinned graph.
- moon project `ios` (`moon.yml`): `generate`, `build` (simulator), `test`
  (`scripts/test.py`, an available iPhone simulator), `localization`. Root
  scripts: `pnpm build:ios`, `pnpm test:ios`. Xcode tasks share the
  `airdraft-xcode` mutex with the Mac app.
- `Airdraft/` app sources, `Keyboard/`, `Widgets/`, `Shared/` (compiled into
  the targets that list them in `project.yml`), `Tests/`, `Config/` (signing).
- `.github/workflows/ios.yml` builds and tests on the simulator; the Mac CI
  ignores `apps/ios/**`, and `release.py` treats `apps/ios/` like the website.

## Architecture

- `Packages/AirdraftCore` builds for iOS 26. Mac-only code is in
  `#if os(macOS)`; iOS adds its own `AudioRecorder` (with a standby input and
  a streaming mode that retains nothing) and `MobileDictation`.
- `MobileDictation` (Core, tested on the Mac) is the iOS flow. It keeps the
  macOS pipeline's contracts: prerequisites before the microphone opens,
  speech-language and input-limit checks before inference, best-effort
  refinement with the raw transcript on any error, timeout or fidelity
  rejection, the Chinese script converter, then the dictionary last. Change
  both flows together when those rules change.
- `DictationController` runs recording for the app and the keyboard, the
  keyboard session, the Live Activity and delivery. `TranscribeController` runs
  imports and long recordings through Core's `MediaJobRunner`. Only one of them
  holds the microphone at a time.
- New setups start with Apple Speech (no download) and refinement Off. Saved
  choices are never rewritten.

## Keyboard

- A keyboard extension has no microphone. The app records during a keyboard
  session: `startSession()` opens the input in standby (iOS lets a background
  app record only from a running input) for the user's session length, shows a
  Live Activity, and preloads a local model. Sessions are started in the app,
  from Control Center or with the Action Button (`StartKeyboardSessionIntent`).
- The keyboard never opens other apps (Guideline 4.4.1): without a session it
  tells the user to start one. Space, delete, return and the globe key work
  without Full Access; dictation needs Full Access to reach the App Group.
- `KeyboardBridge` is the only channel: state, one request and one delivery in
  the App Group defaults, Darwin notifications as change signals. A delivery
  is inserted only by the keyboard process that made the request, stays at most
  60 seconds and is removed after the receipt. When no receipt arrives within
  `DictationController.receiptTimeout`, the text is copied instead and History
  records it as copied; a confirmed insertion is recorded as inserted.
- Leaving the field cancels a recording made for it.

## Models

- Offer only models that fit an iPhone: Apple Speech, the Core ML Parakeet
  models, Whisper Large v3 Turbo (626 MB) and small GGUF models (SenseVoice
  Small, Whisper Small and Base), plus cloud providers with the user's key.
  sherpa-onnx has no iOS slice and MLX models are not offered.
- None has been measured on an iPhone: show sizes and languages, never accuracy
  or speed claims, and no "recommended" label until a measured iOS rule exists
  (root First-run setup's evidence rule applies).
- Downloads start only from an explicit action. Model files are excluded from
  iCloud backup.

## Verification

- Never record audio in the simulator: it opens the Mac's microphone and raises
  a macOS permission prompt. Recording, keyboard insertion on a device and
  memory use stay unverified until checked on an iPhone.
- Debug-only launch arguments render screens without tapping:
  `-AirdraftScreen home|history|transcribe|settings|speech|refinement|keyboard-setup|onboarding|keyboard`,
  `-AirdraftSampleData` and `-AirdraftKeyboardPhase ready|recording|off`. Boot a
  simulator with `xcrun simctl boot`, install, launch with the arguments, and
  capture with `xcrun simctl io <device> screenshot`. Check light and dark,
  each shipped language (`-AppleLanguages`) and a large content size.
- Unit tests use disposable defaults suites and never record audio.

## Release

- Ships through App Store Connect only. Never create a GitHub Release or a
  `v*` tag for iOS: Sparkle's feed reads the latest GitHub Release. Use
  `ios-v<version>-build.<n>` tags. iOS versions (`MARKETING_VERSION` in
  `project.yml`) are independent of the Mac's.
- Device and TestFlight builds need an Apple Developer team in the git-ignored
  `Config/Local.xcconfig`. Archive with `xcodebuild archive` and
  `-exportArchive`; no fastlane.
- No paywall in the first version: payments are deferred (2026-11-01 decision).

## Guidance files

Keep this file and `AGENTS.md` byte-for-byte identical, like every guidance pair.
