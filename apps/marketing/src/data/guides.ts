import type { Locale } from "../i18n";

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
      "Set up Airdraft with local speech recognition and optional local AI cleanup. Check Mac requirements, which model to choose, Airdraft's own English, Japanese and Korean measurement, permissions and profiles.",
    summary:
      "Choose a speech model for your language, keep cleanup local, and make your first dictation.",
    href: "/guides/offline-dictation-on-mac/",
  },
  {
    slug: "mixed-chinese-english-dictation",
    title: "Dictate mixed Chinese and English on a Mac",
    description:
      "Choose a local speech model for sentences that mix Mandarin and English terms. Airdraft's own measurement compares errors, English terms kept, size, memory and speed.",
    summary:
      "Pick a local model for mixed Mandarin and English, with Airdraft's own measured trade-offs.",
    href: "/guides/mixed-chinese-english-dictation/",
  },
  {
    slug: "dictate-to-claude-code-and-terminals",
    title: "Dictate prompts into Claude Code, Codex and terminals",
    description:
      "Speak prompts into Claude Code, Codex and terminal apps on a Mac. See how pasting works in self-drawing terminals, refinement on your existing plan, and what leaves your Mac.",
    summary:
      "Speak prompts into coding agents and terminals, and refine them on the plan you already pay for.",
    href: "/guides/dictate-to-claude-code-and-terminals/",
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
  {
    slug: "private-meeting-transcription",
    title: "Transcribe meetings privately on your Mac",
    description:
      "Record app audio and your microphone or import a file, then transcribe it on your Mac with optional speaker labels. Check permissions, limits and exports.",
    summary:
      "Record a call or import a file, label speakers, and export subtitles.",
    href: "/guides/private-meeting-transcription/",
  },
  {
    slug: "compare-mac-dictation-apps",
    title:
      "Compare Airdraft with VoiceInk, Handy, Typeless and Apple Dictation",
    description:
      "A dated comparison of Airdraft, VoiceInk, Handy, Typeless and Apple Dictation on macOS 27: price, source, where speech runs, meetings and where each is better.",
    summary:
      "See prices, data flow and meeting support side by side, including where others are better.",
    href: "/guides/compare-mac-dictation-apps/",
  },
];

// Traditional Chinese (Taiwan) translations, at the same slugs under /zh-tw/.
export const zhGuides: Guide[] = [
  {
    slug: "mixed-chinese-english-dictation",
    title: "在 Mac 上中英混著講的聽寫",
    description:
      "一句話裡夾著英文術語時，該選哪個本機語音模型？Airdraft 自己的測量比較錯誤率、英文詞保留、下載大小、記憶體與速度。",
    summary: "幫中英混說挑本機模型，附 Airdraft 自己測出的取捨。",
    href: "/zh-tw/guides/mixed-chinese-english-dictation/",
  },
  {
    slug: "dictate-to-claude-code-and-terminals",
    title: "用說的把提示詞送進 Claude Code、Codex 與終端機",
    description:
      "在 Mac 上用語音把提示詞輸入 Claude Code、Codex 與終端機：自行繪製文字的終端機怎麼貼上、怎麼沿用你的訂閱方案潤稿，以及哪些資料會離開 Mac。",
    summary: "用說的對程式助理下指令，並沿用你已付費的方案潤稿。",
    href: "/zh-tw/guides/dictate-to-claude-code-and-terminals/",
  },
  {
    slug: "private-meeting-transcription",
    title: "在 Mac 上私密地把會議轉成逐字稿",
    description:
      "錄下 App 音訊與麥克風，或匯入音訊、影片檔，在你的 Mac 上轉成逐字稿並可選擇標出講者。說明所需權限、限制與匯出格式。",
    summary: "錄下通話或匯入檔案，標出講者，再匯出字幕。",
    href: "/zh-tw/guides/private-meeting-transcription/",
  },
  {
    slug: "compare-mac-dictation-apps",
    title: "Airdraft 與 VoiceInk、Handy、Typeless、Apple 聽寫比較",
    description:
      "附查核日期的比較：Airdraft、VoiceInk、Handy、Typeless 與 macOS 27 的 Apple 聽寫，在價格、原始碼、語音在哪裡處理、會議功能，以及各自強項上的差異。",
    summary: "並排比較價格、資料去向與會議功能，也寫出別人比較好的地方。",
    href: "/zh-tw/guides/compare-mac-dictation-apps/",
  },
];

/**
 * The guides to list on a page in `locale`: the Traditional Chinese guides on
 * Traditional Chinese pages; elsewhere the English guides, which other
 * languages link to in English.
 */
export const guidesFor = (locale: Locale) =>
  locale === "zh-tw" ? zhGuides : guides;
