import type { Locale } from "../index";
import type { Messages } from "./types";
import { en } from "./en";
import { es } from "./es";
import { ja } from "./ja";
import { zhCn } from "./zh-cn";
import { zhTw } from "./zh-tw";

export type { LinkTarget, Messages, Rich, Spoken } from "./types";

/** Every page's copy, by language (one file per language). */
export const messages: Record<Locale, Messages> = {
  en,
  "zh-tw": zhTw,
  "zh-cn": zhCn,
  es,
  ja,
};
