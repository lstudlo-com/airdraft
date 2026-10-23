import { siteLinks } from "./site";

/**
 * Airdraft's own measurement of local speech models on English, Japanese and
 * Korean read speech (AD-083). Every value comes from eval/eja-asr/README.md
 * and eval/eja-asr/results/summary.json in the repository; change them only
 * together with a new measurement and its date. The guides quote these numbers
 * as Airdraft's measurement on one Mac, with its method and caveats, never as
 * a general accuracy claim, a ranking or a comparison with other apps.
 */
export const ejaAsrStudy = {
  date: "2026-10-24",
  sourceCommit: "7f79be0",
  hardware: "Apple M4 Pro, 48 GB, macOS 27.0.1",
  methodURL: `${siteLinks.source}/tree/main/eval/eja-asr`,
  // Google FLEURS test split (CC BY 4.0): read Wikipedia sentences, not
  // dictation. 60 utterances per language.
  utterancesPerLanguage: 60,
};

export type EjaLanguage = "en" | "ja" | "ko";

/** A percentage error rate with its 95% bootstrap interval. */
export interface EjaError {
  value: number;
  ci: [number, number];
}

export interface EjaAsrResult {
  /** The model's name in the app's Models page. */
  model: string;
  /**
   * The download size the Models page lists, character for character:
   * ByteCountFormatter's decimal total of the pinned files, or the fixed
   * label for the sherpa-onnx archive. A listed size, not a measured transfer.
   */
  download: string;
  /**
   * Model output (summary.json `error_raw`, before the Chinese script
   * conversion), Language set to Detect Automatically. WER for English, CER
   * for Japanese and Korean.
   */
  auto: EjaError;
  /** The same with Language set to the spoken language; null where the model ignores it. */
  explicit: EjaError | null;
  /** Median ASR time per utterance after loading (`asr_ms_median`), milliseconds. */
  medianMs: number;
}

export const ejaAsrMetric: Record<EjaLanguage, "WER" | "CER"> = {
  en: "WER",
  ja: "CER",
  ko: "CER",
};

// The models first-run setup recommends or offers for these languages, plus
// the shipped SenseVoice that 0.11.0 and earlier recommended.
export const ejaAsrResults: Record<EjaLanguage, EjaAsrResult[]> = {
  en: [
    {
      model: "Parakeet TDT v2",
      download: "464.4 MB",
      auto: { value: 3.5, ci: [2.3, 4.7] },
      explicit: null,
      medianMs: 68,
    },
    {
      model: "Qwen3-ASR 1.7B",
      download: "2.44 GB",
      auto: { value: 3.0, ci: [1.8, 4.3] },
      explicit: { value: 3.2, ci: [2.1, 4.5] },
      medianMs: 531,
    },
    {
      model: "Whisper Large v3 Turbo",
      download: "1.64 GB",
      auto: { value: 5.1, ci: [3.8, 6.5] },
      explicit: { value: 5.2, ci: [3.9, 6.6] },
      medianMs: 698,
    },
    {
      model: "SenseVoice",
      download: "166 MB",
      auto: { value: 32.4, ci: [26.9, 38.1] },
      explicit: { value: 31.6, ci: [26.2, 37.4] },
      medianMs: 103,
    },
  ],
  ja: [
    {
      model: "Qwen3-ASR 1.7B",
      download: "2.44 GB",
      auto: { value: 6.2, ci: [4.2, 8.8] },
      explicit: { value: 4.5, ci: [3.3, 5.9] },
      medianMs: 640,
    },
    {
      model: "Whisper Large v3 Turbo",
      download: "1.64 GB",
      auto: { value: 7.2, ci: [5.3, 9.2] },
      explicit: { value: 7.9, ci: [5.8, 10.2] },
      medianMs: 940,
    },
    {
      model: "SenseVoice",
      download: "166 MB",
      auto: { value: 76.4, ci: [74.0, 78.6] },
      explicit: { value: 76.3, ci: [73.9, 78.6] },
      medianMs: 127,
    },
  ],
  ko: [
    {
      model: "Qwen3-ASR 1.7B",
      download: "2.44 GB",
      auto: { value: 11.6, ci: [7.7, 15.8] },
      explicit: { value: 9.9, ci: [6.1, 13.8] },
      medianMs: 730,
    },
    {
      model: "Whisper Large v3 Turbo",
      download: "1.64 GB",
      auto: { value: 12.1, ci: [8.4, 16.3] },
      explicit: { value: 11.2, ci: [7.6, 15.1] },
      medianMs: 822,
    },
    {
      model: "SenseVoice",
      download: "166 MB",
      auto: { value: 77.4, ci: [74.2, 80.5] },
      explicit: { value: 77.8, ci: [74.7, 80.8] },
      medianMs: 169,
    },
  ],
};
