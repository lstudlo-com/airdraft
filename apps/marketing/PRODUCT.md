# Airdraft marketing website

## Intent

Help an individual Mac user understand Airdraft, trust it, and choose how to get
it: build the open source for free, or buy a one-time license for the official
ready-to-run app. The site must make the source, the license terms and both
paths easy to find (vault: `Strategy/Business Model`).
This is a marketing surface, separate from the native app's settings UI.
The initial deployment at `airdraft.app` must stay private behind Cloudflare
Access, restricted to the owner's L Studio Google identity.
The primary audience values a quiet Mac utility, control over their models and
their data, and less typing.
Positioning: Airdraft is a late entrant among dictation apps, so the site does
not lead with what every dictation app does (cleaning up ums). The hero names
the jobs (speak into any app, transcribe meetings) and the privacy-minded user
who wants processing that can stay on the Mac.
The site addresses an international audience in the app's interface
languages: dictate in your own language, mixing in English or technical
terms, with speech and refinement on the Mac or with your own provider. The
English headline is "Speak in your language, English terms and all.
Transcribe your meetings." Every claim stays true for an English-only user.
Mixed Chinese and English remains one guide and one homepage example among
others; dictation into AI coding agents (Claude Code, Codex, terminals) that
reuses an existing subscription for refinement remains the second job shown.
The Traditional Chinese positioning is unchanged:
中英混著講，說完就貼上；會議也能整理成逐字稿，一次買斷. The segment decision
of 2026-10-22 (vault: `Strategy/`) predates this international positioning;
the vault records the current decision. Meetings, mixing English into
another language, and Claude Code / Codex refinement are shown on the
homepage, not only in the changelog, guides or pricing. "一次買斷" and its
translations describe the license terms; never imply the official app is on
sale before `siteLinks.checkout` is set.

## Product truth

- The product name is "Airdraft", as in the app's bundle display name and window title.
- Airdraft is a menu-bar dictation app for Apple silicon, macOS 15 or later. Apple SpeechAnalyzer needs macOS 26.
- Hold the shortcut, speak, and release to insert text at the cursor. The default shortcut is Control-Option (⌃⌥); users can change it in Settings.
- Speech recognition and refinement choose providers independently; vocabulary corrections apply last.
  The pipeline lists on the homepage mirror `ASRProviderKind`, `LLMProviderKind` and the
  local engines kept in the root `CLAUDE.md`; update them together.
- Both steps can stay local with local engines. Cloud speech receives audio; cloud refinement and the Claude Code / Codex CLIs receive the transcript. API keys live in the macOS Keychain. Local models download only when chosen on the Models page.
- The local pipeline lists include Parakeet TDT v3 speech and Apple Intelligence
  refinement. Parakeet supports European languages, not Chinese; Apple Intelligence
  requires a supported Mac with macOS 26 or later and system availability.
- Built-in profiles are Clean, Concise, Summary and Verbatim; they are editable and resettable. The website's sample is authored text, not a live microphone or model benchmark.
- Releases so far are personal-use builds signed with Apple Development and not
  notarized. A supported, notarized public installer is not available yet.
  "Get Airdraft" actions lead to the pricing page; source actions lead to the
  repository and its build instructions.
- The official ready-to-run app (no Xcode needed) is sold as a one-time license
  for personal use: **$29 for one Mac, $49 for up to three Macs**, in US dollars
  before applicable tax. Both licenses have every feature and differ only in how
  many Macs can be active at once; a Mac can be deactivated to move the license.
  Licenses don't expire, updates to the purchased version are included, and the
  app offers a 14-day full-feature trial the user starts. While checkout is
  closed there is no build to try, so copy says the trial comes with the
  official app once it is on sale (`siteLinks.checkout` switches it). `licenses`
  in `src/data/site.ts` carries the prices and plan IDs; each language's
  `license` and `pricing` copy in `src/i18n/messages` words them, including
  the `licenseIncludes` lists. Change them only with the Polar products.
  Self-built editions stay complete and free.
- Purchase is not open yet (the merchant account is in test mode). License actions
  read "Not on sale yet" and stay disabled until `siteLinks.checkout` holds the
  production checkout link from `scripts/licensing-config.json`. The homepage's
  Get Airdraft section says so in every language.
- `src/data/site.ts` also controls optional content: the Buy Me a Coffee URL
  (support page) and the license link (footer). Until set, donation actions show a
  disabled "Not set up yet" key.
