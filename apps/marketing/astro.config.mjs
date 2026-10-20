// @ts-check
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

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
      // Pairs each translated page with its English original by path
      // (src/i18n/index.ts), as xhtml:link alternates in the sitemap.
      i18n: {
        defaultLocale: "en",
        locales: { en: "en", "zh-tw": "zh-Hant-TW" },
      },
    }),
  ],
  devToolbar: { enabled: false },
});
