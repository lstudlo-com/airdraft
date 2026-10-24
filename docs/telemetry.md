# App telemetry

Official Airdraft downloads can send anonymous product events and crash reports
to PostHog, only after the user agrees. Source, community, isolated, Polar Sandbox
and Debug builds never send anything and never construct the PostHog client.
The public description is the website privacy page, section `#app-telemetry`.

## Build gating

`TelemetryAvailability.isOffered` is true only when all hold:

- `AirdraftDistribution` is not `community` (an official build), and the
  container is not isolated (renders, fixtures, tests, `--e2e-local`);
- Info.plist carries a valid configuration: `AirdraftTelemetryToken` matches
  `^phc_[A-Za-z0-9]+$` and `AirdraftTelemetryHost` is exactly
  `https://us.i.posthog.com` or `https://eu.i.posthog.com`;
- the build is not Debug.

Sending additionally requires consent `granted`. `TelemetryService.make` passes a
client factory that returns nil under `#if DEBUG`, so a Debug build cannot create
the client even with an official plist and consent.

`project.yml` defaults `AIRDRAFT_TELEMETRY_TOKEN` and `AIRDRAFT_TELEMETRY_HOST` to
empty. Only `scripts/release.py prepare` passes them, from
`scripts/telemetry-config.json` validated by `scripts/telemetry.py`, to the
Release build, then verifies the embedded values in the built app.
`scripts/build-sandbox.py` verifies that the Sandbox build embeds none.
`scripts/test-release.py` covers validation, embedding and absence.

## Project and switching

The app currently shares the website's PostHog US project (645700). Every app
event carries `app=airdraft-mac`, so dashboards can separate it from website
events. The token is a public client-side project token already shipped in the
website bundle. Moving the app to its own project, or to the EU region, changes
only `scripts/telemetry-config.json` (`posthog_token`, `posthog_host`); the next
official release embeds the new values.

## Consent

`AppSettings.telemetryConsent` is `undecided`, `granted` or `denied`, stored as
`telemetry.consent`, outside the `settings.` keys, so an answer never counts as
an existing setup. Absent means undecided. Reset App clears it, so the question
returns.

- The question appears only where telemetry is offered and consent is undecided:
  a card on onboarding's Ready step and on Home (also covering existing users who
  never see onboarding). Both actions, Don’t Share and Share Anonymous Usage Data,
  have equal weight. The card lists what is and is never shared and links to the
  privacy page. Nothing is sent and no client exists before a choice.
- Settings > Behavior has the switch "Share anonymous usage data and crash
  reports", with a Privacy Details link. It is hidden where telemetry is not
  offered and is indexed by Settings search.
- Granting creates the client, calls `optIn()` (an SDK-persisted opt-out never
  overrides our consent) and sends `telemetry_consent_changed` = `granted`.
- Denying from `granted` sends `telemetry_consent_changed` = `denied`, then calls
  `flush()`, `optOut()` and `close()`. A first "no" from undecided sends nothing.
  Already queued events may go out in the final flush; they were captured with
  consent.
- At every launch without `granted`, the app removes the SDK's local data: its
  token-named folder under `~/Library/Application Support/<bundle ID>/` (queue,
  anonymous ID) and `~/Library/Caches/com.plausiblelabs.crashreporter.data/<bundle ID>`
  (pending crash report). A crash handler installed in the current session stays
  until quit (the SDK cannot uninstall it), but its report is never sent without
  consent.

## Events

All properties are enumerated or bucketed. `TelemetrySanitizer` accepts only
these keys and values and drops the event otherwise. Every event also has
`app` = `airdraft-mac`.

