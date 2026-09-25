// Cloud speech list prices, copied from the app's model catalogue
// (Packages/AirdraftCore/Sources/AirdraftCore/Providers/SpeechModelInfo.swift).
// Each row is the provider's default model. Update this with the catalogue.
export const catalogueDate = "September 2026";

export const cloudSpeechPrices: {
  provider: string;
  model: string;
  price: string;
}[] = [
  { provider: "Groq", model: "Whisper Large v3 Turbo", price: "$0.04" },
  { provider: "Soniox", model: "Soniox v5", price: "≈ $0.10" },
  { provider: "ElevenLabs", model: "Scribe v2", price: "$0.22" },
  { provider: "Deepgram", model: "Nova-3", price: "$0.258" },
  { provider: "OpenAI", model: "GPT-Transcribe", price: "$0.27" },
  { provider: "OpenRouter", model: "Several", price: "Varies by model" },
];