- Pricing may state only: the open-source build is $0 with no locked features; the
  license terms above; donations unlock nothing; cloud providers bill users directly;
  that both editions include dictation and Meetings (the same app); a link to the
  dated app comparison guide; and a dated cost comparison. That comparison prices one stated workload (dictations,
  seconds, token budget) for three Airdraft setups (all local; Parakeet with Cerebras
  `qwen-3.8-27b`; Groq Whisper Large v3 Turbo with Cerebras) against Wispr Flow Pro
  and Typeless Pro. `src/data/pricing.ts` holds the workload and list prices and
  derives every total; change inputs there, never the totals. Groq's rate comes from
  the app's model catalogue; Cerebras, Wispr Flow and Typeless from their pricing
  pages, rechecked whenever the date changes. Show the assumptions beneath the table
  and say what leaves the Mac for each cloud setup.
- Support troubleshooting comes from the root README's First run and Known issues sections.
- Meetings records app audio from all apps or one app
  plus an optional microphone through ScreenCaptureKit, with no screen frames,
  or imports one audio or video file with a single audio track, up to two hours.
  Transcription uses a chosen local model or Soniox (upload only after Upload and
  Transcribe). Speaker labels are optional local estimates (Speaker 1, …),
  renameable, never guessed names; overlapping voices are not separated. Exports
  are TXT, JSON, SRT and VTT. There is no echo cancellation. Claims follow
  `docs/meeting-recording.md` and `docs/media-transcription.md`; no accuracy
  measurement is published.
- Chinese: Qwen3-ASR, SenseVoice and FireRedASR2 run locally. First-run setup
  recommends Qwen3-ASR 1.7B on a Mac set to Chinese (SenseVoice on 8 GB or
  less, with Qwen still offered); English gets Parakeet TDT v2 (Qwen3-ASR 1.7B
  as the multilingual alternative); Japanese and Korean get Qwen3-ASR 1.7B
  (Whisper Large v3 Turbo first on 8 GB or less); other languages get Whisper
  Large v3 Turbo. The Models page labels Qwen3-ASR 1.7B "Best for mixed Chinese
  and English" and describes SenseVoice as "Small and fast. Weaker with English
  terms in Chinese speech." 0.11.0 and earlier recommended SenseVoice
  for English, Japanese and Korean, and 0.10.2 suggested it on a Mac set to
  Chinese too; name them only where the older recommendation matters.
  "SenseVoice" is the original multilingual SenseVoiceSmall (163 MB). 0.11.0 and
  earlier installed the WSYue Cantonese fine-tune under that name; the app now
  shows it as "SenseVoice Cantonese" (166 MB), keeps it working for existing
  installs and lists it only while it is in use. Measurements of the old
  artifact stay as dated history labelled SenseVoice Cantonese.
  Qwen3-ASR and Whisper downloads are pinned to verified revisions from 0.11.0.
  Chinese script converts characters to Traditional by default and can be
  Simplified or Auto; Taiwan vocabulary comes from refinement. Parakeet does
  not support Chinese.
- Mixed-language results come only from Airdraft's own measurement in
  `eval/mixed-asr` (2026-10-21, one M4 Pro, ASCEND plus Taiwan-style TTS;
  SenseVoice from its 2026-10-24 follow-up of the original model),
  held in `src/data/mixed-asr.ts`. Quote it as Airdraft's measurement with its
  date, method link and limits (five Hong Kong/Mainland speakers, synthetic
  Taiwan voice, one Mac, refinement off). Never generalize it into an accuracy
  claim or compare it with other apps.
- English, Japanese and Korean results come only from Airdraft's own
  measurement in `eval/eja-asr` (2026-10-24, one M4 Pro, Google FLEURS read
  speech, 60 clips per language; the original SenseVoice from the same-day
  follow-up), held in `src/data/eja-asr.ts` and shown in
  the offline setup guide. Quote model output with its date, method link and
  limits (read Wikipedia sentences, not dictation; wide intervals; one Mac;
  refinement off). Never generalize it into an accuracy claim, a ranking or a
  comparison with other apps.
- Coding agents and terminals: Airdraft pastes once and never presses Return.
  Terminal and iTerm2 are confirmed by read-back. Warp, Zed, Ghostty, kitty,
  Alacritty and WezTerm draw their own text: from 0.11.0 History marks the
  paste "Pasted, unconfirmed" without an error (0.10.2 reported it as
  unconfirmed and kept the text on the clipboard). Claude Code / Codex
  refinement runs the signed-in CLI without tools in a temporary folder and
  sends the prompt to Anthropic or OpenAI; destination-specific prompt rules
  need Read app context, which is off by default.
