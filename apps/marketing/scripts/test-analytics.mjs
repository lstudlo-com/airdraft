import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";
import ts from "typescript";
import * as policy from "../src/lib/analytics-policy.ts";
import { guides, zhGuides } from "../src/data/guides.ts";
import { setup, insights } from "./setup-posthog.mjs";

test("production collection requires an explicit switch, public token and exact origin", () => {
  assert.equal(
    policy.analyticsAllowed("https://airdraft.app", true, "phc_example"),
    true,
  );
  for (const origin of [
    "http://airdraft.app",
    "http://localhost:4321",
    "https://preview.airdraft.app",
    "https://airdraft.app.attacker.example",
  ]) {
    assert.equal(policy.analyticsAllowed(origin, true, "phc_example"), false);
  }
  assert.equal(
    policy.analyticsAllowed("https://airdraft.app", false, "phc_example"),
    false,
  );
  assert.equal(
    policy.analyticsAllowed("https://airdraft.app", true, "phx_private"),
    false,
  );
});

test("invalid and expired consent never enable tracking", () => {
  for (const value of [
    null,
    "broken",
    "true",
    '{"choice":"granted"}',
    '{"choice":"granted","expires":1}',
  ])
    assert.equal(policy.readConsent(value, 2), null);
  assert.equal(
    policy.readConsent('{"choice":"granted","expires":3}', 2),
    "granted",
  );
  assert.equal(
    policy.readConsent('{"choice":"denied","expires":3}', 2),
    "denied",
  );
});

test("outbound policy drops personal data, arbitrary events and unsafe attribution", () => {
  const event = {
    event: "$pageview",
    properties: {
      token: "phc_test",
      distinct_id: "random-browser-id",
      $session_id: "session",
      $pathname: "/pricing/",
      $current_url: "https://airdraft.app/pricing/?email=secret#token",
      $referrer: "https://example.com/private?secret=abc",
      $set: { email: "private" },
      $session_entry_referrer: "https://example.com/sensitive?token=abc",
      $session_entry_pathname: "/account/private",
      $initial_current_url: "secret",
      $elements: ["private"],
      gclid: "ad-id",
      email: "private",
      text: "transcript",
      utm_source: "newsletter",
      utm_campaign: "a@b.example",
      utm_term: "private search",
      plan: "three-macs",
      profile: "private-profile-name",
      $web_vitals_LCP_value: 123,
      $web_vitals_LCP_event: { attribution: "private" },
    },
  };
  const safe = policy.sanitizeEvent(event, true);
  assert.equal(safe.properties.$current_url, "https://airdraft.app/pricing/");
  assert.equal(safe.properties.$referrer, "https://example.com");
  assert.equal(safe.properties.$session_entry_referrer, "https://example.com");
  assert.equal(safe.properties.$session_entry_pathname, "/404/");
  assert.equal(safe.properties.utm_source, "newsletter");
  assert.equal(safe.properties.plan, "three-macs");
  assert.equal(safe.properties.$web_vitals_LCP_value, 123);
  assert.equal(safe.properties.$process_person_profile, false);
  assert.equal(safe.properties.$geoip_disable, true);
  for (const key of [
    "$set",
    "$elements",
    "$initial_current_url",
    "gclid",
    "email",
    "text",
    "utm_campaign",
    "utm_term",
    "profile",
    "$web_vitals_LCP_event",
  ])
    assert.equal(key in safe.properties, false, key);
  assert.equal(policy.sanitizeEvent(event, false), null);
  assert.equal(
    policy.sanitizeEvent({ ...event, event: "$autocapture" }, true),
    null,
  );
  assert.equal(
    policy.sanitizeEvent({ ...event, event: "$snapshot" }, true),
    null,
  );
});

const source = readFileSync(
  new URL("../src/scripts/analytics.ts", import.meta.url),
  "utf8",
).replaceAll("import.meta.env", "env");
const compiled = ts.transpileModule(source, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2022,
  },
}).outputText;
const settle = () => new Promise((resolve) => setImmediate(resolve));

