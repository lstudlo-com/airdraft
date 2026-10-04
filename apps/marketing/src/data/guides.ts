export interface Guide {
  slug: string;
  title: string;
  description: string;
  summary: string;
  href: string;
}

// These are product guides, not a catalogue of keyword variations. Keep each
// guide's setup instructions and limits aligned with the native app.
export const guides: Guide[] = [
  {
    slug: "offline-dictation-on-mac",
    title: "Set up offline dictation on your Mac",
    description:
      "Set up Airdraft with local speech recognition and optional local AI cleanup. Check Mac requirements, model downloads, permissions and profile settings.",
    summary:
      "Choose a speech model, keep cleanup local, and make your first dictation.",
    href: "/guides/offline-dictation-on-mac/",
  },
  {
    slug: "local-vs-cloud-dictation",
    title: "Choose local or cloud dictation",
    description:
      "Compare Airdraft's local and cloud speech and refinement options. See where audio, transcripts and enabled app context go before choosing a setup.",
    summary:
      "See where your audio and text go with each combination of models.",
    href: "/guides/local-vs-cloud-dictation/",
  },
  {
    slug: "free-source-or-official-app",
    title: "Choose the free source build or official app",
    description:
      "Compare Airdraft's complete free source build with its one-time official app license, including setup, updates, Mac limits and current availability.",
    summary:
      "Compare setup, updates and license terms, including what is available now.",
    href: "/guides/free-source-or-official-app/",
  },
];