- The app follows the macOS language setting. Traditional Chinese ships from
  0.11.0 and Simplified Chinese from 0.12.0; builds through 0.10.2 are English
  only, and the translated guides say so. Spanish, Japanese, French, Brazilian
  Portuguese, Russian, Arabic, Hindi and Indonesian interfaces exist in the
  app's catalogs (or the translators' catalog exports) but not yet in a
  published release; their pages say the released app still shows English
  (`interfaceReleased` in `src/i18n/index.ts`; turn a language on when its
  release is published). Translated pages quote app labels (buttons,
  settings, HUD states, Refined/Original, profile names, Meetings controls)
  with the app's values for that language from its string catalogs
  (`src/data/app.ts` for shared labels); a label without a catalog entry stays
  as the app shows it. The English and Traditional Chinese pages keep the
  built-in profile names Clean, Concise, Summary and Verbatim in English; the
  app now localizes them, and the other languages use the catalog names. The
  homepage screenshots are rendered from a Debug build of the current release:
  English for English pages, zh-Hant for `/zh-tw/`; the other languages show
  the English render and say so until theirs are rendered.
- History is local, searchable, grouped by day, and flips between refined and original text.
  If refinement fails or times out, the raw transcript is inserted.
- Changelog entries distinguish unreleased development, dated source history and
  personal-use releases from supported public distribution. Never invent a release
  version or publication date, or imply that a version number proves notarization.
  Keep one entry per published product version, grouping rebuilds, with dates in
  Asia/Taipei and links to the published release or original source. Review the
  commits between tags when release notes omit the user-facing changes.
  The page title and release titles have no summary paragraphs: each release
  goes straight into change items with their own descriptions. A version navigator
  follows reading position, and scroll motion respects Reduce Motion.
- Do not invent prices, discounts, dates, performance measurements, testimonials,
  usage counts, licensing terms, or a download or checkout URL.
- Do not publish app renders that contain personal profiles, device names, history or usage counts.
  The homepage's interface section uses the Settings page rendered by
  `scripts/render-app-window.sh` from an isolated empty data directory, in
  English and Traditional Chinese.

## Design brief

