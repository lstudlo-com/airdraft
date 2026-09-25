import { siteLinks } from "./site";

interface ChangelogEntry {
  id: string;
  date?: string;
  title: string;
  summary: string;
  changes: { title: string; description: string }[];
  source?: { label: string; url: string };
}

// Newest first. Add release dates and versions only when they are published.
export const changelog: ChangelogEntry[] = [
  {
    id: "0-2-0",
    date: "2026-09-26",
    title: "0.2.0: New speech controls and a refreshed interface",
    summary:
      "This personal-use build is signed with Apple Development and is not notarized. A supported, notarized public installer is not available yet.",
    changes: [
      {
        title: "Check your connection",
        description:
          "Test API access from the key field for Soniox, Groq, ElevenLabs, OpenAI, and Deepgram before you dictate.",
      },
      {
        title: "Compare supported speech models",
        description:
          "Choose from each provider’s supported models, with pricing and available quality and speed information linked to official documentation. Unpublished metrics are clearly marked.",
      },
      {
        title: "A refreshed native interface",
        description:
          "A collapsible sidebar, live microphone meters, and a scrolling history timeline join consistent settings and model lists.",
      },
      {
        title: "Safer recording and recovery",
        description:
          "Airdraft checks recording prerequisites before capture and keeps failed speech audio available to retry or discard. Refinement errors still preserve the raw transcript.",
      },
    ],
  },
  {
    id: "initial-source",
    date: "2026-09-18",
    title: "Airdraft is on GitHub",
    summary:
      "The macOS app is available to build from source. A packaged download is not available yet.",
    changes: [
      {
        title: "Speak into the app you’re using",
        description:
          "Hold your shortcut, speak, and release to insert text at the cursor. Airdraft stays in your menu bar between thoughts.",
      },
      {
        title: "Choose each step independently",
        description:
          "Use local or cloud speech recognition and choose your refinement provider separately. If refinement fails, Airdraft keeps your raw transcript.",
      },
      {
        title: "Make it sound like you",
        description:
          "Edit and reset writing profiles, add names and specialist terms to your vocabulary, and revisit previous dictations in History.",
      },
    ],
    source: {
      label: "View initial source",
      url: `${siteLinks.source}/commit/16a392ed2dd2d4d7ec4a86eb23d5be74ae0bb31c`,
    },
  },
];
