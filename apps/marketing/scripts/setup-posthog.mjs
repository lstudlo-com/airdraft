// Dry run by default. Credentials belong in the shell environment, never PUBLIC_*.
import { pathToFileURL } from "node:url";

const property = (key, value) => ({
  key,
  value,
  type: "event",
  operator: "exact",
});
const series = (event, math = "dau") => ({ kind: "EventsNode", event, math });
const common = {
  dateRange: { date_from: "-30d" },
  properties: [
    property("site", "airdraft-marketing"),
    property("environment", "production"),
  ],
};
const trend = (names, breakdown) => ({
  kind: "InsightVizNode",
  source: {
    kind: "TrendsQuery",
    ...common,
    interval: "day",
    series: names.map((name) => series(name)),
    trendsFilter: { display: "ActionsLineGraph" },
    ...(breakdown
      ? { breakdownFilter: { breakdown, breakdown_type: "event" } }
      : {}),
  },
});
const funnel = (steps) => ({
  kind: "InsightVizNode",
  source: {
    kind: "FunnelsQuery",
    ...common,
    series: steps.map((event) => series(event)),
    funnelsFilter: {
      funnelVizType: "steps",
      funnelWindowInterval: 1,
      funnelWindowIntervalUnit: "day",
    },
  },
});

export const dashboard = {
  name: "Airdraft website",
  description:
    "Managed by Airdraft website analytics v1. Consented website traffic only. Source, build and checkout clicks measure intent, not installs or revenue.",
};
export const insights = [
  {
    name: "Visitors and acquisition",
    query: trend(["$pageview"], "$referring_domain"),
  },
  {
    name: "Pages that attract visitors",
    query: trend(["$pageview"], "$pathname"),
  },
  {
    name: "Pricing and source interest",
    query: trend(
      ["pricing_clicked", "source_clicked", "build_instructions_clicked"],
      "placement",
    ),
  },
  {
    name: "Visit to pricing intent",
    query: funnel(["$pageview", "pricing_clicked"]),
  },
  {
    name: "Visit to build instructions",
    query: funnel(["$pageview", "build_instructions_clicked"]),
  },
  {
    name: "Intentional sample use",
    query: trend(["demo_started", "demo_profile_selected"]),
  },
  {
    name: "License plan interest",
    query: trend(["license_plan_selected"], "plan"),
  },
  {
    name: "Pricing to checkout intent",
    query: {
      kind: "InsightVizNode",
      source: {
        kind: "FunnelsQuery",
        ...common,
        series: [
          {
            ...series("$pageview"),
            properties: [property("$pathname", "/pricing/")],
          },
          series("checkout_clicked"),
        ],
        funnelsFilter: {
          funnelVizType: "steps",
          funnelWindowInterval: 1,
          funnelWindowIntervalUnit: "day",
        },
      },
    },
  },
].map((insight) => ({
  ...insight,
  description: `${dashboard.description} ${insight.name}.`,
}));

export async function setup(env, apply = false, request = fetch) {
  if (!apply) return { dryRun: true, dashboard, insights };
  const host = env.POSTHOG_UI_HOST;
  const project = env.POSTHOG_PROJECT_ID;
  const key = env.POSTHOG_PERSONAL_API_KEY;
  if (
    !["https://us.posthog.com", "https://eu.posthog.com"].includes(host) ||
    !/^\d+$/.test(project || "") ||
    !key?.startsWith("phx_")
  ) {
    throw new Error(
      "Set POSTHOG_UI_HOST, POSTHOG_PROJECT_ID and POSTHOG_PERSONAL_API_KEY for the intended Airdraft project.",
    );
  }
  const base = `${host}/api/projects/${project}/`;
  async function api(path, method = "GET", body) {
    const url = new URL(path, base);
    if (!url.href.startsWith(base))
      throw new Error("Refusing an API URL outside the selected project.");
    const response = await request(url, {
      method,
      redirect: "error",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (!response.ok)
      throw new Error(
        `PostHog ${method} ${url.pathname} failed (${response.status}).`,
      );
    return response.json();
  }
  async function list(path) {
    const result = [];
    while (path) {
      const page = await api(path);
      result.push(...page.results);
      path = page.next;
    }
    return result;
  }
  const matches = (await list("dashboards/?limit=100")).filter(
    (item) => item.description === dashboard.description && !item.deleted,
  );
  if (matches.length > 1)
    throw new Error(
      "Multiple managed Airdraft dashboards exist; select one manually.",
    );
  const target = matches[0] || (await api("dashboards/", "POST", dashboard));
  const existing = await list(`insights/?dashboards=${target.id}&limit=100`);
  for (const insight of insights) {
    if (
      existing.some(
        (item) => item.description === insight.description && !item.deleted,
      )
    )
      continue;
    await api("insights/", "POST", { ...insight, dashboards: [target.id] });
  }
  const verified = await list(`insights/?dashboards=${target.id}&limit=100`);
  if (
    !insights.every((insight) =>
      verified.some(
        (item) => item.description === insight.description && !item.deleted,
      ),
    )
  ) {
    throw new Error(
      "Dashboard creation was incomplete; rerun to add missing insights.",
    );
  }
  return {
    dashboardURL: `${host}/project/${project}/dashboard/${target.id}`,
    insights: insights.length,
  };
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  setup(process.env, process.argv.includes("--apply"))
    .then((result) => console.log(JSON.stringify(result, null, 2)))
    .catch((error) => {
      console.error(error.message);
      process.exitCode = 1;
    });
}