The app window's own neumorphism, translated value for value from the native
views: neutral gray chrome around a rounded mid-tone island, raised cards and
capsule keys, pressed wells, light from the top left in light and dark mode. No
hue anywhere except the app's status dots; one graphite key marks the primary
action. Raised keys and recessed wells explain the interaction. Keep readable
contrast, a 13px text floor, visible keyboard focus, reduced-motion behavior,
and useful content without JavaScript. Mac visitors read SF Pro, the app's face.
The first viewport is the hero alone, at every window size: the positioning
headline (the jobs, in three phrases: "Speak in your language, English terms
and all. Transcribe your meetings."; in Traditional and Simplified Chinese the
audience and jobs: 中英混著講，說完就貼上。會議也能整理成逐字稿。),
the "Get Airdraft", source and sample actions, three quiet facts (open source;
on the Mac or with your own provider; macOS 15+ on Apple silicon), and Home's waveform card from the app
(decorative bars, no metrics, the app's first-run caption); no paragraph. The
caption works: holding ⌃⌥ or pressing the waveform plays a pretend dictation
that adds a bar, without recording anything.
Nothing else shows until the visitor scrolls. The headline says transcription,
not dictation: Airdraft records live but transcribes and refines after release.
The shortcut is shown in the hero caption and the bento. The close must state
availability plainly and offer both paths: build free, or the license (one card
with a 1 Mac / 3 Macs choice). Donations live on the support page.
Every line of copy must inform a decision or explain the product; no taglines,
no narration, no restating a heading. Build pages from `src/components/ui/`.
The logo is the app sidebar's neumorphic mark (`SidebarBrandMark`): a raised
capsule with carved waveform grooves and a caret, without lettering. The hero's
waveform responds to the visitor. Pricing, Support and Changelog open with the
same page title block: one size, one top inset and the full content width. Scroll motion tells the dictation story (speak, refine, insert) but
the page reads fully without it. Motion stays physical: objects rise from and
sink into the surface and selections slide; nothing tilts or flies through
perspective. Bento tiles are one graphic and one line.

## Search and product guides

The homepage links to a guide hub and seven distinct guides: offline setup
(choosing a model for your language), mixed Chinese and English dictation
(with the measurement above), dictating prompts into Claude Code, Codex and
terminals, local/cloud data flow, the free
source build versus official app, private meeting transcription, and a dated
comparison with VoiceInk, Handy, Typeless and Apple Dictation on macOS 27. The comparison cites each product's own pages
or source with check dates, says where competitors are better, marks unknown
cells "Not checked", includes whether each can be downloaded and tried today,
and lists Airdraft's current gaps. Where its table does not fit, each product
becomes a block of labelled rows instead of scrolling sideways. Recheck every row before changing
its date; never add rankings, reviews or benchmark numbers. Keep their
answers in static HTML, with descriptive internal links, visible breadcrumbs and
semantic comparison tables. The first viewport remains the hero alone.
Cloud refinement can receive enabled app context as well as transcript and
instructions; some speech providers receive language and vocabulary hints.
Local processing claims apply to the selected models, not downloads, updates or
licensing traffic. Guides must retain these boundaries and active-profile overrides.

`SEARCH.md` owns the search implementation contract and console/submission commands.
The shared layout emits canonical URLs, site/application/page entities and a
1200×630 sharing image, plus breadcrumbs where visible. Do not invent reviews,
ratings or purchasable offers. Preserve current crawler access, sitemap exclusions
and snippet eligibility. `llms.txt` is an optional navigation directory, not a
Google ranking signal. The changelog feed uses the existing release data.

Builds run `scripts/check-search.py` with Python 3 (standard library only).
The check enforces sitemap/canonical parity, internal links, crawler permissions,
metadata, structured data, feed targets and social-image dimensions. HTTP preview
checks also verify response headers, canonical redirects, assets and real 404s.
IndexNow submission is explicit, defaults to a no-network dry run, and checks the
published key and HTML before sending. It does not run during build or deployment.

## Languages

The site's languages follow the app's interface languages. English pages live
at the root; each translation lives under `/<code>/` with the English slug:
`zh-tw` (Traditional Chinese, Taiwan), `zh-cn` (Simplified Chinese), `es`,
`ja`, `fr`, `pt-br`, `ru`, `ar` (right to left), `hi` and `id`.
`src/i18n/locales.json` lists each language's code, BCP 47 tag, Open Graph
locale, own name, direction and translated paths; the search check, sitemap,
analytics allowlist and i18n helpers all read it. Traditional Chinese
translates the homepage, pricing, and the mixed-language, coding-agent,
meeting and comparison guides; every other language translates the homepage
and pricing. Copy lives in one file per language in `src/i18n/messages`.
Translations use natural wording for their audience (Taiwan wording for
zh-tw, Mainland interface terms for zh-cn: 设置, 快捷键, 润色, 模式) and keep
Airdraft, provider and model names in English; app labels follow the app's
interface in that language. Prices stay in US dollars from shared data.
Untranslated pages (support, changelog, privacy, the guides a language lacks)
stay English and are marked with the language's "(English)" word
(（英文）, （英語）, (inglés)…) where a translated page links to them,
including the header, phone menu, footer and guide cards. The header's globe
key (and the phone menu's Language row) opens a language menu listing every
language in its own name: this page in that language, or that language's
homepage, noted, when this page is not translated. The footer lists the same
links.

## Delivery

An independent Moon project at `apps/marketing`, using Astro and Cloudflare Workers static assets.
Use a shared pnpm workspace and lockfile. Avoid changing the native app's build layout.
Deploy to the `lstudlo` Cloudflare account and bind `airdraft.app` only after
Cloudflare Access is configured. Keep Worker development and preview URLs disabled.

## Website analytics

PostHog measures consented website visits, acquisition, performance and explicit
pricing/source/build/guide/demo/plan/checkout intent. Keep native dictation data outside
this integration. Collection is disabled until configured and allowed, honors
GPC/DNT, and never enables replay, autocapture, text capture or person profiles.
The privacy page explains the data and provides revocation. Clicks do not prove
installs or purchases. See `ANALYTICS.md` for event and deployment contracts.
The Mac app's own opt-in usage data and crash reports are separate (official builds
only, same PostHog project, tagged `app=airdraft-mac`); the privacy page's
`#app-telemetry` section must match `docs/telemetry.md` in the repository.
