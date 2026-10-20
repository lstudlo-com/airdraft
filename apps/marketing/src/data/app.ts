import type { Locale } from "../i18n";

/**
 * App interface labels the site quotes, as the app shows them in each
 * language. The app ships English and Traditional Chinese and follows the
 * macOS language setting; the zh-tw values are the zh-Hant entries in
 * Sources/App/Localizable.xcstrings (and AirdraftCore's catalog). Look each
 * English key up there before adding or changing one; a label without a
 * catalog entry stays as the app shows it. Built-in profile names (Clean,
 * Concise, Summary, Verbatim) are data, not catalog strings, so they stay
 * English in both languages.
 */
export const appLabels = {
  en: {
    // The recording window's processing states (IndicatorPanel.hudCaption).
    // The site's sample shows Decoding where the app now says Transcribing.
    hudTranscribing: "Decoding",
    hudRefining: "Refining",
    // The menu's processing status lines.
    listening: "Listening…",
    transcribing: "Transcribing…",
    refining: "Refining…",
    // The first words of the pipeline's refinement-failure notice.
    refinementFailed: "Refinement failed",
    // History's version picker.
    refined: "Refined",
    original: "Original",
    // Sidebar destinations.
    home: "Home",
    profiles: "Profiles",
    vocabulary: "Vocabulary",
    history: "History",
    // Settings > Keyboard shortcuts modes.
    holdToTalk: "Hold to talk",
    toggle: "Toggle",
    // Meetings speaker labels ("Speaker %@").
    speaker: (number: number) => `Speaker ${number}`,
  },
  "zh-tw": {
    hudTranscribing: "轉錄中",
    hudRefining: "潤稿中",
    listening: "正在聆聽⋯",
    transcribing: "正在轉錄⋯",
    refining: "正在潤稿⋯",
    refinementFailed: "潤稿失敗",
    refined: "已潤稿",
    original: "原始",
    home: "首頁",
    profiles: "模式",
    vocabulary: "詞彙",
    history: "記錄",
    holdToTalk: "按住說話",
    toggle: "切換",
    speaker: (number: number) => `講者 ${number}`,
  },
} satisfies Record<Locale, Record<string, unknown>>;
