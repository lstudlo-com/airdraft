import type { Locale } from "../i18n";
import {
  changelog,
  type ChangelogEntry,
  type ChangelogText,
} from "./changelog";
import { changelog as zhTw } from "../locales/zh-tw/changelog";
import { changelog as zhCn } from "../locales/zh-cn/changelog";
import { changelog as es } from "../locales/es/changelog";
import { changelog as ja } from "../locales/ja/changelog";

const translations: Record<Exclude<Locale, "en">, ChangelogText> = {
  "zh-tw": zhTw,
  "zh-cn": zhCn,
  es,
  ja,
};

/**
 * The changelog in `locale`: dates, versions and links from the English
 * entries, words from the language's file. A missing or misshapen entry
 * fails the build, so no language falls back to English.
 */
export function changelogFor(locale: Locale): ChangelogEntry[] {
  if (locale === "en") return changelog;
  const text = translations[locale];
  const extra = Object.keys(text).filter(
    (id) => !changelog.some((entry) => entry.id === id),
  );
  if (extra.length)
    throw new Error(`${locale} changelog has unknown entries: ${extra}`);
  return changelog.map((entry) => {
    const words = text[entry.id];
    if (!words || words.changes.length !== entry.changes.length)
      throw new Error(
        `${locale} changelog: ${entry.id} is missing or has a different number of changes.`,
      );
    return { ...entry, title: words.title, changes: words.changes };
  });
}
