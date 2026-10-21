import { siteLinks } from "./site";

/**
 * Airdraft's own measurement of local speech models on mixed Chinese–English
 * speech (AD-074). Every value comes from eval/mixed-asr/README.md and
 * eval/mixed-asr/results/ in the repository; change them only together with a
 * new measurement and its date. The guides quote these numbers as Airdraft's
 * measurement on one Mac, with its method and caveats, never as a general
 * accuracy claim or a comparison with other apps.
 */
export const mixedAsrStudy = {
  date: "2026-10-21",
  sourceCommit: "2242fb4",
  hardware: "Apple M4 Pro, 48 GB, macOS 27.0.1",
  methodURL: `${siteLinks.source}/tree/main/eval/mixed-asr`,
  // Real code-switching: ASCEND (CAiRE, CC BY-SA 4.0), 100 utterances from
  // five speakers in Hong Kong and Mainland China.
  realUtterances: 100,
  // Taiwan-style sentences spoken by the macOS zh_TW Meijia voice.
  ttsSentences: 40,
};

export interface MixedAsrResult {
  /** The model's name in the app's Models page. */
  model: string;
  /** The download size the app lists for the pinned files (next version). */
  download: string;
  /** Mixed error rate on ASCEND, language Auto, as a percentage. */
  mer: number;
  /** Share of reference English words kept, ASCEND, language Auto. */
  englishKept: number;
  /** Mixed error rate on the Taiwan-style TTS sentences (Meijia), Auto. */
  ttsMer: number;
  /** English words kept with their original letter case, Meijia, Auto. */
  ttsCaseKept: number;
  /** Median ASR time per ASCEND utterance after loading, milliseconds. */
  medianMs: number;
  /** Median peak memory of the app process, or null when not comparable. */
  memory: string | null;
}

// Language Auto rows (a new install's default). For Qwen3-ASR 1.7B, Auto and
// Chinese are statistically indistinguishable on real speech.
export const mixedAsrResults: MixedAsrResult[] = [
  {
    model: "Qwen3-ASR 1.7B",
    download: "2.44 GB",
    mer: 8.9,
    englishKept: 76,
    ttsMer: 2.8,
    ttsCaseKept: 81,
    medianMs: 300,
    memory: "2.4 GB",
  },
  {
    model: "FireRedASR2",
    download: "840 MB",
    mer: 9.3,
    englishKept: 75,
    ttsMer: 5.9,
    ttsCaseKept: 8,
    medianMs: 612,
    memory: "2.7 GB",
  },
  {
    model: "Qwen3-ASR 0.6B",
    download: "713 MB",
    mer: 10.7,
    englishKept: 73,
    ttsMer: 5.9,
    ttsCaseKept: 56,
    medianMs: 244,
    memory: "1.3 GB",
  },
  {
    model: "SenseVoice",
    download: "166 MB",
    mer: 13.6,
    englishKept: 53,
    ttsMer: 10.3,
    ttsCaseKept: 7,
    medianMs: 52,
    memory: "0.9 GB",
  },
  {
    model: "Whisper Large v3 Turbo",
    download: "1.5 GB",
    mer: 21.1,
    englishKept: 68,
    ttsMer: 6.3,
    ttsCaseKept: 48,
    medianMs: 634,
    memory: null,
  },
];
