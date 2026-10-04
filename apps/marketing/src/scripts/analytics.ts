import type { PostHog } from "posthog-js";
import { siteLinks } from "../data/site";
import {
  analyticsAllowed,
  consentKey,
  consentLifetime,
  readConsent,
  sanitizeEvent,
  safePath,
  type Consent,
  type WebsiteEvent,
} from "../lib/analytics-policy";

// The development fixture uses a fixed dummy token and a local collector. The
// production build eliminates this branch, even if the env flag is set.
const localTest =
  import.meta.env.DEV &&
  import.meta.env.PUBLIC_POSTHOG_LOCAL_TEST === "true" &&
  ["127.0.0.1", "localhost"].includes(location.hostname);
const token = localTest
  ? "phc_localfixture"
  : import.meta.env.PUBLIC_POSTHOG_KEY?.trim() || "";
const host = localTest
  ? "http://127.0.0.1:4329"
  : import.meta.env.PUBLIC_POSTHOG_HOST?.trim() || "";
const configured = import.meta.env.PUBLIC_POSTHOG_ENABLED === "true";
const permitted =
  localTest ||
  (analyticsAllowed(location.origin, configured, token) &&
    ["https://us.i.posthog.com", "https://eu.i.posthog.com"].includes(host));
const signalBlocks = () =>
  navigator.doNotTrack === "1" ||
  (navigator as Navigator & { globalPrivacyControl?: boolean })
    .globalPrivacyControl === true;
let consent: Consent | null = null;
try {
  consent = readConsent(localStorage.getItem(consentKey));
} catch {
  /* Storage can be unavailable. */
}
let client: PostHog | undefined;
let loading: Promise<void> | undefined;
const mayCapture = () => permitted && consent === "granted" && !signalBlocks();
const notice = document.querySelector<HTMLElement>("[data-analytics-notice]");
const status = document.querySelector<HTMLElement>("[data-analytics-status]");

function updateControls() {
  if (notice) notice.hidden = !permitted || signalBlocks() || consent !== null;
  if (status)
    status.textContent = !permitted
      ? "Website analytics are not enabled on this site."
      : signalBlocks()
        ? "Analytics are off because your browser requests no tracking."
        : consent === "granted"
          ? "Website analytics are allowed. You can turn them off below."
          : "Website analytics are off.";
  document
    .querySelectorAll<HTMLButtonElement>("[data-analytics-choice=granted]")
    .forEach((button) => {
      button.disabled = !permitted || signalBlocks();
    });
}

async function start() {
  if (!mayCapture()) return;
  if (client) {
    client.opt_in_capturing();
    client.capture("$pageview", { $pathname: safePath(location.pathname) });
    return;
  }
  if (loading) return loading;
  loading = (async () => {
    try {
      const { default: posthog } = await import("posthog-js");
      // A visitor can decline while the SDK chunk is loading.
      if (!mayCapture()) return;
      client = posthog;
      posthog.init(token, {
        api_host: host,
        defaults: "2026-05-30",
        strict_script_versioning: true,
        person_profiles: "never",
        persistence: "localStorage",
        opt_out_capturing_by_default: true,
        opt_out_persistence_by_default: true,
        autocapture: false,
        capture_pageview: false,
        capture_pageleave: true,
        capture_performance: {
          network_timing: false,
          web_vitals: true,
          web_vitals_attribution: false,
        },
        disable_product_tours: true,
        disable_conversations: true,
        disable_web_experiments: true,
        disable_session_recording: true,
        disable_surveys: true,
        capture_heatmaps: false,
        capture_dead_clicks: false,
        rageclick: false,
        capture_exceptions: false,
        enable_recording_console_log: false,
        advanced_disable_flags: true,
        ip: false,
        respect_dnt: true,
        before_send: (event) => {
          const safe = sanitizeEvent(event, mayCapture());
          if (safe && localTest) safe.properties.environment = "local-test";
          return safe;
        },
        loaded: (sdk) => {
          if (!mayCapture()) return;
          sdk.opt_in_capturing();
          sdk.capture("$pageview", { $pathname: safePath(location.pathname) });
        },
      });
    } catch {
      // Analytics must never interrupt navigation or the product sample.
      client = undefined;
    } finally {
      loading = undefined;
    }
  })();
  return loading;
}

function choose(choice: Consent) {
  const wasGranted = consent === "granted";
  consent = choice;
  try {
    localStorage.setItem(
      consentKey,
      JSON.stringify({ choice, expires: Date.now() + consentLifetime }),
    );
  } catch {
    /* Keep the choice for this page only. */
  }
  updateControls();
  if (choice === "denied") client?.opt_out_capturing();
  else if (!wasGranted) void start();
}

export function captureWebsiteEvent(
  event: WebsiteEvent,
  properties: Record<string, string> = {},
) {
  if (!client || !mayCapture()) return;
  client.capture(
    event,
    { ...properties, $pathname: safePath(location.pathname) },
    { transport: "sendBeacon" },
  );
}

function placement(element: Element): string {
  if (element.closest("header")) return "header";
  if (element.closest("footer")) return "footer";
  if (element.closest("[data-preview]")) return "sample";
  if (element.closest("#get-airdraft")) return "offer";
  if (element.closest(".hero-actions")) return "hero";
  return "content";
}

document.addEventListener("click", (event) => {
  if (!(event.target instanceof Element)) return;
  const choice = event.target.closest<HTMLElement>("[data-analytics-choice]")
    ?.dataset.analyticsChoice;
  if (choice === "granted" || choice === "denied") {
    choose(choice);
    return;
  }
  const link = event.target.closest<HTMLAnchorElement>("a[href]");
  if (!link) return;
  let name: WebsiteEvent | undefined;
  if (link.href === siteLinks.build) name = "build_instructions_clicked";
  else if (link.href === siteLinks.source) name = "source_clicked";
  else if (siteLinks.checkout && link.href === siteLinks.checkout)
    name = "checkout_clicked";
  else if (link.href === siteLinks.issues) name = "support_clicked";
  else if (link.origin === location.origin && link.pathname === "/pricing/")
    name = "pricing_clicked";
  else if (link.href.startsWith(`${siteLinks.source}/releases/`))
    name = "release_clicked";
  if (name)
    captureWebsiteEvent(name, {
      placement: placement(link),
      plan: link.dataset.analyticsPlan || "",
    });
});

document.addEventListener("change", (event) => {
  if (
    event.target instanceof HTMLInputElement &&
    event.target.matches("[data-analytics-plan]")
  ) {
    captureWebsiteEvent("license_plan_selected", {
      plan: event.target.value,
      placement: placement(event.target),
    });
  }
});

// Keep consent changes in another tab effective without a navigation.
window.addEventListener("storage", (event) => {
  if (event.key !== consentKey && event.key !== null) return;
  const previous = consent;
  consent = readConsent(event.newValue);
  updateControls();
  if (consent !== "granted") client?.opt_out_capturing();
  else if (previous !== "granted") void start();
});
updateControls();
void start();
