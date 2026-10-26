import { changelogFor } from "../data/changelogs";
import { languageTag, localizedPath, type Locale } from "../i18n";
import { messages } from "../i18n/messages";
import { pages } from "../locales";

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

/** The changelog's RSS feed in `locale`, at /<code>/changelog.xml. */
export function changelogFeed(locale: Locale, site: URL): Response {
  const copy = pages[locale].changelog;
  const feed = new URL(
    `${localizedPath("/", locale)}changelog.xml`.replace(/^\/\//, "/"),
    site,
  ).href;
  const page = new URL(localizedPath("/changelog/", locale), site).href;
  const items = changelogFor(locale).map((entry) => {
    const link = `${page}#${entry.id}`;
    const label =
      entry.source.label === "Initial source"
        ? copy.initialSource
        : copy.releaseNotes;
    const description = [
      ...entry.changes.map(
        (change) => `${change.title}: ${change.description}`,
      ),
      copy.availability[0].trim(),
      `${label}: ${entry.source.url}`,
    ].join("\n\n");
    // The source stores publication days in Asia/Taipei, not exact timestamps.
    const date = new Date(`${entry.date}T00:00:00+08:00`).toUTCString();
    return `<item><title>${xml(`${entry.version ? `${entry.version}: ` : ""}${entry.title}`)}</title><link>${xml(link)}</link><guid isPermaLink="true">${xml(link)}</guid><pubDate>${date}</pubDate><description>${xml(description)}</description></item>`;
  });
  return new Response(
    `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel>
<title>${xml(messages[locale].layout.rss)}</title><link>${xml(page)}</link>
<description>${xml(copy.description)}</description>
<language>${languageTag[locale]}</language><atom:link href="${xml(feed)}" rel="self" type="application/rss+xml"/>
${items.join("\n")}
</channel></rss>`,
    { headers: { "Content-Type": "application/rss+xml; charset=utf-8" } },
  );
}
