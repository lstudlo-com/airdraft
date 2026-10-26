/**
 * Every guide's slug, shared by every language's page, in the order the
 * guide picker lists them. Kept apart from guides.ts, which imports the
 * site's copy, so Node scripts (test-analytics.mjs) can read it alone.
 */
export const guideSlugs = [
  "offline-dictation-on-mac",
  "mixed-chinese-english-dictation",
  "dictate-to-claude-code-and-terminals",
  "local-vs-cloud-dictation",
  "free-source-or-official-app",
  "private-meeting-transcription",
  "compare-mac-dictation-apps",
] as const;

export type GuideSlug = (typeof guideSlugs)[number];
