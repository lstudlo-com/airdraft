import type { Locale } from "../i18n";
import type { PageCopy } from "./types";
import { en } from "./en/pages";
import { zhTw } from "./zh-tw/pages";
import { zhCn } from "./zh-cn/pages";
import { es } from "./es/pages";
import { ja } from "./ja/pages";

export type { PageCopy } from "./types";

export const pages: Record<Locale, PageCopy> = {
  en,
  "zh-tw": zhTw,
  "zh-cn": zhCn,
  es,
  ja,
};
