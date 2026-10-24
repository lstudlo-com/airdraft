// The site's languages. English pages live at the root; each translation
// lives under /<code>/ with the English slug, so the sitemap's i18n links and
// each page's hreflang alternates pair them by path. `locales.json` is the
// single list: astro.config.mjs (sitemap alternates), the analytics path
// allowlist and scripts/check-search.py read the same file.
import definitions from "./locales.json" with { type: "json" };

export const locales = [
  "en",
  "zh-tw",
  "zh-cn",
  "es",
  "ja",
  "fr",
  "pt-br",
  "ru",
  "ar",
  "hi",
  "id",
] as const;
export type Locale = (typeof locales)[number];
/** The locales the guides are written in; the other languages link to English. */
export type GuideLocale = Extract<Locale, "en" | "zh-tw">;

interface Definition {
  code: string;
  tag: string;
  og: string;
  name: string;
  dir: string;
  paths: string[];
}
const byCode = new Map(
  (definitions as Definition[]).map((entry) => [entry.code, entry]),
);
if (
  definitions.length !== locales.length ||
  locales.some((code, index) => definitions[index]?.code !== code)
) {
  throw new Error("src/i18n/locales.json must list `locales` in order.");
}
const definition = (locale: Locale) => byCode.get(locale)!;
const table = <T>(pick: (entry: Definition) => T) =>
  Object.fromEntries(
    locales.map((locale) => [locale, pick(definition(locale))]),
  ) as Record<Locale, T>;

/** BCP 47 tags for `lang`, `hreflang` and structured data `inLanguage`. */
export const languageTag = table((entry) => entry.tag);

/** Open Graph locale codes. */
export const ogLocale = table((entry) => entry.og);

/** Each language's name in that language, for the language menu. */
export const languageName = table((entry) => entry.name);

/** Writing direction for `<html dir>`. */
export const direction = table((entry) => entry.dir as "ltr" | "rtl");

/**
 * English paths translated into each language at `/<code>` + path. Add a
 * path to locales.json only together with its translated page; the search
 * check requires every alternate to exist and link back.
 */
export const translatedPaths = table((entry) => entry.paths);

/**
 * Whether the app's interface in this language is in a published release.
 * Pages in the other languages quote the catalog labels and say that the
 * released app still shows English. Turn a language on when its release is
 * published.
 */
export const interfaceReleased: Record<Locale, boolean> = {
  en: true,
  "zh-tw": true,
  "zh-cn": true,
  es: false,
  ja: false,
  fr: false,
  "pt-br": false,
  ru: false,
  ar: false,
  hi: false,
  id: false,
};

const prefixed = locales.filter((locale) => locale !== "en");
const withSlash = (path: string) => `${path.replace(/\/+$/, "")}/`;

export function localeOf(pathname: string): Locale {
  return (
    prefixed.find(
      (locale) =>
        pathname === `/${locale}` || pathname.startsWith(`/${locale}/`),
    ) ?? "en"
  );
}

/** The English path a page translates, or the path itself. */
export function englishPath(pathname: string): string {
  const path = withSlash(pathname);
  const locale = localeOf(path);
  return locale === "en"
    ? path
    : withSlash(path.slice(locale.length + 1) || "/");
}

/** The path in `locale`, whether or not that page has been translated. */
export function localizedPath(path: string, locale: Locale): string {
  const english = englishPath(path);
  return locale === "en" ? english : `/${locale}${english}`;
}

/** Whether the English page at `path` exists in `locale`. */
export function isTranslated(path: string, locale: Locale): boolean {
  return locale === "en" || translatedPaths[locale].includes(englishPath(path));
}

/** Every language version of this page, or none if it is not translated. */
export function alternatesFor(
  pathname: string,
): { locale: Locale; path: string }[] {
  const english = englishPath(pathname);
  const versions = locales.filter((locale) => isTranslated(english, locale));
  return versions.length < 2
    ? []
    : versions.map((locale) => ({
        locale,
        path: localizedPath(english, locale),
      }));
}

/**
 * The language menu: every language, leading to this page's version in it,
 * or to that language's homepage when this page is not translated.
 */
export function languageChoices(pathname: string): {
  locale: Locale;
  path: string;
  translated: boolean;
  current: boolean;
  label: string;
}[] {
  const current = localeOf(pathname);
  return locales.map((locale) => {
    const translated = isTranslated(pathname, locale);
    return {
      locale,
      path: localizedPath(translated ? pathname : "/", locale),
      translated,
      current: locale === current,
      label: languageName[locale],
    };
  });
}

/** A route in the visitor's language when it exists, else the English one. */
export function href(path: string, locale: Locale): string {
  const [route, fragment] = path.split("#");
  const english = englishPath(route);
  const hash = fragment === undefined ? "" : `#${fragment}`;
  return `${isTranslated(english, locale) ? localizedPath(english, locale) : english}${hash}`;
}
