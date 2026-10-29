import type { PageCopy } from "../types";

export const en: PageCopy = {
  chrome: {
    breadcrumb: "Breadcrumb",
    home: "Home",
    guides: "Guides",
    related: "Related guides",
  },
  notFound: {
    title: "Page not found | Airdraft",
    heading: "This page doesn’t exist",
    action: "Go to the homepage",
  },
  hub: {
    title: "Mac dictation setup and model guides | Airdraft",
    description:
      "Airdraft guides: offline dictation, mixed Chinese and English, coding agents, local or cloud models, private transcription, app comparisons and editions.",
    heading: "Dictation guides",
    help: [
      "Already set up and something is wrong?",
      "Check permissions, shortcuts and common problems.",
    ],
    pricing: "Compare Pricing",
    changes: "See What Changed",
  },
  support: {
    title: "Airdraft support: permissions, shortcuts and models",
    description:
      "Fix common Airdraft problems with permissions, shortcuts and models, or report a bug.",
    heading: "Support",
  },
  privacy: {
    title: "Airdraft privacy: what stays on your Mac",
    description:
      "How Airdraft handles dictation data, optional app usage data and website analytics, and how to change either choice.",
    heading: "Privacy",
  },
  changelog: {
    title: "Airdraft changelog: every release, newest first",
    description:
      "Airdraft release history, from the first source build to speech models per profile, local intelligence and a new native interface.",
    heading: "Changelog",
    nav: "Release versions",
    latest: "Latest release",
    source: "Source",
    releaseNotes: "Release notes",
    initialSource: "Initial source",
    sourceFor: (label, version) => `${label} for ${version}`,
    firstBuild: "the first source build",
    availability: [
      "Published installers are personal-use builds signed with Apple Development, without notarization. See ",
      "installation guidance",
      ".",
    ],
  },
  guides: {
    "offline-dictation-on-mac": {
      title: "Set up offline dictation on your Mac",
      description:
        "Set up Airdraft with local speech recognition and optional local cleanup: Mac requirements, which model to choose, permissions and profiles.",
      summary:
        "Choose a speech model for your language, keep cleanup local, and make your first dictation.",
    },
    "mixed-chinese-english-dictation": {
      title: "Dictate mixed Chinese and English on a Mac",
      description:
        "Choose a local speech model for Mandarin mixed with English terms, with Airdraft’s own measurement of errors, terms kept, size, memory and speed.",
      summary:
        "Pick a local model for mixed Mandarin and English, with Airdraft's own measured trade-offs.",
    },
    "dictate-to-claude-code-and-terminals": {
      title: "Dictate prompts into Claude Code, Codex and terminals",
      metaTitle: "Dictate prompts into Claude Code, Codex and terminals",
      description:
        "Speak prompts into Claude Code, Codex and terminals on a Mac: how pasting works in self-drawing terminals, refinement on your plan, and what leaves your Mac.",
      summary:
        "Speak prompts into coding agents and terminals, and refine them on the plan you already pay for.",
    },
    "local-vs-cloud-dictation": {
      title: "Choose local or cloud dictation",
      description:
        "Compare Airdraft's local and cloud speech and refinement options. See where audio, transcripts and enabled app context go before choosing a setup.",
      summary:
        "See where your audio and text go with each combination of models.",
    },
    "free-source-or-official-app": {
      title: "Choose the free source build or official app",
      description:
        "Compare Airdraft's complete free source build with its one-time official app license, including setup, updates, Mac limits and current availability.",
      summary:
        "Compare setup, updates and license terms, including what is available now.",
    },
    "private-meeting-transcription": {
      title: "Transcribe meetings privately on your Mac",
      description:
        "Use the Transcribe page to record a meeting’s app audio and your microphone or import a file, then transcribe it on your Mac with optional speaker labels.",
      summary:
        "Record a call or import a file, label speakers, and export subtitles.",
    },
    "compare-mac-dictation-apps": {
      title:
        "Compare Airdraft with VoiceInk, Handy, Typeless and Apple Dictation",
      metaTitle: "Airdraft vs VoiceInk, Handy, Typeless and Apple Dictation",
      description:
        "A dated comparison of Airdraft, VoiceInk, Handy, Typeless and Apple Dictation: price, source, where speech runs, file transcription and where each is better.",
      summary:
        "See prices, data flow and transcription of recordings and files side by side, including where others are better.",
    },
  },
};
