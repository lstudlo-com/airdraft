// When a page's sources last changed, from Git, for sitemap <lastmod> and
// guides' Article dates. A page's date is its newest source file's last
// commit. Outside a Git checkout (or for an unknown route) there is no
// date, and the page simply goes without one.
import { execFileSync } from "node:child_process";
import { join } from "node:path";

// Paths are relative to apps/marketing. The build bundles this module away
// from its source, so the app is found from the checkout's root instead.
const cache = new Map();
let app;

function git(args) {
  try {
    app ??= join(
      execFileSync("git", ["rev-parse", "--show-toplevel"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      }).trim(),
      "apps/marketing",
    );
    return execFileSync("git", args, {
      cwd: app,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

/** The newest commit date (ISO 8601) touching any of `files`, or "". */
export function lastCommitted(files) {
  const key = files.join("\n");
  if (!cache.has(key)) {
    cache.set(key, git(["log", "-1", "--format=%cI", "--", ...files]));
  }
  return cache.get(key);
}

/** The commit date that added `file`, or "". */
export function firstCommitted(file) {
  const key = `first:${file}`;
  if (!cache.has(key)) {
    const dates = git(["log", "--follow", "--format=%cI", "--", file]);
    cache.set(key, dates.split("\n").filter(Boolean).at(-1) ?? "");
  }
  return cache.get(key);
}

const views = {
  "/": ["src/views/HomePage.astro"],
  "/pricing/": [
    "src/views/PricingPage.astro",
    "src/data/site.ts",
    "src/data/pricing.ts",
  ],
  "/guides/": ["src/views/GuidesHub.astro"],
  "/support/": ["src/views/SupportPage.astro"],
  "/privacy/": ["src/views/PrivacyPage.astro"],
  "/changelog/": ["src/views/ChangelogPage.astro"],
};

/**
 * The source files of a page, by its path (/<code>/… for translations):
 * the shared view and that language's copy.
 */
export function sourcesOf(pathname, codes) {
  const code = codes.find((entry) => pathname.startsWith(`/${entry}/`)) ?? "en";
  const page = code === "en" ? pathname : pathname.slice(code.length + 1);
  const guide = page.match(/^\/guides\/([a-z0-9-]+)\/$/);
  if (guide) return [`src/locales/${code}/guides/${guide[1]}.astro`];
  const copy = {
    "/": [`src/i18n/messages/${code}.ts`],
    "/pricing/": [`src/i18n/messages/${code}.ts`],
    "/guides/": [`src/locales/${code}/pages.ts`],
    "/support/": [`src/locales/${code}/Support.astro`],
    "/privacy/": [`src/locales/${code}/Privacy.astro`],
    "/changelog/": [
      code === "en"
        ? "src/data/changelog.ts"
        : `src/locales/${code}/changelog.ts`,
    ],
  }[page];
  return copy ? [...views[page], ...copy] : [];
}
