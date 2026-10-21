// The site's languages. English pages live at the root; Traditional Chinese
// (Taiwan) translations live under /zh-tw/ with the same slug, so the sitemap's
// i18n links and each page's hreflang alternates pair them by path.
export const locales = ["en", "zh-tw"] as const;
export type Locale = (typeof locales)[number];

/** BCP 47 tags for `lang`, `hreflang` and structured data `inLanguage`. */
export const languageTag: Record<Locale, string> = {
  en: "en",
  "zh-tw": "zh-Hant-TW",
};

/** Open Graph locale codes. */
export const ogLocale: Record<Locale, string> = {
  en: "en_US",
  "zh-tw": "zh_TW",
};

/** The switch's label is always in the target language. */
export const languageName: Record<Locale, string> = {
  en: "English",
  "zh-tw": "繁體中文",
};

/**
 * The switch's label when this page has no translation and it leads to the
 * other language's homepage instead, in the target language.
 */
export const languageHomeName: Record<Locale, string> = {
  en: "English home",
  "zh-tw": "繁體中文首頁",
};

const zhPrefix = "/zh-tw";

/**
 * English paths that have a Traditional Chinese translation at
 * `/zh-tw` + path. Add a path here only together with its translated page;
 * the search check requires every alternate to exist and link back.
 */
export const translatedPaths = [
  "/",
  "/pricing/",
  "/guides/mixed-chinese-english-dictation/",
  "/guides/dictate-to-claude-code-and-terminals/",
  "/guides/private-meeting-transcription/",
  "/guides/compare-mac-dictation-apps/",
] as const;

const withSlash = (path: string) => `${path.replace(/\/+$/, "")}/`;

export function localeOf(pathname: string): Locale {
  return pathname === zhPrefix || pathname.startsWith(`${zhPrefix}/`)
    ? "zh-tw"
    : "en";
}

/** The English path a page translates, or the path itself. */
export function englishPath(pathname: string): string {
  const path = withSlash(pathname);
  return localeOf(path) === "zh-tw"
    ? withSlash(path.slice(zhPrefix.length) || "/")
    : path;
}

/** The path in `locale`, whether or not that page has been translated. */
export function localizedPath(path: string, locale: Locale): string {
  const english = englishPath(path);
  return locale === "zh-tw" ? `${zhPrefix}${english}` : english;
}

/** Every language version of this page, or none if it is not translated. */
export function alternatesFor(
  pathname: string,
): { locale: Locale; path: string }[] {
  const english = englishPath(pathname);
  if (!(translatedPaths as readonly string[]).includes(english)) return [];
  return locales.map((locale) => ({
    locale,
    path: localizedPath(english, locale),
  }));
}

/**
 * Where the language switch leads: this page's translation if there is one,
 * otherwise the other language's homepage. `label` names the destination in
 * its language, so an untranslated page says it leads to a homepage.
 */
export function switchTarget(pathname: string): {
  locale: Locale;
  path: string;
  translated: boolean;
  label: string;
} {
  const current = localeOf(pathname);
  const other: Locale = current === "en" ? "zh-tw" : "en";
  const alternate = alternatesFor(pathname).find(
    (entry) => entry.locale === other,
  );
  return alternate
    ? { ...alternate, translated: true, label: languageName[other] }
    : {
        locale: other,
        path: localizedPath("/", other),
        translated: false,
        label: languageHomeName[other],
      };
}

/** A route in the visitor's language when it exists, else the English one. */
export function href(path: string, locale: Locale): string {
  const english = englishPath(path.split("#")[0]);
  const hash = path.includes("#") ? `#${path.split("#")[1]}` : "";
  const translated = (translatedPaths as readonly string[]).includes(english);
  return `${locale === "zh-tw" && translated ? localizedPath(english, locale) : english}${hash}`;
}
