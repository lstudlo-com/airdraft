import type { APIRoute } from "astro";
import { guides } from "../data/guides";
import { siteLinks } from "../data/site";

// Optional navigation for tools that read llms.txt. HTML is authoritative;
// this file is not a ranking signal or a crawler permission mechanism.
export const GET: APIRoute = ({ site }) => {
  if (!site) throw new Error("The site directory requires Astro.site.");
  const url = (path: string) => new URL(path, site).href;
  return new Response(
    `# Airdraft

> Airdraft is an open-source menu-bar dictation app for Apple silicon Macs running macOS 15 or later. It transcribes speech, optionally refines the text, and inserts it at the cursor. Speech and refinement providers are chosen independently.

The linked pages contain current product facts and availability. The source build is free. See Pricing for official-build availability and license terms.

## Product

- [Airdraft](${url("/")}): Features and an illustrative dictation sample.
- [Pricing and availability](${url("/pricing/")}): Source build, official licenses, and provider costs.
- [Support](${url("/support/")}): Permissions, setup, and troubleshooting.
- [Changelog](${url("/changelog/")}): Product changes with original release links.

## Guides

${guides.map((guide) => `- [${guide.title}](${url(guide.href)}): ${guide.description}`).join("\n")}

## Source

- [Source repository](${siteLinks.source}): Implementation and license.
- [Build instructions](${siteLinks.build}): Build Airdraft from source.
`,
    { headers: { "Content-Type": "text/plain; charset=utf-8" } },
  );
};
