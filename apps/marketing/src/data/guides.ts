import { localizedPath, type Locale } from "../i18n";
import { pages } from "../locales";

/** Every guide's slug, shared by every language's page. */
export type GuideSlug =
  | "offline-dictation-on-mac"
  | "mixed-chinese-english-dictation"
  | "dictate-to-claude-code-and-terminals"
  | "local-vs-cloud-dictation"
  | "free-source-or-official-app"
  | "private-meeting-transcription"
  | "compare-mac-dictation-apps";

export interface Guide {
  slug: GuideSlug;
  title: string;
  description: string;
  summary: string;
  href: string;
}

// These are product guides, not a catalogue of keyword variations. Keep each
// guide's setup instructions and limits aligned with the native app. Every
// guide exists in every language at /<code>/guides/<slug>/; titles,
// descriptions and summaries are copy in src/locales/<code>/pages.ts.
export const guideSlugs: GuideSlug[] = [
  "offline-dictation-on-mac",
  "mixed-chinese-english-dictation",
  "dictate-to-claude-code-and-terminals",
  "local-vs-cloud-dictation",
  "free-source-or-official-app",
  "private-meeting-transcription",
  "compare-mac-dictation-apps",
];

/** The guides in `locale`, in that language, linking to that language. */
export const guidesFor = (locale: Locale): Guide[] =>
  guideSlugs.map((slug) => ({
    slug,
    ...pages[locale].guides[slug],
    href: localizedPath(`/guides/${slug}/`, locale),
  }));

/** The English guides. */
export const guides = guidesFor("en");

/** Each guide's graphic in the guide picker (GuideGlyph.astro), by slug. */
export type GuideGlyphKind =
  | "mixed"
  | "terminal"
  | "offline"
  | "dataflow"
  | "price"
  | "speakers"
  | "compare";

export const guideGlyphs: Record<GuideSlug, GuideGlyphKind> = {
  "mixed-chinese-english-dictation": "mixed",
  "dictate-to-claude-code-and-terminals": "terminal",
  "offline-dictation-on-mac": "offline",
  "local-vs-cloud-dictation": "dataflow",
  "free-source-or-official-app": "price",
  "private-meeting-transcription": "speakers",
  "compare-mac-dictation-apps": "compare",
};
