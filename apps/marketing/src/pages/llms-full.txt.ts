import type { APIRoute } from "astro";
import { siteLinks } from "../data/site";
import { productFacts, richText } from "../lib/llms";
import { messages } from "../i18n/messages";

// The long companion to /llms.txt: the product facts plus the homepage and
// pricing questions with their answers, as plain Markdown in English. The
// HTML pages stay authoritative.
export const GET: APIRoute = ({ site }) => {
  if (!site) throw new Error("The site directory requires Astro.site.");
  const copy = messages.en;
  const onSale = Boolean(siteLinks.checkout);
  const home = copy.home.faq;
  const pricing = copy.pricing.faq;
  const questions = (list: [string, Parameters<typeof richText>[0]][]) =>
    list
      .map(
        ([question, answer]) =>
          `### ${question}\n\n${richText(answer, "en", site)}`,
      )
      .join("\n\n");
  return new Response(
    `# Airdraft

> ${copy.home.lede}

${productFacts()}

## Questions

${questions([
  onSale ? home.price : home.priceNotOnSale,
  home.macs,
  home.offline,
  home.data,
  home.apple,
])}

## Pricing questions

${questions([
  pricing.subscription,
  pricing.licenses,
  onSale ? pricing.trial : pricing.trialNotOnSale,
  pricing.editions,
  pricing.providers,
  pricing.compare,
])}

## Source

- [Source repository](${siteLinks.source})
- [Build instructions](${siteLinks.build})
- [Releases](${siteLinks.releases})
`,
    { headers: { "Content-Type": "text/plain; charset=utf-8" } },
  );
};
