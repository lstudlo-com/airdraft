# Cloud refinement providers

## OpenRouter provider selection

In Models → Refinement, select OpenRouter and a model, then choose its inference
provider. Automatic leaves routing to OpenRouter. Each model remembers its own
provider and fallback preference across switches and restarts. The picker uses
OpenRouter's endpoint tags, preserving variants such as `deepinfra/turbo`.
Base provider choices with several listed endpoints are labelled **provider-wide**.
Their standard-tier endpoints are shown separately for comparison, with output
speed and collapsible details. Flex and Priority endpoints require an explicit
choice or service-tier opt-in, so they are excluded from base-provider metrics.
Selecting a specific variant restricts routing to that variant when fallback is off.

Choosing a provider defaults to using only that provider. Enable **Allow other
providers as fallback** to prefer it while letting OpenRouter try other hosts.
Account-level OpenRouter restrictions still apply. A saved provider that leaves
the catalog stays selected with an explanation; it is never silently reset.
Refinement failures continue to insert the raw transcript through the existing
pipeline fallback.
Selecting a provider sets `provider.order`, which takes precedence over the
automatic sorting of `:nitro` and `:floor` model variants.

The selected endpoint shows output tokens/second, reported latency and uptime
over OpenRouter's last 30 minutes, plus input/output/cached-input USD per million
tokens, context length, maximum output and quantization. Percentile measurements
use p50 and are labelled median; legacy scalar measurements are not. Missing
values show **Not reported**. OpenRouter's endpoint API does not define its latency
field as time to first token, so AirDraft labels it simply **Latency**. These are
provider measurements, not a local dictation benchmark. With Automatic, there is
no single host to report.

Provider metadata is fetched from
`GET /api/v1/models/{author}/{slug}/endpoints` without reading credentials or
sending dictation text. The endpoint returned data without authentication on
September 24, 2026, although its API reference marks bearer authentication as
required. Reload refreshes the list and measurements. Selecting
a different model cancels the previous lookup and clears its metrics. Requests
use the existing `llm.openrouter` Keychain credential. Exclusive routing sends
`provider.order`, `provider.only` and `allow_fallbacks: false`; preferred routing
sends `order` and `allow_fallbacks: true`. Both survive the one-time HTTP 400
compatibility retry. OpenRouter receives its native `reasoning` object, not
local-server options. AirDraft opts in to OpenRouter response metadata and reports
the selected host from that metadata in the connection test. When OpenRouter does
not return a selected host, the test says **Provider not reported**; the response
model alone does not identify the host. An authenticated response is still needed
to verify actual routing on the user's account.

Documentation checked September 24, 2026:

- [Endpoint discovery and metrics](https://openrouter.ai/docs/api/api-reference/endpoints/list-all-endpoints-for-a-model)
- [Provider routing](https://openrouter.ai/docs/guides/routing/provider-selection)
- [Chat completion response metadata](https://openrouter.ai/docs/api/api-reference/chat/create-a-chat-completion)
- [Reasoning settings](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)

## Cerebras and Groq

Select either provider in Models → Text refinement, save its API key, then choose
a model and press Test. Keys use `llm.cerebras` and `llm.groq` in the existing
Airdraft Keychain service. The Groq speech key is separate. Each provider remembers
its model and thinking preference when switching or restarting.

| Provider | Base URL | Default model |
|---|---|---|
| Cerebras | `https://api.cerebras.ai/v1` | `qwen-3.8-27b` |
| Groq | `https://api.groq.com/openai/v1` | `openai/gpt-oss-20b` |

Both use Bearer authentication, GET `/models`, and POST `/chat/completions`.
The model picker excludes known Groq speech, moderation and tool-using systems.
Custom model IDs remain available. Account-specific model access is determined by
the provider. Test sends the built-in sample text and may incur API usage.

The default Cerebras model supports disabling reasoning. Groq GPT-OSS requires
at least low effort, so Off maps to low and the UI explains this. Supported
Qwen models use none/low/medium/high. Unknown model IDs omit reasoning options.
Neither provider receives local-server `chat_template_kwargs`. A 400 retries once
with only model, messages and stream; authentication failures are not retried.
The normal dictation pipeline still falls back to the original transcript if
refinement fails, and dictionary processing still runs last.

Existing Local / self-hosted configurations migrate to Groq only when both their
URL and key reference exactly match the former built-in preset. Their model,
effort and existing `llm.groq` key survive. Custom URLs/key references are unchanged.

Contracts and default model availability checked on September 21, 2026:

- [Cerebras model catalog](https://inference-docs.cerebras.ai/models/overview)
- [Cerebras chat completions](https://inference-docs.cerebras.ai/api-reference/chat-completions)
- [Cerebras reasoning](https://inference-docs.cerebras.ai/capabilities/reasoning)
- [Groq models](https://console.groq.com/docs/models)
- [Groq reasoning](https://console.groq.com/docs/reasoning)
