/**
 * The copy of the pages translated into every language (homepage, pricing)
 * and of the shared chrome (header, footer, consent notice), one file per
 * language. Product facts, prices and provider names come from src/data;
 * only wording lives here. App interface labels are in src/data/app.ts.
 */

import type { GuideSlug } from "../../data/guides";

/** Pages a sentence can link to, in the sentence's language. */
export type LinkTarget =
  | "pricing"
  | "guides"
  | "meetingGuide"
  | "mixedGuide"
  | "agentGuide"
  | "offlineGuide"
  | "comparison";

/** A sentence with optional links, rendered by components/Rich.astro. */
export type Rich = (string | { link: LinkTarget; text: string })[];

/** Spoken sample text; fillers are struck through. */
export type Spoken = (string | { filler: string })[];

export interface Messages {
  /** The space between two sentences: "" in Chinese and Japanese. */
  gap: string;
  layout: { skip: string; rss: string };
  header: {
    pricing: string;
    support: string;
    changelog: string;
    home: string;
    nav: string;
    github: string;
    source: string;
    get: string;
    menu: string;
    /** The language menu's name, in this language. */
    language: string;
  };
  footer: {
    nav: string;
    build: string;
    pricing: string;
    guides: string;
    support: string;
    changelog: string;
    rss: string;
    privacy: string;
    license: string;
  };
  analytics: {
    title: string;
    body: string;
    privacy: string;
    decline: string;
    allow: string;
  };
  home: {
    title?: string;
    description?: string;
    headline: string[];
    /** Between headline phrases: " " in spaced scripts. */
    headlineGap: string;
    get: string;
    source: string;
    sample: string;
    facts: string[];
    guidesTitle: string;
    featuresTitle: string;
    spoken: string;
    outputs: string[];
    typed: string;
    /**
     * The mixed-language tile. "script" is the app's Chinese script picker
     * over one sentence; "languages" shows one sentence per language, each
     * with English terms.
     */
    mixed:
      | { kind: "script"; sentences: [string, string] }
      | { kind: "languages"; samples: { lang: string; sentence: string }[] };
    tiles: Record<
      | "cursor"
      | "shortcut"
      | "profiles"
      | "vocabulary"
      | "history"
      | "fallback"
      | "privacy"
      | "mixed"
      | "plan",
      [string, string]
    >;
    privacyArt: {
      mac: string;
      speech: string;
      refinement: string;
      cloud: string;
    };
  };
  preview: {
    name: string;
    said: string;
    inserts: string;
    picker: string;
    run: string;
    noscript: string;
    spoken: Spoken;
    examples: { clean: string; concise: string; summary: string };
    stop: string;
    again: string;
    placeholder: string;
  };
  meetings: {
    title: string;
    intro: string;
    sample: string;
    meeting: string;
    meta: string;
    turns: [number, string, string][];
    play: string;
    export: string;
    guide: string;
  };
  interface: {
    title: string;
    intro: string;
    alt: string;
    compare: string;
    half: string;
    allLight: string;
    allDark: string;
    mixed: string;
    materials: string;
    caption: string;
    drag: string;
    press: [string, string];
    select: [string, string];
    travel: [string, string];
    keysLabel: string;
    callouts: Record<
      | "Carved mark"
      | "Pressed well"
      | "Raised button"
      | "Raised card"
      | "Engraved divider"
      | "Reactive capsules",
      [string, string]
    >;
  };
  pipeline: {
    title: string;
    intro: string;
    speech: string;
    refinement: string;
    insertion: string;
    where: (stage: string) => string;
    mac: string;
    cloud: string;
    plan: string;
    speechMac: string;
    speechCloud: string;
    refinementMac: string;
    refinementCloud: string;
    refinementPlan: string;
    atCursor: string;
    insertionLine: string;
    /** The vocabulary sample around the corrected name. */
    fix: [string, string];
  };
  get: {
    title: string;
    intro: string;
    notOnSale: string;
    build: string;
    free: string;
    note: string;
    action: string;
  };
  license: {
    title: string;
    count: string;
    once: string;
    use: (macs: string) => string;
    rest: string;
    restNotOnSale: string;
    see: string;
    plans: Record<
      "one-mac" | "three-macs",
      { name: string; title: string; macs: string }
    >;
  };
  /**
   * The guide picker's tile labels (components/GuideLinks.astro): a few
   * words each, the full guide title stays the link's accessible name where
   * the guide exists in this language.
   */
  guideLinks: { labels: Record<GuideSlug, string> };
  pricing: {
    title: string;
    description: string;
    heading: string;
    intro: string;
    source: string;
    build: string;
    buildAction: string;
    sourceList: string;
    sourceIncludes: string[];
    app: string;
    once: string;
    buy: (macs: string) => string;
    notOnSale: string;
    appList: string;
    licenseIncludes: string[];
    currency: string;
    costTitle: string;
    costIntro: (dictationsPerMonth: string) => string;
    columns: [string, string, string, string];
    groups: [string, string];
    rows: Record<
      "local" | "local-cerebras" | "groq-cerebras" | "wispr" | "typeless",
      { name: string; detail: string }
    >;
    note: (values: {
      checked: string;
      perDay: number;
      seconds: number;
      inputTokens: string;
      outputTokens: number;
    }) => string;
    /** The month the prices were checked, e.g. "October 2026". */
    checked: (date: { year: number; month: number }) => string;
    questions: string;
    faq: {
      subscription: [string, Rich];
      licenses: [string, Rich];
      trial: [string, Rich];
      trialNotOnSale: [string, Rich];
      editions: [string, Rich];
      providers: [string, Rich];
      compare: [string, Rich];
    };
  };
}
