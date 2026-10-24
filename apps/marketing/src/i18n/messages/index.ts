import type { Locale } from "../index";
import type { Messages } from "./types";
import { ar } from "./ar";
import { en } from "./en";
import { es } from "./es";
import { fr } from "./fr";
import { hi } from "./hi";
import { id } from "./id";
import { ja } from "./ja";
import { ptBr } from "./pt-br";
import { ru } from "./ru";
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
  fr,
  "pt-br": ptBr,
  ru,
  ar,
  hi,
  id,
};
