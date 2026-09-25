// @ts-check
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

// The production domain is also the canonical URL for local previews.
const site = process.env.SITE_URL?.trim() || "https://airdraft.app";
if (!/^https:\/\/[^/]+/.test(site)) {
  throw new Error("SITE_URL must be an absolute HTTPS URL.");
}

export default defineConfig({
  site,
  output: "static",
  integrations: [sitemap({ filter: (page) => !page.includes("/design/") })],
  devToolbar: { enabled: false },
});
