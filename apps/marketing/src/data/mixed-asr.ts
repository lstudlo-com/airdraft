import type { Locale } from "../i18n";
import { siteLinks } from "./site";

/**
 * Airdraft's own measurement of local speech models on mixed Chinese–English
 * speech (AD-074), with its dated SenseVoice follow-up. Every value comes from
 * eval/mixed-asr/README.md and eval/mixed-asr/results/ in the repository;
 * change them only together with a new measurement and its date. The guides
 * quote these numbers as Airdraft's measurement on one Mac, with its method
 * and caveats, never as a general accuracy claim or a comparison with other
 * apps.
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
  // The 2026-10-24 follow-up (README "2026-10-24 follow-up", results/
  // followup-2026-10-24/): the original multilingual SenseVoice, which the app
  // now installs as "SenseVoice", against the Cantonese fine-tune that 0.11.0
  // and earlier installed under that name ("SenseVoice Cantonese"), through
  // the same route, from a working tree based on 0196926, with AD-082's output
  // guards active.
  followup: {
    date: "2026-10-24",
    sourceCommit: "0196926",
  },
};

export interface MixedAsrResult {
  /** The model's name in the app's Models page. */
  model: string;
  /** A short line under the model's name, for rows that need their date or version. */
  note?: Record<Locale, string>;
  /**
   * The download size the Models page shows, character for character:
   * ByteCountFormatter's decimal total of the pinned files
   * (Packages/AirdraftCore/.../local-pinned-models.json), or the fixed label
   * for the sherpa-onnx archives (SherpaTranscriber.Model.sizeLabel). A listed
   * size, not a measured transfer.
   */
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
  /** Measured median peak memory of the app process, or null when not comparable. */
  memory: string | null;
}

// Language Auto rows (a new install's default). For Qwen3-ASR 1.7B, Auto and
// Chinese are statistically indistinguishable on real speech. Rows without a
// note are AD-074 (2026-10-21, results/summary.json).
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
    download: "712.8 MB",
    mer: 10.7,
    englishKept: 73,
    ttsMer: 5.9,
    ttsCaseKept: 56,
    medianMs: 244,
    memory: "1.3 GB",
  },
  {
    // The original SenseVoiceSmall (sherpa:senseVoiceMultilingual), from
    // results/followup-2026-10-24/summary.json, Auto: mer 0.126, english_
    // retention 0.5929, Meijia mer 0.1221 and english_retention_case_exact
    // 0.5517, latency_ms_median 52. Memory is the eja-asr follow-up's "about
    // 0.9 GB" (peak_mb_median 882–918 MB on FLEURS read speech), because the
    // mixed follow-up recorded only maximum peaks.
    model: "SenseVoice",
    note: { en: "Measured 2026-10-24", "zh-tw": "2026-10-24 測量" },
    download: "163 MB",
    mer: 12.6,
    englishKept: 59,
    ttsMer: 12.2,
    ttsCaseKept: 55,
    medianMs: 52,
    memory: "0.9 GB",
  },
  {
    model: "Whisper Large v3 Turbo",
    download: "1.64 GB",
    mer: 21.1,
    englishKept: 68,
    ttsMer: 6.3,
    ttsCaseKept: 48,
    medianMs: 634,
    memory: null,
  },
  {
    // The WSYue Cantonese fine-tune (sherpa:senseVoice) that 0.11.0 and
    // earlier installed as "SenseVoice": the AD-074 row, before AD-082's
    // output guards restored English case.
    model: "SenseVoice Cantonese",
    note: { en: "0.11.0 and earlier", "zh-tw": "0.11.0 及更早版本" },
    download: "166 MB",
    mer: 13.6,
    englishKept: 53,
    ttsMer: 10.3,
    ttsCaseKept: 7,
    medianMs: 52,
    memory: "0.9 GB",
  },
];

/** A difference in percentage points with its 95% paired-bootstrap interval. */
export interface MixedAsrDelta {
  points: number;
  ci: [number, number];
}

/**
 * Paired differences from the 2026-10-24 follow-up (README table, summary.json
 * `paired_vs_sensevoice_auto`), language Auto. Negative error differences
 * favour the first-named model.
 */
export const mixedAsrFollowup = {
  // Qwen3-ASR 1.7B − SenseVoice, ASCEND: mer_delta −0.0366, retention_delta
  // +0.1681.
  qwenVsSenseVoice: {
    errors: { points: -3.7, ci: [-5.3, -2.1] } as MixedAsrDelta,
    englishKept: { points: 16.8, ci: [8.9, 24.9] } as MixedAsrDelta,
  },
  // SenseVoice − SenseVoice Cantonese: ASCEND mer_delta −0.0096, Meijia
  // +0.0188. Statistically tied on both sets.
  originalVsCantonese: {
    realErrors: { points: -1.0, ci: [-2.6, 0.7] } as MixedAsrDelta,
    ttsErrors: { points: 1.9, ci: [-1.9, 5.6] } as MixedAsrDelta,
  },
  // SenseVoice Cantonese's Meijia english_retention_case_exact (0.5747) in the
  // same follow-up run, with the output guards active.
  cantoneseCaseKeptWithGuards: 57,
};