| Event | Properties |
|---|---|
| `app_launched` | `app_version` (digits and dots), `app_build` (digits), `macos_major`, `arch` (`arm64`/`x86_64`), `interface_language` (`en`, `zh-Hant`, `zh-Hans`, `other`), `license_state` (`trial`, `licensed`, `expired`, `none`) |
| `onboarding_finished` | `outcome` (`completed`, `skipped`); first time only |
| `dictation_completed` | `speech_engine` (`ASRProviderKind` raw value), `speech_location` (`local`/`cloud`), `refinement_provider` (`LLMProviderKind` raw value, `none` when the profile skips refinement), `profile` (`clean`, `concise`, `summary`, `verbatim`, `custom`), `recording_duration` (`0-5s` … `10m+`), `stop_to_delivery` (`0-250ms` … `10s+`, `unknown`), `delivery_status` (`delivered`, `sentUnverified`, `notDelivered`), `refinement_outcome` (`none`, `applied`, `fallback`) |
| `dictation_failed` | `category` (`permission`, `microphone_unavailable`, `model_missing`, `credential_missing`, `setup_invalid`, `license_required`, `recording_failed`, `speech_error`, `delivery_failed`, `other`) |
| `model_download_finished` | `model` (bundled `ModelCatalogue` ID or `other`), `outcome` (`ok`, `failed`, `cancelled`) |
| `meeting_transcribed` | `duration` (`0-5m` … `2h+`), `speech_engine`, `speech_location` |
| `license_event` | `action` (`trial_started`, `activated`) |
| `telemetry_consent_changed` | `consent` (`granted`, `denied`) |
| `$exception` (crash report) | `$exception_list`, `$exception_level`, `$exception_source`, `$debug_images`; `/Users/<name>` in strings becomes `/Users/<user>`, strings are capped at 1024 characters, `$exception_steps` is removed |

Pipeline rules: `dictation_completed` is reported after delivery and the state
change, for normal dictations and explicit retries; review-only work and
onboarding practice are not counted. An undelivered dictation also reports
`dictation_failed` = `delivery_failed`. A refinement fallback is a completed
dictation. Cancellation and "setup changed, press again" are never reported.
Recording only hands an enum to the gate; the client runs every SDK call on its
own serial queue, so delivery never waits on telemetry.

## SDK configuration

posthog-ios (pinned in `project.yml`): `personProfiles = .never`,
`setDefaultPersonProperties = false`, lifecycle and screen events off, swizzling
and push-notification capture off, `sendFeatureFlagEvent = false`,
`preloadFeatureFlags = false`, `disableGeoIp = true` (adds `$geoip_disable`),
error tracking `autoCapture = true` with exception steps off. Surveys and replay
are unavailable on macOS and unused. No `identify`, `alias`, `group` or `$ip`.

A `beforeSend` hook runs `TelemetrySanitizer.outgoing` on every event: SDK events
other than Airdraft's and `$exception` are dropped; SDK properties are reduced to
`$lib`, `$lib_version`, `$os_name`, `$os_version`, `$app_version`, `$app_build`,
`$session_id`, `$process_person_profile` and `$geoip_disable`. Device name and
model, locale, time zone, screen size, network, bundle identifier, groups, screen
names, feature flags and person properties are removed.

The SDK still contacts PostHog's remote config endpoint after setup (consent
given); that request reveals the network address like any event.

## Never sent

Transcripts, refined or final text, audio, vocabulary, prompts or profile
instructions, clipboard contents, app names, bundle IDs of target apps, window
titles, URLs, file names or paths, provider endpoints or hosts, API keys, license
keys or device labels, custom or unknown model IDs, the Mac's name, user names,
email addresses and IP-derived location. Unit tests feed hostile strings for each
of these into every key and assert rejection.

## Server-side settings (unverified in code)

IP storage must be disabled in the PostHog project settings ("Discard client IP
data"); the app cannot enforce this. Event retention and access control are
project settings too. Record their verified state in the vault, not here.

## Tests and renders

- `AirdraftCoreTests/TelemetryTests`, `TelemetryPipelineTests` (credential-free
  suite) and `AirdraftAppTests/TelemetryServiceTests` use a fake client; nothing
  is sent. They prove gating, the allowlist, buckets, pipeline emission and that
  community and Debug builds construct no client.
- `AIRDRAFT_RENDER_TELEMETRY=official-undecided|official-granted|community`
  shows the consent UI in Debug renders (`official-granted` only changes isolated
  render settings). It never enables sending. `settings-search` asserts the switch
  is indexed.
