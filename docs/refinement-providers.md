# Cerebras and Groq refinement

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
