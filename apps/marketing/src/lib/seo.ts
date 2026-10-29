import { license, licenses, siteLinks } from "../data/site";
import { languageTag, locales, type Locale } from "../i18n";

export interface Breadcrumb {
  name: string;
  path: string;
}

export const siteName = "Airdraft";
export const defaultTitle =
  "Airdraft | Mac dictation and transcription, local or cloud";
export const defaultDescription =
  "Open-source Mac dictation: speak into any app, mix English terms into your language, and transcribe recordings. Runs on your Mac or your own provider.";
/** Each language's sharing image (scripts/render-social-card.swift). */
export const socialImagePath = (locale: Locale) =>
  locale === "en" ? "/social-card.png" : `/social-card-${locale}.png`;
/** The social card's text, described in each page's language. */
export const socialImageAlt: Record<Locale, string> = {
  en: "Airdraft: Speak into any app. Transcribe anything. Keep it on your Mac. Open source, with local or cloud models.",
  "zh-tw":
    "Airdraft：在任何 App 裡用說的輸入，什麼聲音都能轉成逐字稿，資料留在你的 Mac。開放原始碼，可用本機或雲端模型。",
  "zh-cn":
    "Airdraft：在任何 App 里用说的输入，什么声音都能转成文字稿，数据留在你的 Mac。开源，可用本机或云端模型。",
  es: "Airdraft: habla en cualquier app, transcribe lo que sea y mantenlo en tu Mac. Código abierto, con modelos locales o en la nube.",
  ja: "Airdraft：どのアプリにも話して入力し、なんでも文字起こし。データは Mac に。オープンソースで、ローカルまたはクラウドのモデルを使えます。",
};

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

/** A guide's dates (ISO 8601), from Git (src/lib/source-dates.mjs). */
export interface ArticleDates {
  published?: string;
  modified?: string;
}

export function pageStructuredData({
  canonical,
  title,
  description,
  breadcrumbs = [],
  locale = "en",
  home: isHome = false,
  version,
  article,
}: {
  canonical: URL;
  title: string;
  description: string;
  breadcrumbs?: Breadcrumb[];
  locale?: Locale;
  /** A homepage in any language: names the site and the app. */
  home?: boolean;
  /** The latest published app version (src/data/changelog.ts). */
  version?: string;
  article?: ArticleDates;
}) {
  const home = new URL("/", canonical);
  const websiteID = new URL("#website", home).href;
  const applicationID = new URL("#application", home).href;
  const publisherID = new URL("#publisher", home).href;
  const breadcrumbID = new URL("#breadcrumbs", canonical).href;
  const pageID = new URL("#webpage", canonical).href;
  const graph: Record<string, unknown>[] = [];

  if (isHome) {
    graph.push(
      {
        "@type": "WebSite",
        "@id": websiteID,
        name: siteName,
        url: home.href,
        inLanguage: locales.map((entry) => languageTag[entry]),
        publisher: { "@id": publisherID },
      },
      {
        "@type": "Organization",
        "@id": publisherID,
        name: siteName,
        url: home.href,
        logo: new URL("/airdraft-icon.png", home).href,
        sameAs: [siteLinks.source],
      },
      {
        "@type": "SoftwareApplication",
        "@id": applicationID,
        name: siteName,
        url: canonical.href,
        description,
        inLanguage: languageTag[locale],
        image: new URL("/airdraft-icon.png", home).href,
        applicationCategory: "UtilitiesApplication",
        operatingSystem: "macOS 15 or later",
        processorRequirements: "Apple silicon",
        ...(version && { softwareVersion: version }),
        license: license?.url,
        isAccessibleForFree: true,
        publisher: { "@id": publisherID },
        sameAs: [siteLinks.source],
        // The free source build is the edition available today; the
        // official app's licenses join once checkout opens.
        offers: [
          {
            "@type": "Offer",
            name: "Source build",
            price: "0",
            priceCurrency: "USD",
            url: siteLinks.build,
            availability: "https://schema.org/InStock",
          },
          ...(siteLinks.checkout
            ? licenses.map((plan) => ({
                "@type": "Offer",
                name: plan.title,
                price: plan.price.replace(/[^0-9.]/g, ""),
                priceCurrency: "USD",
                url: siteLinks.checkout,
                availability: "https://schema.org/InStock",
              }))
            : []),
        ],
        featureList: [
          "Dictation with text insertion at the cursor",
          "Independent local or cloud speech recognition and refinement",
          "Editable writing profiles and vocabulary corrections",
          "Local, searchable dictation history",
          "Audio recording from apps and the microphone, and audio or video file transcription with optional speaker labels and summaries",
          "Dictation in many languages, with English and technical terms mixed in, using the selected speech model",
          "Traditional or Simplified Chinese output, including mixed Chinese and English speech with supported models",
        ],
      },
    );
  }

  graph.push({
    "@type": "WebPage",
    "@id": pageID,
    url: canonical.href,
    name: title,
    description,
    inLanguage: languageTag[locale],
    isPartOf: { "@id": websiteID },
    about: { "@id": applicationID },
    ...(breadcrumbs.length > 1 && {
      breadcrumb: { "@id": breadcrumbID },
    }),
    ...(article?.modified && { dateModified: article.modified }),
  });

  if (article) {
    graph.push({
      "@type": "TechArticle",
      "@id": new URL("#article", canonical).href,
      headline: title,
      description,
      inLanguage: languageTag[locale],
      mainEntityOfPage: { "@id": pageID },
      about: { "@id": applicationID },
      author: { "@id": publisherID },
      publisher: { "@id": publisherID },
      image: new URL(socialImagePath(locale), home).href,
      ...(article.published && { datePublished: article.published }),
      ...(article.modified && { dateModified: article.modified }),
    });
  }

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
