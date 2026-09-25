# Cloud transcription in Airdraft

Direct-provider research checked September 18, 2026; OpenRouter checked September 24, 2026.
These are file-transcription APIs: Airdraft sends the captured audio after
recording stops. Streaming first-token latency is not dictation completion latency.

| Provider / default model | Why it is included | Published USD per audio hour | Important tradeoff |
|---|---|---|---|
| Soniox / `stt-async-v5` | Value and Chinese/English code-switching, with vocabulary context | About $0.10 | Token-based estimate; context adds cost. Upload, job creation and polling add network round trips. |
| Groq / `whisper-large-v3-turbo` | Speed and the lowest listed base price in this selection | $0.04 | Older Whisper architecture, with lower reported accuracy than Groq's full Whisper model. Each request bills at least 10 seconds. |
| ElevenLabs / `scribe_v2` | Quality-focused option covering 90+ languages and varied accents | $0.22 | No claim of universal best accuracy. Paid keyterms, diarization and audio-event tags are omitted. |
| OpenAI / `gpt-transcribe` | Current general transcription model with native keyword and language hints | $0.27 | More expensive than Soniox/Groq. Dictionary terms are recognition hints, not guaranteed output. |
| Deepgram / `nova-3` | Noise robustness and smart formatting for dates, numbers and punctuation | $0.258 | Uses the pre-recorded monolingual rate. Automatic detection chooses the dominant language; it is not multilingual code-switching mode. |
| OpenRouter / `openai/whisper-1` | One speech-to-text endpoint with a live catalog of transcription-capable models | Varies by model | OpenRouter chooses the upstream host; transcription does not accept chat's provider pinning or fallback controls. Duration and token billing differ by model. |

These roles are a product selection based on current provider documentation, not an
Airdraft accuracy/latency benchmark. Prices exclude taxes, account-specific discounts
and optional add-ons. Network time, clip length, accent and language affect results.

## Model selection and evidence

The comparison table shows every supported file-transcription choice for the selected
provider at once. It uses the same row layout, selection control and Speed/Accuracy
meters as the local model table, with Price per hour replacing Storage.
Each selection changes the actual request and engine identity and is saved per
provider. Prices below are USD per audio hour; `≈` means a token-based estimate.
Direct-provider information was checked against the linked official pages on September 18, 2026.
OpenRouter's catalog and request contract were checked on September 24, 2026.

