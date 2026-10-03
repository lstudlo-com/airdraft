# Model brand assets

`ModelBrand.swift` maps speech models to their model family or creator. Hosting
services remain text beneath cloud model names: Whisper uses OpenAI's mark even
when served by Groq or Deepgram. Unknown models from a dynamic catalog use the
hosting service's logo until their creator is added to the mapping.

The assets are bundled in `Sources/App/Assets.xcassets/ModelBrand*.imageset`.
Opening Models never requests a logo over the network. Keep upstream artwork
intact; these marks identify the corresponding models and organizations.
Apple Speech retains the system `apple.logo` symbol. SenseVoice uses Alibaba's
company mark; Qwen uses the Qwen family mark.

Sources retrieved October 3, 2026:

| Asset | Source |
|---|---|
| Qwen | [Qwen site icon](https://img.alicdn.com/imgextra/i4/O1CN01OXv3EM1FN8t9W4P79_!!6000000000474-2-tps-80-80.png), linked by [qwen.ai](https://qwen.ai) |
| NVIDIA | [NVIDIA organization avatar](https://github.com/NVIDIA.png?size=128) |
| OpenAI | [OpenAI organization avatar](https://github.com/openai.png?size=128) |
| FireRed | [FireRedTeam organization avatar](https://github.com/FireRedTeam.png?size=128) |
| Alibaba | [Alibaba organization avatar](https://github.com/alibaba.png?size=128) |
| Cohere | [Cohere site icon](https://cohere.com/favicon-32x32.png) |
| ElevenLabs | [ElevenLabs site icon](https://elevenlabs.io/icon.svg) |
| Soniox | [Soniox site icon](https://soniox.com/icons/favicon-96x96.png) |
| Deepgram | [Deepgram organization avatar](https://github.com/deepgram.png?size=128) |
| Groq | [Groq organization avatar](https://github.com/groq.png?size=128) |
| OpenRouter | [OpenRouter site icon](https://openrouter.ai/favicon/glyph.png) |
| AssemblyAI | [AssemblyAI organization avatar](https://github.com/AssemblyAI.png?size=128) |
| Fish Audio | [Fish Audio organization avatar](https://github.com/fishaudio.png?size=128) |
| Google | [Google organization avatar](https://github.com/google.png?size=128) |
| Gemini | [Gemini model icon](https://www.gstatic.com/lamda/images/gemini_sparkle_4g_512_lt_f94943af3be039176192d.png), linked by [Gemini](https://gemini.google.com) |
| Meta | [Meta organization avatar](https://github.com/facebook.png?size=128) |
| Microsoft | [Microsoft organization avatar](https://github.com/microsoft.png?size=128) |
| Mistral | [Mistral organization avatar](https://github.com/mistralai.png?size=128) |
| xAI | [xAI organization avatar](https://github.com/xai-org.png?size=128) |

The creator mappings also cover the public [OpenRouter transcription catalog](https://openrouter.ai/api/v1/models?output_modalities=transcription).
Keep a model's creator separate from its hosting preset when adding entries.
