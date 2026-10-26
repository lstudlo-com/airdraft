import type { PageCopy } from "../types";

// TRANSLATE: placeholder English copy; translate every string.
export const zhTw: PageCopy = {
  chrome: {
    breadcrumb: "Breadcrumb",
    home: "Home",
    guides: "Guides",
    related: "Related guides",
  },
  notFound: {
    title: "Page not found — Airdraft",
    heading: "This page doesn’t exist",
    action: "Go to the homepage",
  },
  hub: {
    title: "Mac dictation setup and model guides | Airdraft",
    description:
      "Practical Airdraft guides for offline Mac dictation in your language, mixed Chinese and English, dictating into Claude Code and terminals, local and cloud models, private meeting transcription, comparisons with other apps, and the free source build or official app.",
    heading: "Dictation guides",
    help: [
      "Already set up and something is wrong?",
      "Check permissions, shortcuts and common problems.",
    ],
    pricing: "Compare Pricing",
    changes: "See What Changed",
  },
  support: {
    title: "Support — Airdraft",
    description:
      "Fix common Airdraft problems with permissions, shortcuts and models, or report a bug.",
    heading: "Support",
  },
  privacy: {
    title: "Privacy | Airdraft",
    description:
      "How Airdraft handles dictation data, optional app usage data and website analytics, and how to change either choice.",
    heading: "Privacy",
  },
  changelog: {
    title: "Changelog — Airdraft",
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
        "Set up Airdraft with local speech recognition and optional local AI cleanup. Check Mac requirements, which model to choose, Airdraft's own English, Japanese and Korean measurement, permissions and profiles.",
      summary:
        "Choose a speech model for your language, keep cleanup local, and make your first dictation.",
    },
    "mixed-chinese-english-dictation": {
      title: "在 Mac 上中英混著講：本機模型怎麼選",
      description:
        "一句話夾著英文術語時，該選哪個本機語音模型？Airdraft 自行測量五個模型的錯誤率、英文詞保留率、下載大小、記憶體與速度。",
      summary: "中英混說該用哪個本機模型，附 Airdraft 的實測取捨。",
    },
    "dictate-to-claude-code-and-terminals": {
      title: "用語音在 Claude Code、Codex 與終端機輸入提示詞",
      description:
        "在 Mac 上用語音輸入 Claude Code、Codex 與終端機的提示詞：自繪文字的終端機如何貼上、如何沿用現有訂閱潤稿，以及哪些資料會離開 Mac。",
      summary: "用說的輸入提示詞，並沿用你已付費的訂閱潤稿。",
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
      title: "在自己的 Mac 上把會議轉成逐字稿",
      description:
        "錄下 App 音訊與麥克風，或匯入音訊、影片檔，在 Mac 上轉成逐字稿，可選擇標出講者。另說明所需權限、限制與匯出格式。",
      summary: "錄下通話或匯入檔案，標出講者，再匯出字幕。",
    },
    "compare-mac-dictation-apps": {
      title: "Airdraft 與 VoiceInk、Handy、Typeless、Apple 聽寫比較",
      description:
        "附查核日期，比較 Airdraft、VoiceInk、Handy、Typeless 與 macOS 27 的 Apple 聽寫：價格、原始碼、語音在哪裡處理、會議功能，以及各自的強項。",
      summary: "並排比較價格、資料去向與會議功能，也列出別人做得更好的地方。",
    },
  },
};
