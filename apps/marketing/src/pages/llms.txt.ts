import type { APIRoute } from "astro";
import { guides, guidesFor } from "../data/guides";
import { siteLinks } from "../data/site";
import { productFacts } from "../lib/llms";
import { languageName, locales, localizedPath } from "../i18n";
import { pages } from "../locales";
import { messages } from "../i18n/messages";

// Optional navigation for tools that read llms.txt. HTML is authoritative;
// this file is not a ranking signal or a crawler permission mechanism.
export const GET: APIRoute = ({ site }) => {
  if (!site) throw new Error("The site directory requires Astro.site.");
  const url = (path: string) => new URL(path, site).href;
  const facts = productFacts();
  // Every page in every other language, in that language.
  const translated = locales
    .filter((locale) => locale !== "en")
    .map((locale) => {
      const home = messages[locale].home;
      const pricing = messages[locale].pricing;
      const copy = pages[locale];
      return [
        `## ${languageName[locale]}`,
        "",
        `- [Airdraft](${url(localizedPath("/", locale))}): ${home.description}`,
        `- [${pricing.heading}](${url(localizedPath("/pricing/", locale))}): ${pricing.description}`,
        `- [${copy.support.heading}](${url(localizedPath("/support/", locale))}): ${copy.support.description}`,
        `- [${copy.changelog.heading}](${url(localizedPath("/changelog/", locale))}): ${copy.changelog.description}`,
        `- [${copy.privacy.heading}](${url(localizedPath("/privacy/", locale))}): ${copy.privacy.description}`,
        `- [${copy.hub.heading}](${url(localizedPath("/guides/", locale))}): ${copy.hub.description}`,
        ...guidesFor(locale).map(
          (guide) =>
            `- [${guide.title}](${url(guide.href)}): ${guide.description}`,
        ),
      ].join("\n");
    })
    .join("\n\n");
  return new Response(
    `# Airdraft

> Airdraft is an open-source menu-bar dictation app for Apple silicon Macs running macOS 15 or later. It transcribes speech, optionally refines the text, and inserts it at the cursor. Speech and refinement providers are chosen independently. Its Transcribe page records app audio and the microphone or imports audio and video files, then transcribes them on the Mac or with Soniox, with optional speaker labels and summaries, for a meeting or any other recording.

${facts}

The linked pages contain current product facts and availability. A longer plain-text version, with the homepage and pricing questions answered, is at ${url("/llms-full.txt")}.

## Product

- [Airdraft](${url("/")}): Features and an illustrative dictation sample.
- [Pricing and availability](${url("/pricing/")}): Source build, official licenses, and provider costs.
- [Support](${url("/support/")}): Permissions, setup, and troubleshooting.
- [Changelog](${url("/changelog/")}): Product changes with original release links.

## Guides

${guides.map((guide) => `- [${guide.title}](${url(guide.href)}): ${guide.description}`).join("\n")}

${translated}

## Source

- [Source repository](${siteLinks.source}): Implementation and license.
- [Build instructions](${siteLinks.build}): Build Airdraft from source.
`,
    { headers: { "Content-Type": "text/plain; charset=utf-8" } },
  );
};
