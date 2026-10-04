import type { APIRoute } from "astro";

// Search policies checked 2026-10-05. Named groups document discovery intent;
// the wildcard keeps the existing access for training and user-triggered agents.
// https://developers.google.com/crawling/docs/robots-txt/robots-txt-spec
// https://www.bing.com/webmasters/help/webmaster-guidelines-30fba23a
// https://developers.openai.com/api/docs/bots
// https://support.claude.com/en/articles/8896518-does-anthropic-crawl-data-from-the-web-and-how-can-site-owners-block-the-crawler
// https://docs.perplexity.ai/docs/resources/perplexity-crawlers
const searchAgents = [
  "Googlebot",
  "Bingbot",
  "OAI-SearchBot",
  "Claude-SearchBot",
  "PerplexityBot",
  "*",
];

export const GET: APIRoute = ({ site }) =>
  new Response(
    `${searchAgents.map((agent) => `User-agent: ${agent}\nAllow: /\n`).join("\n")}\n${site ? `Sitemap: ${new URL("sitemap-index.xml", site)}\n` : ""}`,
    { headers: { "Content-Type": "text/plain; charset=utf-8" } },
  );
