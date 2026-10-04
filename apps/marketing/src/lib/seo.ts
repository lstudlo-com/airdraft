import { siteLinks } from "../data/site";

export interface Breadcrumb {
  name: string;
  path: string;
}

export const siteName = "Airdraft";
export const defaultTitle =
  "Airdraft | Open-source Mac dictation, local or cloud";
export const defaultDescription =
  "Airdraft is a Mac dictation app with independent local or cloud speech and refinement. Speak, release the shortcut, and insert text. Free to build from source.";
export const socialImageAlt =
  "Airdraft: The Mac transcription app you own. Open source, with local or cloud models.";

/** HTML routes use the same trailing slash as Astro's directory output. */
export function canonicalURL(path: string, site: URL): URL {
  if (!path.startsWith("/") || path.startsWith("//")) {
    throw new Error("Canonical paths must be absolute paths on this site.");
  }
  const canonical = new URL(path, site);
  if (canonical.origin !== site.origin) {
    throw new Error("Canonical paths must stay on this site.");
  }
  canonical.search = "";
  canonical.hash = "";
  canonical.pathname = `${canonical.pathname.replace(/\/+$/, "")}/`;
  return canonical;
}

/** Escape the HTML script boundary even when future copy contains markup. */
export function serializeStructuredData(value: unknown): string {
  return JSON.stringify(value).replace(/</g, "\\u003c");
}

export function pageStructuredData({
  canonical,
  title,
  description,
  breadcrumbs = [],
}: {
  canonical: URL;
  title: string;
  description: string;
  breadcrumbs?: Breadcrumb[];
}) {
  const home = new URL("/", canonical);
  const websiteID = new URL("#website", home).href;
  const applicationID = new URL("#application", home).href;
  const breadcrumbID = new URL("#breadcrumbs", canonical).href;
  const graph: Record<string, unknown>[] = [];

  if (canonical.pathname === "/") {
    graph.push(
      {
        "@type": "WebSite",
        "@id": websiteID,
        name: siteName,
        url: home.href,
        inLanguage: "en",
      },
      {
        "@type": "SoftwareApplication",
        "@id": applicationID,
        name: siteName,
        url: home.href,
        description: defaultDescription,
        image: new URL("/airdraft-icon.png", home).href,
        applicationCategory: "UtilitiesApplication",
        operatingSystem: "macOS 15 or later",
        processorRequirements: "Apple silicon",
        sameAs: [siteLinks.source],
        featureList: [
          "Dictation with text insertion at the cursor",
          "Independent local or cloud speech recognition and refinement",
          "Editable writing profiles and vocabulary corrections",
          "Local, searchable dictation history",
        ],
      },
    );
  }

  graph.push({
    "@type": "WebPage",
    "@id": new URL("#webpage", canonical).href,
    url: canonical.href,
    name: title,
    description,
    inLanguage: "en",
    isPartOf: { "@id": websiteID },
    about: { "@id": applicationID },
    ...(breadcrumbs.length > 1 && {
      breadcrumb: { "@id": breadcrumbID },
    }),
  });

  if (breadcrumbs.length > 1) {
    graph.push({
      "@type": "BreadcrumbList",
      "@id": breadcrumbID,
      itemListElement: breadcrumbs.map((entry, index) => ({
        "@type": "ListItem",
        position: index + 1,
        name: entry.name,
        item: canonicalURL(entry.path, home).href,
      })),
    });
  }

  return { "@context": "https://schema.org", "@graph": graph };
}