function fixture({
  choice = null,
  dnt = false,
  gpc = false,
  storageFails = false,
  origin = "https://airdraft.app",
  sdkFails = false,
  siteLinks = {},
  pathname = "/pricing/",
} = {}) {
  const listeners = {};
  const stored = new Map();
  if (choice)
    stored.set(
      policy.consentKey,
      JSON.stringify({ choice, expires: Date.now() + 10000 }),
    );
  const calls = [];
  let config;
  let imports = 0;
  let optedIn = false;
  const client = {
    init(token, options) {
      calls.push(["init", token]);
      config = options;
      options.loaded(client);
    },
    opt_in_capturing() {
      optedIn = true;
    },
    opt_out_capturing() {
      optedIn = false;
      calls.push(["opt-out"]);
    },
    capture(name, properties) {
      if (!optedIn) return;
      const result = config.before_send({ event: name, properties });
      if (result) calls.push(["capture", result]);
    },
  };
  class Element {
    constructor(choice) {
      this.dataset = { analyticsChoice: choice };
    }
    closest() {
      return this;
    }
  }
  const context = {
    exports: {},
    env: {
      PUBLIC_POSTHOG_ENABLED: "true",
      PUBLIC_POSTHOG_KEY: "phc_fixture",
      PUBLIC_POSTHOG_HOST: "https://us.i.posthog.com",
      DEV: false,
    },
    require(name) {
      if (name.includes("analytics-policy")) return policy;
      if (name.includes("data/site")) return { siteLinks };
      imports++;
      if (sdkFails) throw new Error("blocked SDK");
      return { default: client };
    },
    navigator: { doNotTrack: dnt ? "1" : "0", globalPrivacyControl: gpc },
    location: {
      origin,
      hostname: new URL(origin).hostname,
      pathname,
    },
    document: {
      querySelector: () => null,
      querySelectorAll: () => [],
      addEventListener: (name, fn) => {
        listeners[name] = fn;
      },
    },
    window: {
      addEventListener: (name, fn) => {
        listeners[name] = fn;
      },
    },
    localStorage: {
      getItem: (key) => {
        if (storageFails) throw new Error("denied");
        return stored.get(key);
      },
      setItem: (key, value) => {
        if (storageFails) throw new Error("denied");
        stored.set(key, value);
      },
    },
    Element,
    HTMLInputElement: class {},
    URL,
  };
  runInNewContext(compiled, context);
  return {
    calls,
    context,
    listeners,
    choose: (choice) => listeners.click({ target: new Element(choice) }),
    get imports() {
      return imports;
    },
    get config() {
      return config;
    },
  };
}

test("no SDK load before consent, on decline, previews or privacy signals", async () => {
  for (const options of [
    {},
    { choice: "denied" },
    { choice: "granted", dnt: true },
    { choice: "granted", gpc: true },
    { choice: "granted", origin: "http://localhost:4321" },
    { storageFails: true },
  ]) {
    const f = fixture(options);
    await settle();
    assert.equal(f.imports, 0);
    assert.equal(f.calls.length, 0);
  }
});

test("grant captures one pageview, repeated grant is inert, revoke stops events", async () => {
  const f = fixture();
  f.choose("granted");
  await settle();
  f.choose("granted");
  await settle();
  assert.equal(f.imports, 1);
  assert.equal(f.calls.filter((call) => call[0] === "capture").length, 1);
  assert.equal(f.config.autocapture, false);
  assert.equal(f.config.disable_session_recording, true);
  assert.equal(f.config.person_profiles, "never");
  f.choose("denied");
  f.context.exports.captureWebsiteEvent("pricing_clicked", {
    placement: "hero",
  });
  assert.equal(f.calls.filter((call) => call[0] === "capture").length, 1);
  assert.equal(
    f.config.before_send({ event: "$pageleave", properties: {} }),
    null,
  );
  f.choose("granted");
  await settle();
  assert.equal(f.calls.filter((call) => call[0] === "capture").length, 2);
});

test("revocation during load and in another tab blocks capture", async () => {
  const f = fixture();
  f.choose("granted");
  f.choose("denied");
  await settle();
  assert.equal(f.calls.length, 0);
  f.choose("granted");
  await settle();
  f.listeners.storage({
    key: policy.consentKey,
    newValue: '{"choice":"granted","expires":9999999999999}',
  });
  await settle();
  assert.equal(f.calls.filter((call) => call[0] === "capture").length, 1);
  f.listeners.storage({
    key: policy.consentKey,
    newValue: '{"choice":"denied","expires":9999999999999}',
  });
  f.context.exports.captureWebsiteEvent("source_clicked");
  assert.equal(f.calls.filter((call) => call[0] === "capture").length, 1);
});

test("blocked SDK never breaks consent controls", async () => {
  const f = fixture({ sdkFails: true });
  f.choose("granted");
  await settle();
  assert.equal(f.calls.length, 0);
  assert.doesNotThrow(() => f.choose("denied"));
});

