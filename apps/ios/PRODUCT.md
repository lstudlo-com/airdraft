# Airdraft for iPhone: product

Dictation on iPhone that writes clean text: speak in Airdraft or with the
Airdraft keyboard in any app, choose an on-device model or your own online
service, and keep everything on the phone unless you choose otherwise.

## Goals

1. **Dictate anywhere.** The keyboard's microphone works in any app during a
   keyboard session, and the text lands where the user was typing.
2. **Private by default.** On-device speech first; online providers only with
   the user's own key and a clear note of what they receive.
3. **Same quality rules as the Mac.** Profiles, vocabulary and refinement follow
   the Mac's contracts: refinement never loses speech, the dictionary has the
   last word.
4. **Honest about the phone.** Only models that fit an iPhone, no claims that
   were not measured on one.
5. **The Mac's material.** The same neutral neumorphism in the content, with
   the system's navigation around it.

## Status

Implemented behavior only; release and verification status live in the vault.

| Area | Behavior |
| --- | --- |
| Home | Record key with a level well; status and setup problems; last dictation with Copy and Share; keyboard session card |
| Keyboard | Microphone key driven by the session, space, delete (repeats), return, globe; inserts its own delivery and confirms it |
| Keyboard session | Standby input for 2–60 minutes (default 5), Live Activity, model preloaded, ends on time or by the user |
| Controls and shortcuts | Control Center / Action Button controls and App Shortcuts: Dictate, Keyboard Session |
| Speech | Apple Speech, Core ML Parakeet (v3 INT4, v3, v2, Japanese), Whisper Large v3 Turbo 626 MB, GGUF SenseVoice Small, Whisper Small/Base; cloud providers with keys; language choice |
| Refinement | Off, Apple Intelligence, OpenAI, Anthropic, Gemini, OpenRouter, Groq, Cerebras, a self-hosted server; model list loading; raw text on failure |
| Profiles and vocabulary | Choose the active profile; add, edit and delete terms |
| History | Day sections, search, detail with original transcript, delivery and engines; delete |
| Transcribe | Import audio or video, record long audio from the microphone, optional on-device speaker labels, resumable jobs, copy and share |
| Onboarding | Welcome, microphone, speech, keyboard; can be skipped |
| Languages | English, Spanish, Japanese, Simplified and Traditional Chinese |

## Not in this version

Payments (deferred), profile editing and app rules, live text, the Edit and
send-after-paste features, iCloud sync of profiles and vocabulary, measured iOS
model recommendations, and an iPad layout.
