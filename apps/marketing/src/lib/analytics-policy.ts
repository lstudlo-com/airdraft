import type { CaptureResult } from "posthog-js";

export const consentKey = "airdraft.analytics-consent.v1";
export const consentLifetime = 180 * 24 * 60 * 60 * 1000;
export type Consent = "granted" | "denied";

export function readConsent(
  raw: string | null,
  now = Date.now(),
): Consent | null {
  try {
    const value = JSON.parse(raw || "null");
    return value &&
      ["granted", "denied"].includes(value.choice) &&
      typeof value.expires === "number" &&
      value.expires > now
      ? value.choice
      : null;
  } catch {
    return null;
  }
}

export function analyticsAllowed(
  origin: string,
  enabled: boolean,
  token: string,
) {
  return (
    enabled &&
    /^phc_[a-zA-Z0-9]+$/.test(token) &&
    origin === "https://airdraft.app"
  );
}

const paths = new Set([
  "/",
  "/pricing/",
  "/support/",
  "/changelog/",
  "/privacy/",
  "/guides/",
  "/guides/offline-dictation-on-mac/",
  "/guides/local-vs-cloud-dictation/",
  "/guides/free-source-or-official-app/",
]);
export function safePath(path: string) {
  return paths.has(path) ? path : "/404/";
}

export const events = [
  "$pageview",
  "$pageleave",
  "$web_vitals",
  "pricing_clicked",
  "source_clicked",
  "build_instructions_clicked",
  "checkout_clicked",
  "license_plan_selected",
  "demo_started",
  "demo_profile_selected",
  "support_clicked",
  "release_clicked",
] as const;
export type WebsiteEvent = (typeof events)[number];

// Retain the SDK's session/browser fields needed by Web Analytics. Everything
// else is excluded, including nested person data, DOM, URLs and click IDs.
const sdkProperties = new Set([
  "token",
  "distinct_id",
  "$device_id",
  "$session_id",
  "$window_id",
  "$lib",
  "$lib_version",
  "$browser",
  "$browser_version",
  "$os",
  "$os_version",
  "$device_type",
  "$screen_height",
  "$screen_width",
  "$viewport_height",
  "$viewport_width",
  "$time",
  "$is_identified",
  "$insert_id",
  "$pageview_id",
  "$prev_pageview_id",
  "$prev_pageview_duration",
  "$prev_pageview_max_scroll_percentage",
  "$prev_pageview_last_scroll_percentage",
  "$prev_pageview_max_content_percentage",
  "$prev_pageview_last_content_percentage",
  "$session_entry_referring_domain",
  "$session_entry_utm_source",
  "$session_entry_utm_medium",
  "$session_entry_utm_campaign",
  "$session_entry_utm_content",
]);
const categoricalProperties: Record<string, readonly string[]> = {
  placement: ["header", "hero", "sample", "footer", "content", "offer"],
  plan: ["one-mac", "three-macs"],
  demo: ["waveform", "sample"],
  profile: ["clean", "concise", "summary"],
};
const campaignKeys = [
  "utm_source",
  "utm_medium",
  "utm_campaign",
  "utm_content",
];
const campaignValue = /^[a-zA-Z0-9_-]{1,80}$/;

export function sanitizeEvent(
  event: CaptureResult | null,
  consent: boolean,
): CaptureResult | null {
  if (!event || !consent || !events.includes(event.event as WebsiteEvent))
    return null;
  const original = event.properties || {};
  const properties: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(original)) {
    if (
      sdkProperties.has(key) &&
      ["string", "number", "boolean"].includes(typeof value)
    ) {
      // Session UTM values must follow the same convention as current UTMs.
      if (
        key.includes("utm_") &&
        (typeof value !== "string" || !campaignValue.test(value))
      )
        continue;
      properties[key] = value;
    }
    if (
      /^\$web_vitals_(LCP|CLS|INP|FCP)_value$/.test(key) &&
      typeof value === "number" &&
      Number.isFinite(value)
    ) {
      properties[key] = value;
    }
    if (categoricalProperties[key]?.includes(value as string))
      properties[key] = value;
    if (
      campaignKeys.includes(key) &&
      typeof value === "string" &&
      campaignValue.test(value)
    )
      properties[key] = value;
  }
  const path = safePath(String(original.$pathname || "/"));
  properties.$pathname = path;
  properties.$current_url = `https://airdraft.app${path}`;
  for (const key of ["$referrer", "$session_entry_referrer"]) {
    try {
      const url = new URL(String(original[key]));
      if (["https:", "http:"].includes(url.protocol))
        properties[key] = url.origin;
    } catch {
      /* No referrer is a normal direct visit. */
    }
  }
  for (const key of ["$referring_domain", "$session_entry_referring_domain"]) {
    if (
      typeof original[key] === "string" &&
      /^[a-zA-Z0-9.-]+$/.test(original[key])
    )
      properties[key] = original[key];
    else delete properties[key];
  }
  for (const key of ["$prev_pageview_pathname", "$session_entry_pathname"]) {
    if (original[key]) properties[key] = safePath(String(original[key]));
  }
  properties.site = "airdraft-marketing";
  properties.environment = "production";
  properties.event_schema_version = 1;
  properties.$process_person_profile = false;
  properties.$geoip_disable = true;
  return { ...event, properties };
}
