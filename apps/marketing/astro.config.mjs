// @ts-check
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import languages from "./src/i18n/locales.json" with { type: "json" };
import { lastCommitted, sourcesOf } from "./src/lib/source-dates.mjs";

// The production domain is also the canonical URL for local previews.
const configuredSite = process.env.SITE_URL?.trim() || "https://airdraft.app";
let siteURL;
try {
  siteURL = new URL(configuredSite);
} catch {
  throw new Error("SITE_URL must be an absolute HTTPS origin.");
}
if (
  !/^https:\/\//i.test(configuredSite) ||
  siteURL.protocol !== "https:" ||
  siteURL.username ||
  siteURL.password ||
  siteURL.pathname !== "/" ||
  siteURL.search ||
  siteURL.hash
) {
  throw new Error(
    "SITE_URL must be an HTTPS origin without a path, credentials, query, or fragment.",
  );
}
const site = siteURL.origin;
const excludedPaths = new Set(["/design/", "/404/"]);

export default defineConfig({
  site,
  output: "static",
  trailingSlash: "always",
  integrations: [
    sitemap({
      filter: (page) => !excludedPaths.has(new URL(page).pathname),
      // <lastmod>: when the page's own sources last changed in Git.
      serialize(item) {
        const files = sourcesOf(
          new URL(item.url).pathname,
          languages.map((language) => language.code),
        );
        const date = files.length ? lastCommitted(files) : "";
        return date ? { ...item, lastmod: date } : item;
      },
      // Pairs each translated page with its English original by path
      // (src/i18n/locales.json), as xhtml:link alternates in the sitemap.
      i18n: {
        defaultLocale: "en",
        locales: Object.fromEntries(
          languages.map((language) => [language.code, language.tag]),
        ),
      },
    }),
  ],
  devToolbar: { enabled: false },
});