test("dashboard setup is offline by default and reruns without duplicates", async () => {
  let calls = 0;
  const boards = [
    { id: 1, name: "Unrelated dashboard", description: "Keep me" },
  ];
  const saved = [];
  const request = async (url, options) => {
    calls++;
    assert.equal(url.origin, "https://eu.posthog.com");
    assert.equal(options.redirect, "error");
    const isDashboard = url.pathname.endsWith("/dashboards/");
    let result;
    if (options.method === "POST") {
      result = { id: calls, ...JSON.parse(options.body) };
      (isDashboard ? boards : saved).push(result);
    } else result = { results: isDashboard ? boards : saved, next: null };
    return { ok: true, json: async () => result };
  };
  assert.equal((await setup({}, false, request)).dryRun, true);
  assert.equal(calls, 0);
  const env = {
    POSTHOG_UI_HOST: "https://eu.posthog.com",
    POSTHOG_PROJECT_ID: "42",
    POSTHOG_PERSONAL_API_KEY: "phx_fixture",
  };
  await setup(env, true, request);
  await setup(env, true, request);
  assert.equal(boards.length, 2);
  assert.equal(saved.length, insights.length);
  assert.equal(boards[0].description, "Keep me");
  assert.ok(saved.every((item) => item.dashboards[0] === boards[1].id));
  await assert.rejects(() =>
    setup(
      { ...env, POSTHOG_UI_HOST: "https://attacker.example" },
      true,
      request,
    ),
  );
});

test("guide links report only an allowlisted slug in either language", () => {
  const slugs = [...guides, ...zhGuides].map((guide) => guide.slug);
  assert.deepEqual(
    [...new Set(slugs)].sort(),
    [...policy.guideSlugs].sort(),
    "guideSlugs must match src/data/guides.ts",
  );
  for (const guide of [...guides, ...zhGuides])
    assert.equal(policy.guideOf(guide.href), guide.slug);
  for (const path of [
    "/guides/",
    "/guides/unknown-guide/",
    "/zh-tw/guides/",
    "/pricing/",
    "/guides/mixed-chinese-english-dictation/extra/",
  ])
    assert.equal(policy.guideOf(path), undefined, path);
  const safe = policy.sanitizeEvent(
    {
      event: "guide_clicked",
      properties: {
        $pathname: "/zh-tw/",
        guide: "mixed-chinese-english-dictation",
        placement: "content",
        text: "transcript",
      },
    },
    true,
  );
  assert.equal(safe.properties.guide, "mixed-chinese-english-dictation");
  assert.equal(safe.properties.$pathname, "/zh-tw/");
  assert.equal("text" in safe.properties, false);
  const unknown = policy.sanitizeEvent(
    { event: "guide_clicked", properties: { guide: "private-notes" } },
    true,
  );
  assert.equal("guide" in unknown.properties, false);
});

test("intent clicks are captured the same way on English and Chinese pages", async () => {
  const siteLinks = {
    source: "https://github.com/example/airdraft",
    build: "https://github.com/example/airdraft#build",
    issues: "https://github.com/example/airdraft/issues",
    checkout: "",
  };
  for (const pathname of ["/", "/zh-tw/"]) {
    const f = fixture({ choice: "granted", siteLinks, pathname });
    await settle();
    const click = (url, containers = []) => {
      const link = new URL(url, "https://airdraft.app");
      const target = new f.context.Element();
      target.dataset = {};
      Object.assign(target, {
        href: link.href,
        origin: link.origin,
        pathname: link.pathname,
      });
      target.closest = (selector) =>
        selector === "a[href]" || containers.includes(selector) ? target : null;
      f.listeners.click({ target });
    };
    click(siteLinks.build, ["footer"]);
    click(siteLinks.source, [".hero-actions"]);
    click("/zh-tw/pricing/", ["#get-airdraft"]);
    click("/pricing/#provider-costs");
    click("/zh-tw/guides/dictate-to-claude-code-and-terminals/");
    click("/guides/");
    click(pathname);
    const captured = f.calls
      .filter((call) => call[0] === "capture" && call[1].event !== "$pageview")
      .map((call) => [
        call[1].event,
        call[1].properties.placement,
        call[1].properties.guide,
        call[1].properties.$pathname,
      ]);
    assert.deepEqual(captured, [
      ["build_instructions_clicked", "footer", undefined, pathname],
      ["source_clicked", "hero", undefined, pathname],
      ["pricing_clicked", "offer", undefined, pathname],
      ["pricing_clicked", "content", undefined, pathname],
      [
        "guide_clicked",
        "content",
        "dictate-to-claude-code-and-terminals",
        pathname,
      ],
    ]);
  }
});

test("both pricing pages lead the checkout funnel", () => {
  const funnel = insights.find(
    (insight) => insight.name === "Pricing pages to checkout intent",
  );
  assert.deepEqual(funnel.query.source.series[0].properties[0].value, [
    "/pricing/",
    "/zh-tw/pricing/",
  ]);
  assert.ok(insights.some((insight) => insight.name === "Guide interest"));
});
