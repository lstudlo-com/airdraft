// What a year of dictation costs: three Airdraft setups against two
// subscription apps, for one stated workload. Every figure below is derived
// from the list prices and the workload here, so change those, not the totals.
// Recheck the prices on `pricesCheckedOn` before publishing a new date.
import { licenses } from "./site";

export const pricesCheckedOn = "October 2026";

// A heavy but ordinary workday: 100 dictations of 15 seconds, 22 workdays.
export const workload = {
  dictationsPerDay: 100,
  secondsPerDictation: 15,
  workdaysPerMonth: 22,
  // Generous per-refinement token budget: system prompt, app context and the
  // transcript in; the refined text out (reasoning off, the app default).
  inputTokens: 1000,
  outputTokens: 150,
};

const dictationsPerMonth =
  workload.dictationsPerDay * workload.workdaysPerMonth;
const audioHoursPerMonth =
  (dictationsPerMonth * workload.secondsPerDictation) / 3600;

// List prices. Groq comes from the app's model catalogue
// (Packages/AirdraftCore/Sources/AirdraftCore/Providers/SpeechModelInfo.swift);
// Cerebras serves `qwen-3.8-27b`, the app's default Cerebras model
// (ProviderConfig.swift), at its pay-as-you-go rate.
const groqWhisperTurboPerAudioHour = 0.04;
const cerebrasQwenPerMillion = { input: 0.99, output: 1.49 };

const groqPerMonth = audioHoursPerMonth * groqWhisperTurboPerAudioHour;
const cerebrasPerMonth =
  (dictationsPerMonth *
    (workload.inputTokens * cerebrasQwenPerMillion.input +
      workload.outputTokens * cerebrasQwenPerMillion.output)) /
  1_000_000;

// The one-Mac license; the open-source build makes this $0.
const license = Number(licenses[0].price.replace("$", ""));

export const workloadSummary = {
  dictationsPerMonth,
  audioHoursPerMonth: Math.round(audioHoursPerMonth * 10) / 10,
};

export type CostRow = {
  name: string;
  detail: string;
  oneTime: number;
  monthly: number;
  airdraft: boolean;
};

// Airdraft rows say what leaves the Mac; the models are in the page's note.
export const costRows: CostRow[] = [
  {
    name: "All local",
    detail: "Nothing leaves your Mac",
    oneTime: license,
    monthly: 0,
    airdraft: true,
  },
  {
    name: "Local speech + Cerebras",
    detail: "Transcripts go to Cerebras",
    oneTime: license,
    monthly: cerebrasPerMonth,
    airdraft: true,
  },
  {
    name: "Groq + Cerebras",
    detail: "Audio to Groq, transcripts to Cerebras",
    oneTime: license,
    monthly: groqPerMonth + cerebrasPerMonth,
    airdraft: true,
  },
  {
    name: "Wispr Flow Pro",
    detail: "Billed yearly",
    oneTime: 0,
    monthly: 12,
    airdraft: false,
  },
  {
    name: "Typeless Pro",
    detail: "Billed yearly",
    oneTime: 0,
    monthly: 12,
    airdraft: false,
  },
];

export const totalAfter = (row: CostRow, years: number) =>
  row.oneTime + row.monthly * 12 * years;

export const formatUSD = (amount: number) =>
  amount === 0
    ? "$0"
    : amount < 10 && !Number.isInteger(amount)
      ? `$${amount.toFixed(2)}`
      : `$${Math.round(amount)}`;
