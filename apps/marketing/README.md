# Airdraft marketing

The Airdraft marketing website, initially available as a private preview.
Astro renders static HTML, CSS, and a small
TypeScript demo; Cloudflare Workers serves the generated assets. It is a second
Moon project in the existing repository, not a nested Git repository.

## Development

From the repository root, install the pinned tools with `proto install`, then:

```sh
pnpm install
pnpm dev:marketing       # Astro, http://localhost:4321
pnpm check:marketing     # Astro/TypeScript diagnostics and formatting
pnpm build:marketing     # apps/marketing/dist
pnpm preview:marketing   # build, then Cloudflare's local runtime on port 8787
```

`pnpm exec moon run marketing:build` is the underlying task. Moon remains pinned
to 2.5.5; Node 24.21.0 and pnpm 10.34.5 are pinned in `.prototools`. The root
`package.json` also provides Moon for environments without proto. All JavaScript
packages share the root `pnpm-lock.yaml`; install dependencies from the root.

Use `pnpm --filter @airdraft/marketing format` after editing website files.
The website workflow checks, builds, and dry-runs Wrangler on Linux; it does not deploy.

## Cloudflare origin

Initialized on 2026-09-18 with Cloudflare's C3 CLI and its official
[Astro Framework Starter](https://github.com/cloudflare/templates/tree/main/astro-blog-starter-template):

```sh
pnpm dlx create-cloudflare@2.72.9 apps/marketing \
  --template=cloudflare/templates/astro-blog-starter-template \
  --no-git --no-deploy --no-open --no-agents --no-auto-update
```

Template repository revision at initialization:
`fa7b8572e96fa5ac3bc0b5b4ed20193ed75ce90a`.
The starter's sample blog, fonts, and placeholder images were replaced. Astro
was updated from the template's 5.16.9 to 7.3.3, and unused MDX, RSS, and server
adapter dependencies were removed.

The deployment follows Cloudflare's
[Astro static-site configuration](https://developers.cloudflare.com/workers/framework-guides/web-apps/astro/):
`assets.directory` is `dist`, with no Worker entry point or runtime adapter.
Add `@astrojs/cloudflare` only if a future feature actually needs server rendering.

## Publishing

The deployment target is `https://airdraft.app` in the `lstudlo` Cloudflare
account (`9f4d2a24a5cb90bf0cc79c62e579081f`). Wrangler manages the custom domain
for the `airdraft-marketing` Worker. Both `workers.dev` and version preview URLs
are disabled so they cannot bypass the domain's Access policy.

Initial deployment was verified on 2026-09-18:

- Worker version: `fb1de34f-5d92-46a1-a53a-b27334625603`.
- Access application: `AirDraft — Private Preview`
  (`26665d5c-491d-477f-9a77-f20bad9b12c0`).
- Policy: `AirDraft — L Studio Google only`
  (`6a54dda8-9a0f-4545-abe9-f03c60e97cc3`), requiring both the existing owner's
  exact email and the `使用 lstudlo 登入` Google provider.
- Application sessions last six hours. Other identity providers and Cloudflare
  One Client authentication are disabled for this application.

The header and changelog update was deployed on 2026-09-19 (Asia/Taipei):
Worker version `e4dba1ee-8768-4021-8a35-905014cc6717`, serving 100% of traffic.
The authorized browser verified both routes, and anonymous requests to the pages,
icon, and sitemap still redirect to Access. Alternate Worker URLs remain disabled.
The donation action awaits the owner's confirmed Buy Me a Coffee profile URL.

Cloudflare Access must protect the entire `airdraft.app` hostname **before the
first deployment**. Configure Google as the login provider and allow only the
owner-approved L Studio Google identity. Do not add an Everyone, Bypass, or
unrestricted Google-login policy. Access is configured separately in Cloudflare;
the Wrangler domain configuration does not create an Access application.

1. Verify the Access application, its Google provider, and its restrictive policy.
2. Authenticate Wrangler with the `lstudlo` account.
3. From the root, run `pnpm check:marketing`, then
   `pnpm --filter @airdraft/marketing deploy:check`.
4. Run `pnpm --filter @airdraft/marketing deploy`.
5. Verify unauthenticated requests are intercepted by Access, authorized Google
   sign-in reaches the website, and the alternate Worker URLs remain disabled.

Astro uses `https://airdraft.app` for canonical/social URLs, the sitemap, and its
`robots.txt` reference. `SITE_URL` can override it for a deliberately separate
deployment. This is a build-time setting; changing a runtime Worker variable does
not update generated pages.

For **Cloudflare Workers Builds** connected to this monorepo:

| Setting           | Value                                                                                                    |
| ----------------- | -------------------------------------------------------------------------------------------------------- |
| Root directory    | Repository root                                                                                          |
| Build command     | `pnpm install --frozen-lockfile && pnpm build:marketing`                                                 |
| Deploy command    | `pnpm --filter @airdraft/marketing exec wrangler deploy`                                                 |
| Build variables   | `NODE_VERSION=24.21.0`, `PNPM_VERSION=10.34.5`; production `SITE_URL` defaults to `https://airdraft.app` |
| Build watch paths | `apps/marketing/**`, root package/workspace/lock files, `.moon/**`, `.prototools`                        |

`pnpm --filter @airdraft/marketing deploy:check` rebuilds and runs a local
deployment dry run without publishing. `wrangler.jsonc` includes clean HTML
routing and the custom 404 page. `public/_headers` sets browser security headers
and immutable caching for Astro's hashed assets.

## Content and assets

- `PRODUCT.md` records the audience, factual claims, and release boundary.
- `DESIGN.md` and `.impeccable/design.json` record the implemented visual system
  and component examples for future pages.
- `src/pages/index.astro` owns the homepage (hero and sample, bento, pipeline,
  build). `pricing.astro` and `support.astro` are the Pricing and Support pages.
  `changelog.astro` renders the product history from `src/data/changelog.ts`. Add
  entries newest first and keep unpublished changes explicitly marked as unreleased.
  `design.astro` is an unlinked, `noindex` component reference at `/design/`,
  excluded from the sitemap.
- `src/components/ui/` holds the reusable components: `Brand`, `Button`,
  `Section`, `Surface`, `Chips`, `Keys`, `Hud`, `Waveform`, `BentoTile` and
  `Disclosure`.
  Use them for new pages;
  DESIGN.md documents their props.
- `SiteHeader.astro` and `SiteFooter.astro` are shared by every page.
  `src/data/site.ts` owns the GitHub, build-instruction and issue destinations,
  the two licenses (`licenses`, `licenseIncludes`: $29 for one Mac, $49 for up to
  three; change them only with the Polar products), and optional values that stay
  disabled until they are real: the production checkout link (`checkout`, from
  `scripts/licensing-config.json` once payments are live), the Buy Me a Coffee
  URL and the license link. `src/data/pricing.ts` copies cloud speech list prices
  from the app's model catalogue; update both together.
- `src/components/DictationPreview.astro` and `src/scripts/preview.ts` implement
  an explicitly labelled sample that plays once when it scrolls into view. Its HUD
  copies the app's `IndicatorPanel` states (timer, Decoding, Refining). It does not
  record audio, call an API, or imply measured timing.
- The homepage's provider lists mirror the app's provider enums. Update them when
  an engine is added or removed.
- `src/styles/global.css` translates the app window's material value for value
  (`Theme`, `SoftControls`, `NeumorphicSurface`, `HomeHero`, `IndicatorPanel`) for
  light and dark mode. `scripts/check-neutral.mjs` runs in `pnpm check` and fails
  on any colour with a hue; the app's three status-dot colours are the only
  exception.
- The hero is Home's waveform card (`HeroCard.astro`, `ui/Waveform.astro`); its
  bars are decorative, not data. `src/scripts/dictate.ts` makes its caption work:
  holding ⌃⌥ (or pressing and holding the waveform) plays a pretend dictation
  that adds a bar; nothing is recorded. `src/scripts/waveform.ts` copies the
  app's hover magnification, `src/scripts/segmented.ts` slides every segmented
  picker's thumb, and `src/scripts/keys.ts` sinks ⌃ and ⌥ keycaps while the
  visitor holds those keys.
- The sticky header (`SiteHeader.astro`) draws the app's progressive header blur
  with six stacked `backdrop-filter` layers; see DESIGN.md.
- The mark (`ui/Brand.astro`) is the app sidebar's `SidebarBrandMark`
  (`Sources/App/Views/MainWindow.swift`) in CSS: a raised capsule with carved
  grooves and no lettering. Change it together with the Swift view.
- `uv run apps/marketing/scripts/render-brand.py` writes neutral capsule SVGs to
  `public/brand/` (`airdraft-mark.svg`, and `airdraft-logo.svg` with the app
  wordmark's lettering) for use outside the site. They are not the site's logo.
- `scripts/render-app-icon.swift` writes the website's `airdraft-icon.png` and
  `favicon.png` along with the app's icon set.
- Motion: `src/scripts/voice.ts` lifts the hero's waveform with pointer and scroll
  speed; `src/scripts/story.ts` runs the homepage's entrance rises and graphic loops
  with GSAP and ScrollTrigger (`gsap` is a dependency under GSAP's no-charge
  standard license). Both do nothing with reduced motion, and every element's
  resting CSS is its final state.
- Bento tiles use `ui/BentoTile.astro` (one graphic, a title, one line); the provider
  section is `PipelineStory.astro` (one board: Speech, Refinement and Insertion
  columns, each with its own place choice and provider table); the
  homepage close is `GetAirdraft.astro`: the source build beside `LicenseCard.astro`,
  which the pricing page shares.
- Text uses SF Pro through the system font stack on Apple devices. Inter is
  self-hosted through `@fontsource-variable/inter` as the fallback elsewhere, under
  its included SIL Open Font License, copied to `public/fonts/inter-OFL.txt`; it is
  only downloaded where the system face is missing. No third-party font requests
  are included. Optional PostHog website analytics
  require consent and an explicit production build configuration; see
  [ANALYTICS.md](ANALYTICS.md). Cloudflare can inject its own browser metrics
  according to the zone's settings.
- The GitHub action is intentional: no binary release or product license has
  been invented. Change the CTA only after a real distribution URL is available.
- Do not publish app window renders made from a personal profile: `--render-window`
  uses the real profile store, device name and dictation count.

## UI verification

Check the homepage, pricing, support, changelog, `/design/` and the custom 404 in the
browser at desktop and mobile sizes, in both light and dark appearance.
Exercise the autoplay, Run again, Stop mid-run, all three profile buttons (the
thumb must land on the selected one), the license card's 1 Mac / 3 Macs choice
(pointer and arrow keys, with and without JavaScript), the hero waveform's hover,
the hero's hold-to-dictate (⌃⌥ and press-and-hold; a third key cancels), the
sticky header's blur over scrolled content, the provider board's choices (pointer, arrow keys, without JavaScript),
the FAQ's open and close,
and anchor links; check keyboard focus and reduced motion (no autoplay, immediate
result). The static example and navigation
remain useful with JavaScript disabled.
