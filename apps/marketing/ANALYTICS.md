# Website analytics

PostHog measures the website's acquisition and intent funnel. This integration
does not instrument the macOS app. A source link is not an install, a checkout
click is not a sale, and the automatic sample animation is not engagement.

## Configuration

Airdraft uses [US Cloud project 645700](https://us.posthog.com/project/645700/settings/project-details). Copy the public
`phc_` project token from project settings into the build environment:

```dotenv
PUBLIC_POSTHOG_ENABLED=true
PUBLIC_POSTHOG_KEY=phc_your_project_token
PUBLIC_POSTHOG_HOST=https://us.i.posthog.com
```

For EU projects use `https://eu.i.posthog.com`. Local configuration goes in
`apps/marketing/.env`, which is ignored. Copy `.env.example` first. Astro embeds
these values at build time; Worker runtime variables cannot configure an already
built static bundle. Moon includes the env files and variables in its build inputs.
Set the same values in the actual deployment build environment before rebuilding.
The GitHub marketing workflow currently validates the package and does not deploy.

Only `https://airdraft.app` collects production events. Missing configuration,
development hosts and previews remain off. Enabled builds reject malformed keys
and unknown ingestion hosts. Never put a `phx_` personal API key in `PUBLIC_*`,
the repository or browser code. Disabling `PUBLIC_POSTHOG_ENABLED` and rebuilding
is the collection rollback.

## Consent and data

The shared Astro layout loads the pinned `posthog-js` package dynamically after
consent. There is one manual `$pageview` per document after consent; this static
site does not use ClientRouter. Do not also enable automatic pageviews. If
ClientRouter is added, revise navigation handling and test duplicate capture.

The notice offers equally styled Allow and Decline actions. `/privacy/` allows
revocation; consent is stored for 180 days. No PostHog script or request runs
before consent or after an initial decline. GPC and DNT keep collection off.
SDK opt-out and a final event gate handle withdrawal, including another tab and
withdrawal while the SDK loads. Previously delivered events are not deleted.

Person profiles, identification, replay, autocapture, heatmaps, dead/rage clicks,
exceptions, console recording, surveys, flags, tours and experiments are off.
There is no audio or transcript collection. IP storage and GeoIP enrichment are
disabled. The service still receives the network connection, so this is not a
claim that no personal data can ever reach a processor.

The event allowlist preserves anonymous/session IDs, browser and device types,
known page paths and numeric Web Vitals. It removes arbitrary properties,
nested person/DOM data, query strings, hashes, referral paths and advertising
click IDs. Only `utm_source`, `utm_medium`, `utm_campaign` and `utm_content` are
accepted, with 1–80 ASCII letters, digits, underscores or hyphens. Never put
personal information in campaign labels. `utm_term` is excluded. Unknown paths
become `/404/`; referral origins remain, without paths or credentials.

## Events and decisions

All events include `site=airdraft-marketing`, `environment=production` and
`event_schema_version=1`. Keep the contract in `src/lib/analytics-policy.ts`.

| Event                                          | What it answers                                                                                              |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `$pageview`, `$pageleave`                      | Which pages and referral sources attract visits? How long do consented visits last?                          |
| `$web_vitals`                                  | Do LCP, INP, CLS or FCP show a performance problem?                                                          |
| `pricing_clicked`                              | Which placements lead visitors to pricing?                                                                   |
| `source_clicked`, `build_instructions_clicked` | How much interest is there in self-building?                                                                 |
| `license_plan_selected`                        | Which Mac count do visitors actively select?                                                                 |
| `demo_started`, `demo_profile_selected`        | Do visitors intentionally try the authored samples and profiles?                                             |
| `checkout_clicked`                             | Do pricing visitors follow an enabled checkout link? `plan` means the clicked offer, not the purchased plan. |
| `support_clicked`, `release_clicked`           | Do visitors seek help or release details?                                                                    |

`placement` is limited to header, hero, sample, footer, offer and content.
`plan` is one-mac or three-macs. Demo events exclude autoplay. Disabled checkout
controls send nothing. No download event is invented while the site has no
installer download CTA. Track a future verified download CTA separately from
completed app installation. Actual revenue requires verified payment-side events
and a separate identity/consent design; do not infer it from a redirect.

## PostHog project setup

Use Web Analytics for visitors, sources, landing pages, bounce and Web Vitals.
Keep project IP discarding enabled, web autocapture and session replay disabled,
and Web Vitals enabled; the SDK applies the same restrictions after consent.
Pin `pricing_clicked` and `build_instructions_clicked` as intent goals; enable a
checkout goal only when sales open. Expect consent and blocker undercounting.
Direct pricing landings appear in pageviews even without `pricing_clicked`.

[Airdraft website dashboard](https://us.posthog.com/project/645700/dashboard/2169951)
uses eight saved insights with production/site
filters, including acquisition, page popularity, source/build interest, demo
use, plan interest and visit/pricing/checkout funnels. Unique visitors use
anonymous IDs and the funnels use a one-day conversion window.

```sh
# Print the exact dashboard and insight definitions without network access.
node apps/marketing/scripts/setup-posthog.mjs

# In a trusted shell, provide the selected project ID, region's app host and
# a personal API key with dashboard:read/write and insight:read/write scopes.
# POSTHOG_UI_HOST=https://us.posthog.com or https://eu.posthog.com
# POSTHOG_PROJECT_ID=<project ID>
# POSTHOG_PERSONAL_API_KEY=<personal key, never PUBLIC_*>
node apps/marketing/scripts/setup-posthog.mjs --apply
```

The provisioner can create one marked dashboard and only its missing insights. It
leaves unrelated dashboards intact, supports rerunning after partial failure,
and checks that the saved insights exist. Review event volume and retention in
project settings before opening the site. Website events alone do not establish
app activation or retention.

PostHog recommends a reverse proxy to improve delivery through blockers. Its
managed proxy is the first option to assess for this static site. Enabling one
requires a verified project/domain configuration, extending the host validation
and checking that consent still gates every request. A proxy is not configured
by this integration. Do not turn off Cloudflare Access to make analytics work.

## Verification

`pnpm check:marketing` includes consent, data filtering and dashboard provisioner
regressions. `pnpm build:marketing` validates the generated website and discovery
files. For a local browser test, run the collector and development server:

```sh
node apps/marketing/scripts/analytics-collector.mjs
PUBLIC_POSTHOG_LOCAL_TEST=true pnpm --filter @airdraft/marketing dev
```

Use the actual address printed by Astro. The development-only flag fixes the
project token to `phc_localfixture`, routes to `127.0.0.1:4329`, and marks events
`local-test`. The production build removes this branch. Inspect the collector's
`/results` for zero requests before consent, one pageview after allowing,
intent events, sanitized URL/UTM data, and no new requests after withdrawal.
Check the notice and privacy page at desktop and mobile widths.

After a separately authorized deployment, verify the exact deployed build and
real events in the intended project's Activity/Web Analytics. A local collector
or a successful build does not prove PostHog ingestion or a saved live dashboard.

## Official references

Reviewed 2026-10-05 against `posthog-js` 1.435.8:

- [Astro integration](https://posthog.com/docs/libraries/astro), shared layout and pageview handling.
- [JavaScript configuration](https://posthog.com/docs/libraries/js/config), explicit defaults and capture controls.
- [Data collection](https://posthog.com/docs/privacy/data-collection), consent and storage controls.
- [Web Analytics](https://posthog.com/docs/web-analytics), acquisition and goals.
- [Reverse proxy](https://posthog.com/docs/advanced/proxy), delivery recommendation.
- [Dashboards API](https://posthog.com/docs/api/dashboards) and [Insights API](https://posthog.com/docs/api/insights), provisioning and permissions.
