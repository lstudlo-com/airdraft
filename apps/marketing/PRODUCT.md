# Airdraft marketing website

## Intent

Help an individual Mac user understand Airdraft, trust it, and reach the real
build instructions. As an open-source project funded by donations and, later, a
paid service, the site must also make the source, the license and the ways to
support the project easy to find once they exist.
This is a marketing surface, separate from the native app's settings UI.
The initial deployment at `airdraft.app` must stay private behind Cloudflare
Access, restricted to the owner's L Studio Google identity.
The primary audience values a quiet Mac utility, control over their models and
their data, and less typing.
Positioning: Airdraft is a late entrant among dictation apps, so the site does
not lead with what every dictation app does (cleaning up ums). It leads with
what sets it apart: a thoughtful, premium, native macOS app that works without
a paid subscription.

## Product truth

- The product name is "Airdraft", as in the app's bundle display name and window title.
- Airdraft is a menu-bar dictation app for Apple silicon, macOS 15 or later. Apple SpeechAnalyzer needs macOS 26.
- Hold the shortcut, speak, and release to insert text at the cursor. The default shortcut is Control-Option (⌃⌥); users can change it in Configuration.
- Speech recognition and refinement choose providers independently; vocabulary corrections apply last.
  The pipeline lists on the homepage mirror `ASRProviderKind`, `LLMProviderKind` and the
  local engines kept in the root `CLAUDE.md`; update them together.
- Both steps can stay local with local engines. Cloud speech receives audio; cloud refinement and the Claude Code / Codex CLIs receive the transcript. API keys live in the macOS Keychain. Local models download only when chosen on the Models page.
- The local pipeline lists include Parakeet TDT v3 speech and Apple Intelligence
  refinement. Parakeet supports European languages, not Chinese; Apple Intelligence
  requires a supported Mac with macOS 26 or later and system availability.
- Built-in profiles are Clean, Concise, Summary and Verbatim; they are editable and resettable. The website's sample is authored text, not a live microphone or model benchmark.
- Version 0.2.0 is a personal-use release signed with Apple Development and is not
  notarized. A supported, notarized public installer is not available yet. The paid
  option will be a ready-to-run app (no Xcode needed); its price and date are not
  announced. "Get Airdraft" actions lead to the pricing page; source actions lead
  to the repository and its build instructions.
- Airdraft is open source and donation-supported. `src/data/site.ts` controls optional content:
  the Buy Me a Coffee URL (pricing and support pages), the license (footer, only once a LICENSE
  file exists), and the paid plan (pricing page, only once it is real). Until set, donation
  actions show a disabled "Not set up yet" key and the paid plan reads "Not announced".
- Pricing may state only: the open-source build is $0 with no locked features; donations
  unlock nothing; cloud providers bill users directly. Cloud speech prices come from the app's
  model catalogue (`src/data/pricing.ts`), dated, one default model per provider.
- Support troubleshooting comes from the root README's First run and Known issues sections.
- History is local, searchable, grouped by day, and flips between refined and original text.
  If refinement fails or times out, the raw transcript is inserted.
- Changelog entries distinguish unreleased development, dated source history and
  personal-use releases from supported public distribution. Never invent a release
  version or publication date, or imply that a version number proves notarization.
- Do not invent pricing, performance measurements, testimonials, usage counts, licensing, or a download URL.
- Do not publish app renders that contain personal profiles, device names, history or usage counts.

## Design brief

The app window's own neumorphism, translated value for value from the native
views: neutral gray chrome around a rounded mid-tone island, raised cards and
capsule keys, pressed wells, light from the top left in light and dark mode. No
hue anywhere except the app's status dots; one graphite key marks the primary
action. Raised keys and recessed wells explain the interaction. Keep readable
contrast, a 13px text floor, visible keyboard focus, reduced-motion behavior,
and useful content without JavaScript. Mac visitors read SF Pro, the app's face.
The first viewport is the hero alone, at every window size: the positioning
headline, the "Get Airdraft", source and sample actions, two quiet facts (open
source; macOS 15+ on Apple silicon), and Home's waveform card from the app
(decorative bars, no metrics, the app's first-run caption); no paragraph.
Nothing else shows until the visitor scrolls. The headline says transcription,
not dictation: Airdraft records live but transcribes and refines after release.
The shortcut is shown in the hero caption and the bento. The close must state
availability plainly and offer every path: build free, the paid app, donate.
Every line of copy must inform a decision or explain the product; no taglines,
no narration, no restating a heading. Build pages from `src/components/ui/`.
The logo is the app's outlined wordmark. Both waveforms, the logo's and the
hero's, respond to the visitor. Scroll motion tells the dictation story (speak, refine, insert) but
the page reads fully without it. Bento tiles are one graphic and one line.

## Delivery

An independent Moon project at `apps/marketing`, using Astro and Cloudflare Workers static assets.
Use a shared pnpm workspace and lockfile. Avoid changing the native app's build layout.
Deploy to the `lstudlo` Cloudflare account and bind `airdraft.app` only after
Cloudflare Access is configured. Keep Worker development and preview URLs disabled.
