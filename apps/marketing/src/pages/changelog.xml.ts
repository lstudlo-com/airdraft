import type { APIRoute } from "astro";
import { changelog } from "../data/changelog";

const xml = (value: string) =>
  value.replace(/[<>&"']/g, (character) => {
    const entities: Record<string, string> = {
      "<": "&lt;",
      ">": "&gt;",
      "&": "&amp;",
      '"': "&quot;",
      "'": "&apos;",
    };
    return entities[character];
  });

export const GET: APIRoute = ({ site }) => {
  if (!site) throw new Error("The changelog feed requires Astro.site.");
  const feed = new URL("changelog.xml", site).href;
  const page = new URL("changelog/", site).href;
  const items = changelog.map((entry) => {
    const link = `${page}#${entry.id}`;
    const description = [
      ...entry.changes.map(
        (change) => `${change.title}: ${change.description}`,
      ),
      "Releases are personal-use Apple Development builds, not notarized public installers.",
      `${entry.source.label}: ${entry.source.url}`,
    ].join("\n\n");
    // The source stores publication days in Asia/Taipei, not exact timestamps.
    const date = new Date(`${entry.date}T00:00:00+08:00`).toUTCString();
    return `<item><title>${xml(`${entry.version ? `${entry.version}: ` : ""}${entry.title}`)}</title><link>${xml(link)}</link><guid isPermaLink="true">${xml(link)}</guid><pubDate>${date}</pubDate><description>${xml(description)}</description></item>`;
  });
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel>
<title>Airdraft changelog</title><link>${xml(page)}</link>
<description>Product changes and source releases for Airdraft, the open-source Mac dictation app.</description>
<language>en</language><atom:link href="${xml(feed)}" rel="self" type="application/rss+xml"/>
${items.join("\n")}
</channel></rss>`,
    { headers: { "Content-Type": "application/rss+xml; charset=utf-8" } },
  );
};