| Provider | Model / mode | Price | Quality / intended use | Published speed evidence |
|---|---|---|---|---|
| [OpenAI](https://developers.openai.com/api/docs/models/gpt-transcribe) | `gpt-transcribe` | $0.27 | High accuracy, keyword and language hints | Comparable file latency not published |
| [OpenAI](https://developers.openai.com/api/docs/models/gpt-4o-mini-transcribe) | `gpt-4o-mini-transcribe` | ≈$0.18 | Improved recognition over original Whisper; lower cost | Comparable file latency not published |
| [OpenAI](https://developers.openai.com/api/docs/models/gpt-4o-transcribe) | `gpt-4o-transcribe` | ≈$0.36 | Improved recognition over original Whisper | Comparable file latency not published |
| [Groq](https://console.groq.com/docs/speech-to-text) | `whisper-large-v3-turbo` | $0.04 | 12% word error rate in Groq's benchmark | 216× real time in Groq's benchmark |
| [Groq](https://console.groq.com/docs/speech-to-text) | `whisper-large-v3` | $0.111 | 10.3% word error rate in Groq's benchmark | 189× real time in Groq's benchmark |
| [ElevenLabs](https://elevenlabs.io/docs/overview/models) | `scribe_v2` | $0.22 | General recognition across 90+ languages | Comparable file latency not published |
| [ElevenLabs](https://elevenlabs.io/docs/overview/models) | `scribe_v2_medical` | $0.22 | Specialized clinical vocabulary | Comparable file latency not published |
| [Deepgram](https://developers.deepgram.com/docs/models-languages-overview) | `nova-3` · single language | $0.258 | Noisy/far-field speech; Mandarin supported | Faster than Deepgram Whisper, per provider |
| [Deepgram](https://developers.deepgram.com/docs/models-languages-overview) | Nova-3 · multilingual mode | $0.312 | Code-switching between ten supported languages; excludes Mandarin | Faster than Deepgram Whisper, per provider |
| [Deepgram](https://developers.deepgram.com/docs/deepgram-whisper-cloud) | `whisper-large` | $0.288 | Hosted Whisper Large v2; alternative recognition to compare against Nova | Slower than Nova, per provider |
| [Soniox](https://soniox.com/docs/stt/models) | `stt-async-v5` | ≈$0.10 | Mixed-language speech, including Chinese/English | Comparable file latency not published; asynchronous job processing |
| [OpenRouter](https://openrouter.ai/docs/guides/overview/multimodal/stt) | `openai/whisper-1` and live STT catalog | See live model price | Models must report `transcription` as an output modality; the provider and available models may change | Comparable file latency not published |

Prices: [OpenAI](https://developers.openai.com/api/docs/pricing),
[Groq](https://console.groq.com/docs/speech-to-text),
[ElevenLabs](https://elevenlabs.io/pricing/api),
[Deepgram](https://deepgram.com/pricing), [Soniox](https://soniox.com/pricing).
Deepgram prices use the pre-recorded pay-as-you-go column, not streaming rates.
Groq bills a minimum of ten seconds per request. Soniox context can add cost.
Paid vocabulary/entity add-ons are not enabled by Airdraft.

Nova-3 multilingual is a mode of `nova-3`, sent as `language=multi`, not a separate
upstream model ID. It overrides the Language setting and supports English, Spanish,
French, German, Hindi, Russian, Portuguese, Japanese, Italian and Dutch. The selected model details
explain this before use. Deepgram Whisper is included as an alternative recognition
family with different coverage, despite its slower processing; local model choices
are unchanged. Soniox has only one active asynchronous model, which the table
states explicitly. Retired aliases and realtime models are not offered.

Quality/speed descriptions are provider-reported and are not a shared cross-provider
benchmark. Airdraft does not turn unavailable measurements into invented ratings.
The UI includes these limits, the verification date, billing notes and official links.

Both tables use five-segment bars, with the value or **Not rated** printed beneath.
Local values retain Airdraft's relative 1–5 guidance. Cloud bars require published
numeric evidence: Groq speed is scaled to the fastest supported Groq model (216×),
and accuracy fill is `1 − WER / 100` with the original WER percentage alongside.
All other cloud meters are unfilled and labeled **Not rated**, not treated as zero.
The legend and source disclosure explain that local ratings and provider benchmarks
are different scales. No cross-provider ranking is implied. Model descriptions still
show the provider's documented language coverage, quality and processing tradeoffs.

### OpenRouter speech model discovery

OpenRouter speech uses `POST /api/v1/audio/transcriptions`, separate from the
Chat Completions endpoint used for refinement. Airdraft loads models from
`GET /api/v1/models?output_modalities=transcription`; the default models query
does not include them. Only entries declaring transcription output are selectable.
The live list can be refreshed, and four documented choices remain shown if
catalog loading fails: `openai/whisper-1` (the default),
`openai/whisper-large-v3-turbo`, `openai/gpt-transcribe`, and
`qwen/qwen3-asr-1.7b`. A selected model ID
survives a catalog refresh or app restart even if it is temporarily absent.

OpenRouter prices some models by audio second and others by tokens. Airdraft links
to each model's current price rather than converting catalog fields into an
unjustified common hourly estimate. The response's `usage.cost` is the actual USD
cost of a successful request. OpenRouter balances eligible upstream hosts; its
transcription endpoint currently ignores chat `provider.order`, `only`,
`allow_fallbacks`, `data_collection`, and `sort` controls. Therefore the speech UI
does not offer host pinning or imply that refinement's routing settings apply.
Both stages can use the same `llm.openrouter` Keychain key while retaining their
own provider and model selections.

Configuration, Models and History share 16-point card padding on all four sides.
Settings rows no longer add vertical padding on top of the card inset. Section
headings use an 8-point gap; sections use 20 points. Model columns adapt to the
900-point minimum window width. History trims surrounding blank lines for display
while preserving the stored and copied transcript.

## Connection testing

A Connection row with Test sits below the API-key row for every provider, matching
refinement. It tests the saved key, so Save first; without one it asks for a key.
Pending tests can be cancelled, and changing the key/model/provider invalidates
old results. Only Keychain stores saved credentials. Raw response
bodies and account details are never displayed or logged by the checker.

| Provider | Authenticated check | What success confirms |
|---|---|---|
| [OpenAI](https://developers.openai.com/api/reference/ruby/resources/models) | `GET /v1/models`, Bearer key | API access and selected model present |
| [Groq](https://console.groq.com/docs/models) | `GET /openai/v1/models`, Bearer key | API access and selected model present |
| [ElevenLabs](https://elevenlabs.io/docs/api-reference/user/get) | `GET /v1/user`, `xi-api-key` | Account access; key needs User Read permission |
| [Deepgram](https://developers.deepgram.com/guides/fundamentals/authenticating) | `GET /v1/auth/token`, Token key | Key accepted by the documented authentication check |
| [Soniox](https://soniox.com/docs/api-reference/stt/get_models) | `GET /v1/models`, Bearer key | API access and selected model present |
| [OpenRouter](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key) | `GET /api/v1/key` with Bearer key, then filtered STT catalog | Key accepted and selected model listed; neither proves a paid transcription will succeed |

These checks do not upload audio or run billable transcription. They do not prove
speech permissions, credit balance, model quality, or dictation latency. A restricted
key can allow transcription but deny account/model reads; the UI explains that
permission failures are separate from speech access. Requests use a ten-second
network deadline and distinguish auth, permissions, rate/quota limits, network failure,
malformed responses, unavailable models and cancellation.
OpenRouter's model catalog is public: it returns HTTP 200 even with an invalid
Bearer token. The key check must succeed separately before reporting Connected.

`AIRDRAFT_SELFTEST=connections` runs the same read-only checker for saved keys and
logs only provider names and sanitized outcomes; absent keys are skipped.
`AIRDRAFT_RENDER_ASR` and `AIRDRAFT_RENDER_ASR_MODEL` render each choice without
changing saved settings. `AIRDRAFT_RENDER_CONNECTION=testing|success|error` supplies
visual fixtures only during `--render-window`; no credentials or network calls.

## Provider integration changes

- OpenAI defaults to GPT-Transcribe and also offers both GPT-4o transcription
  variants. GPT-Transcribe uses `languages[]` and `keywords[]`; GPT-4o uses `language`
  and `prompt`. The separate compatible adapter serves Groq and custom endpoints.
- Scribe v1 is removed from built-in choices, and saved Scribe v1 configurations
  use Scribe v2. Groq Turbo and Scribe v2 remain because they still serve their roles.
- Soniox v5 and Deepgram Nova-3 are new native integrations.
- OpenRouter speech uses its native JSON transcription request: WAV bytes as plain
  base64 in `input_audio.data`, `input_audio.format = "wav"`, and a transcription
  model slug. Its Keychain key is shared with OpenRouter refinement. Speech never
  sends refinement's `provider` routing block. The upstream processing timeout is
  about 60 seconds; long recordings may need segmentation, which AirDraft does not
  yet add for this endpoint.
- Exact old OpenAI/Groq presets migrate with their existing Keychain accounts.
  Custom endpoints and custom credential references are preserved.
- Local engines and refinement profiles remain independent of the speech provider.
  Chinese script conversion and final dictionary replacement retain their existing order.

A provider is selected from `EndpointPreset.asr`; direct-provider model IDs live
in `ModelCatalog`, and OpenRouter uses its filtered live catalog with a documented
fallback. Direct providers use separate `asr.<provider>` Keychain accounts;
OpenRouter shares `llm.openrouter` across speech and refinement. The UI links to each
provider's key console and pricing page and explains why each choice exists.

## Why not more providers?

Mistral's Voxtral Mini Transcribe 2 is a credible 13-language option at $0.003/min,
but overlaps this selection's general transcription/value roles. Its launch article
compares against older competitor prices, so its cost ranking is not reused here.
AssemblyAI Universal-3 Pro is a credible English/domain-specialist alternative at
$0.21/hour; its documented six-language coverage does not include Mandarin.
Neither adds enough to this personal Chinese/English dictation shortlist to justify
a sixth integration. This is a scope decision, not a claim that either API is obsolete.

## API behavior and validation

All providers reject empty input and missing required keys before uploading audio.
Requests have finite timeouts and propagate HTTP/authentication/rate-limit errors.
Soniox has a single deadline spanning upload, creation, polling and result retrieval.
It attempts to delete only the job and file created by that dictation, including on
failure or cancellation. Each deletion has a two-second limit; cleanup failure is
logged without credentials or audio and does not discard a successful transcript.
If the network is unavailable, retained resources can be removed in the Soniox console.

Paid Deepgram/ElevenLabs keyterm add-ons are not enabled automatically. The local
dictionary still applies after refinement for every provider. Soniox and OpenAI
receive bounded dictionary hints through their native request fields.

`TranscriberWireTests` cover native request formats, WAV upload, response decoding,
missing keys, empty audio, malformed replies, HTTP failures, Soniox lifecycle,
deadline/cancellation cleanup, and cleanup failure. `SpeechPresetTests` cover preset
selection, migrations, custom endpoint preservation, factory routing and identities.
These use an isolated URLSession transport and do not spend API credits or upload
user recordings. Live quality and latency comparisons require provider credentials
and a common set of recordings; they are not claimed by these tests.

### Settings verification, September 18, 2026

- Final Xcode tests: **94 executed, 3 skipped, 0 failures**. The checks cover model
  routing, provider-switch/reload persistence, request contracts and connection
  errors, timeouts and cancellation. Debug build, strict signing and diff checks passed.
- Inspected all six pages in both themes, all five cloud model tables at 900 × 600,
  the local/cloud comparison, expanded source details, and connection-state fixtures.
  Configuration, Models (including Refinement, Memory and Speech options), and History
  were also inspected in the running app.
- Computer Use verified all eleven model choices, direct row selection, remembered
  choices after provider changes, model search and its empty state, local/cloud filters,
  and History's Original/Refined switch. The starting Groq Turbo selection was restored.
- The saved Soniox key passed the live connection check in the new layout. Earlier
  checks rejected deliberately invalid, unsaved keys for the other four providers.
  Valid-key checks for those four and paid transcription quality/latency remain
  unverified because those credentials are not saved on this Mac.
- No test credentials were saved. Render fixtures were confirmed to leave persisted
  speech settings unchanged. The app was relaunched from the tested, signed build.

### OpenRouter speech verification, September 24, 2026

- The public filtered models API returned 22 transcription entries. It also
  returned HTTP 200 with an invalid Bearer token, while `/api/v1/key` returned
  HTTP 401 for that token; this is why the connection checker uses both calls.
- Xcode ran 155 passing tests, 3 skips and no failures. Focused tests cover the
  JSON WAV request, omission of chat routing fields, catalog filtering, model-ID
  persistence, factory identity, key-first authentication and failure messages.
  The Debug app built successfully.
- All six pages were rendered and inspected in light and dark mode. The Models
  page was also inspected at full height with OpenRouter selected, including
  its speech table, Keychain editor, refinement settings and lower sections.
  Offscreen rendering deliberately skips live catalog and credential reads, so
  the image shows the four documented fallback choices.
- An isolated WAV pipeline self-test completed through Apple Speech and confirmed
  the raw-transcript LLM fallback, dictionary pass and history write in the log.
  This checks shared pipeline behavior; it does not exercise OpenRouter speech.
- No OpenRouter key was available in the current Keychain account or shell
  environment. No authenticated transcription or served-host/activity check was
  performed. A real request remains necessary to verify upstream acceptance,
  latency, `usage.cost` and the selected host for each tested model.

## Primary sources

- [OpenAI GPT-Transcribe model and pricing](https://developers.openai.com/api/docs/models/gpt-transcribe)
- [OpenAI file transcription and new array fields](https://developers.openai.com/api/docs/guides/speech-to-text)
- [Groq transcription models, speed figures, pricing and minimum billing](https://console.groq.com/docs/speech-to-text)
- [ElevenLabs API pricing](https://elevenlabs.io/pricing/api)
- [ElevenLabs file transcription contract](https://elevenlabs.io/docs/api-reference/speech-to-text/convert)
- [Soniox model lifecycle and v5](https://soniox.com/docs/stt/models)
- [Soniox pricing](https://soniox.com/pricing)
- [Soniox async API](https://soniox.com/docs/stt/async/async-transcription)
- [Soniox request and response schema](https://soniox.com/docs/openapi.yaml)
- [Deepgram pre-recorded API](https://developers.deepgram.com/reference/speech-to-text/listen-pre-recorded)
- [Deepgram pricing](https://deepgram.com/pricing)
- [Deepgram Traditional Chinese support](https://developers.deepgram.com/changelog/2026/3/31)
- [Mistral Voxtral Transcribe 2](https://mistral.ai/news/voxtral-transcribe-2/)
- [AssemblyAI Universal-3 Pro languages and pricing](https://www.assemblyai.com/blog/universal-3-pro-prompt-engineering)
- [OpenRouter speech-to-text guide, model discovery, request, usage and pricing](https://openrouter.ai/docs/guides/overview/multimodal/stt)
- [OpenRouter transcription API schema](https://openrouter.ai/docs/api/api-reference/stt/create-transcription)
- [OpenRouter current-key endpoint](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key)
- [OpenRouter transcription routing limits](https://openrouter.ai/blog/tutorials/transcription-on-openrouter/)
