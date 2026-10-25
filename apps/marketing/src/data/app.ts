import type { Locale } from "../i18n";

/**
 * App interface labels the site quotes, as the app shows them in each
 * language. Look each English key up in Sources/App/Localizable.xcstrings
 * (and AirdraftCore's catalog) before adding or changing one: zh-tw is the
 * zh-Hant entry, zh-cn zh-Hans, es and ja their own entries. A label
 * without a catalog entry stays as the app shows it. `hold` and `holdAfter`
 * are the two halves of Home's first-run caption around the key caps
 * (HomeHero.swift). `refinementFailed` is the first clause of the pipeline's
 * refinement-failure notice.
 *
 * Built-in profile names: the app localizes them (RefinementProfile
 * .displayName). The English and Traditional Chinese pages were written when
 * they were English in both and keep that wording; the other languages use
 * the catalog names.
 */
const english = {
  // The recording window's processing states (IndicatorPanel.hudCaption).
  hudTranscribing: "Transcribing",
  hudRefining: "Refining",
  // The menu's processing status lines.
  listening: "Listening…",
  transcribing: "Transcribing…",
  refining: "Refining…",
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
  // Home's first-run caption, before and after the key caps.
  hold: "Hold",
  holdAfter: "and speak. Each dictation adds a bar.",
  // Built-in profile names.
  clean: "Clean",
  concise: "Concise",
  summary: "Summary",
  verbatim: "Verbatim",
  settings: "Settings",
  // The first words of the pipeline's refinement-failure notice.
  refinementFailed: "Refinement failed",
  // Meetings speaker labels ("Speaker %@").
  speaker: (number: number) => `Speaker ${number}`,
};

export type AppLabels = typeof english;

export const appLabels: Record<Locale, AppLabels> = {
  en: english,
  "zh-tw": {
    hudTranscribing: "轉錄中",
    hudRefining: "潤稿中",
    listening: "正在聆聽⋯",
    transcribing: "正在轉錄⋯",
    refining: "正在潤稿⋯",
    refined: "已潤稿",
    original: "原始",
    home: "首頁",
    profiles: "模式",
    vocabulary: "詞彙",
    history: "記錄",
    holdToTalk: "按住說話",
    toggle: "切換",
    hold: "按住",
    holdAfter: "並說話。每次聽寫都會增加一條長條。",
    clean: "Clean",
    concise: "Concise",
    summary: "Summary",
    verbatim: "Verbatim",
    settings: "設定",
    refinementFailed: "潤稿失敗",
    speaker: (number: number) => `講者 ${number}`,
  },
  "zh-cn": {
    hudTranscribing: "转录中",
    hudRefining: "润色中",
    listening: "正在收听…",
    transcribing: "正在转录…",
    refining: "正在润色…",
    refined: "已润色",
    original: "原始",
    home: "主页",
    profiles: "模式",
    vocabulary: "词汇",
    history: "历史记录",
    holdToTalk: "按住说话",
    toggle: "切换",
    hold: "按住",
    holdAfter: "并说话。每次听写都会增加一个柱条。",
    clean: "整理",
    concise: "简洁",
    summary: "摘要",
    verbatim: "逐字",
    settings: "设置",
    refinementFailed: "润色失败",
    speaker: (number: number) => `发言人 ${number}`,
  },
  es: {
    hudTranscribing: "Transcribiendo",
    hudRefining: "Refinando",
    listening: "Escuchando…",
    transcribing: "Transcribiendo…",
    refining: "Refinando…",
    refined: "Refinado",
    original: "Original",
    home: "Inicio",
    profiles: "Perfiles",
    vocabulary: "Vocabulario",
    history: "Historial",
    holdToTalk: "Mantener pulsado para hablar",
    toggle: "Alternar",
    hold: "Mantén pulsado",
    holdAfter: "y habla. Cada dictado añade una barra.",
    clean: "Limpio",
    concise: "Conciso",
    summary: "Resumen",
    verbatim: "Literal",
    settings: "Ajustes",
    refinementFailed: "Error en el refinamiento",
    speaker: (number: number) => `Hablante ${number}`,
  },
  ja: {
    hudTranscribing: "文字起こし中",
    hudRefining: "整形中",
    listening: "聞き取り中…",
    transcribing: "文字起こし中…",
    refining: "整形中…",
    refined: "整形済み",
    original: "元の内容",
    home: "ホーム",
    profiles: "プロファイル",
    vocabulary: "語彙",
    history: "履歴",
    holdToTalk: "長押しで話す",
    toggle: "切り替え",
    hold: "長押し",
    holdAfter: "して話します。音声入力するたびにバーが 1 本増えます。",
    clean: "クリーン",
    concise: "簡潔",
    summary: "要約",
    verbatim: "逐語",
    settings: "設定",
    refinementFailed: "整形に失敗しました",
    speaker: (number: number) => `話者 ${number}`,
  },
};
