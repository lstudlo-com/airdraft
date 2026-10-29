import { monthYear } from "./format";
import type { Messages } from "./types";

export const en: Messages = {
  gap: " ",
  layout: { skip: "Skip to content", rss: "Airdraft releases" },
  header: {
    pricing: "Pricing",
    support: "Support",
    changelog: "Changelog",
    home: "Airdraft home",
    nav: "Main navigation",
    github: "Airdraft on GitHub",
    source: "Source on GitHub",
    get: "Get Airdraft",
    menu: "Menu",
    language: "Language",
  },
  footer: {
    nav: "Footer",
    build: "Build instructions",
    pricing: "Pricing",
    guides: "Guides",
    support: "Support",
    changelog: "Changelog",
    rss: "RSS",
    privacy: "Privacy",
    license: "License",
  },
  analytics: {
    title: "Optional website analytics",
    body: "Help us understand visits and which features interest people. No recordings or typed text.",
    privacy: "Privacy details",
    decline: "Decline",
    allow: "Allow Analytics",
  },
  home: {
    headline: ["Speak into any app.", "Transcribe anything."],
    headlineGap: " ",
    lede: "A dictation app for your Mac: hold a shortcut, speak, and tidy text lands at your cursor. It transcribes recordings and files too.",
    get: "Get Airdraft",
    source: "View source",
    sample: "Try the sample",
    facts: [
      "Open source",
      "On your Mac, or with your own provider",
      "macOS 15+ on Apple silicon",
    ],
    guidesTitle: "Setup guides",
    featuresTitle: "What Airdraft handles for you",
    faqTitle: "Questions",
    faq: {
      price: [
        "Is Airdraft free?",
        [
          "Yes. The source build is free, has every feature and needs Xcode to build. The ready-to-run app is a one-time license: $29 for one Mac or $49 for up to three. See ",
          { link: "pricing", text: "pricing" },
          ".",
        ],
      ],
      priceNotOnSale: [
        "Is Airdraft free?",
        [
          "Yes. The source build is free, has every feature and needs Xcode to build. The ready-to-run app will be a one-time license, $29 for one Mac or $49 for up to three; it isn’t on sale yet. See ",
          { link: "pricing", text: "pricing" },
          ".",
        ],
      ],
      macs: [
        "Which Macs does it run on?",
        [
          "Macs with Apple silicon running macOS 15 or later. Local speech models download once and then run on the Mac; setup shows each one’s size before you download it.",
        ],
      ],
      offline: [
        "Does it work offline?",
        [
          "Yes. With a local speech model, and Apple Intelligence or LM Studio for cleanup, dictation runs entirely on your Mac. See ",
          { link: "offlineGuide", text: "which model fits your language" },
          ".",
        ],
      ],
      data: [
        "What leaves my Mac?",
        [
          "With local models, your audio and text stay on it. If you choose a cloud provider for speech or cleanup, that step’s audio or text goes to it on your own API key, which stays in the Keychain. See ",
          { link: "localGuide", text: "local or cloud dictation" },
          ".",
        ],
      ],
      apple: [
        "How is it different from Apple Dictation?",
        [
          "You choose the speech model, an editable profile tidies what you said, it learns your names and terms, and it keeps a searchable history. See the dated ",
          { link: "comparison", text: "comparison" },
          ", including where other apps are better.",
        ],
      ],
    },
    // Illustrative outputs for the bento graphics (decorative, sample text).
    spoken: "Um, tell Maya the, uh, draft is coming tomorrow.",
    outputs: [
      "Tell Maya the draft is coming tomorrow.",
      "Draft to Maya tomorrow.",
      "Maya gets the draft tomorrow.",
    ],
    typed: "Hi Maya, I’ll send the draft tomorrow morning.",
    mixed: {
      kind: "languages",
      samples: [
        {
          lang: "es",
          sentence: "Antes de la demo, cambia la API key y haz push a main.",
        },
        {
          lang: "ja",
          sentence:
            "demo の前に API key を差し替えて、main に push してください。",
        },
        {
          lang: "zh-Hant",
          sentence: "明天 demo 前先把 API key 換掉，再 push 到 main。",
        },
        {
          lang: "fr",
          sentence: "Avant la démo, change l’API key et fais un push sur main.",
        },
      ],
    },
    tiles: {
      cursor: ["Inserts at your cursor", "In whatever app you’re typing in."],
      shortcut: ["One shortcut", "Hold ⌃⌥, or record your own."],
      profiles: ["Profiles", "Four built in, each one editable."],
      vocabulary: ["Vocabulary", "Teach it names and jargon once."],
      history: ["History", "Search it, flip to the original, copy."],
      fallback: ["Nothing is lost", "If cleanup fails, the raw text goes in."],
      privacy: [
        "Stays on your Mac",
        "Local models send nothing; keys stay in the Keychain.",
      ],
      mixed: [
        "Your language, English mixed in",
        "Mix English and technical terms into your sentences. Chinese can come out 繁體 or 简体.",
      ],
      plan: [
        "Your Claude or ChatGPT plan",
        "Claude Code or Codex, no API key.",
      ],
    },
    privacyArt: {
      mac: "This Mac",
      speech: "Speech",
      refinement: "Refinement",
      cloud: "Cloud, if you choose",
    },
  },
  preview: {
    title: "Hold, speak, let go",
    steps: [
      ["Hold", "and speak"],
      "Let go, and Airdraft tidies it",
      "It lands at your cursor",
    ],
    name: "Sample dictation",
    said: "What you said",
    inserts: "What Airdraft inserts",
    picker: "Refinement profile",
    run: "Run sample",
    noscript:
      "Showing the Clean profile. Turn on JavaScript to run the sample.",
    spoken: [
      "“",
      { filler: "Um," },
      " let Maya know I’ll send the draft tomorrow morning. ",
      { filler: "And, uh," },
      " ask if we can move our check-in to two.”",
    ],
    examples: {
      clean:
        "Hi Maya, I’ll send the draft tomorrow morning. Could we move our check-in to two?",
      concise:
        "Maya, I’ll send the draft tomorrow morning. Can we move our check-in to two?",
      summary:
        "Send Maya the draft tomorrow morning. Ask to move the check-in to two.",
    },
    stop: "Stop",
    again: "Run again",
    placeholder: "The text appears here when you let go.",
  },
  meetings: {
    title: "Turn any recording into a transcript",
    steps: [
      "Record or import",
      "Speakers split into lanes",
      "Written out, turn by turn",
      "Export to text or subtitles",
    ],
    sample: "Sample transcript",
    meeting: "Podcast interview",
    meta: "Oct 21 · 42:18 · Whisper Large v3 Turbo",
    turns: [
      [1, "0:02", "So why record every conversation?"],
      [2, "0:06", "I kept forgetting what people told me."],
      [1, "0:13", "And now?"],
      [2, "0:15", "Now I search them like email."],
    ],
    play: "Play sample",
    export: "Export",
    guide: "Transcription guide",
  },
  interface: {
    title: "An interface you’ll love to use",
    alt: "Airdraft’s Settings page in light mode: a sidebar beside raised cards for the microphone and appearance, including the six recording-window styles.",
    compare: "Compare light and dark appearance",
    half: "Half light, half dark",
    allLight: "All light",
    allDark: "All dark",
    mixed: "{light}% light, {dark}% dark",
    materials: "Materials in the window",
    caption: "Rendered from the app with the Graphite accent.",
    drag: "Drag to compare light and dark.",
    press: ["Keys that press in", "Hold ⌃⌥ on your keyboard to press them."],
    select: [
      "Selection that slides",
      "The well moves first; the icon’s island follows.",
    ],
    travel: [
      "Controls with travel",
      "Knobs and thumbs slide inside their tracks.",
    ],
    callouts: {
      "Carved mark": ["Carved mark", "Its waveform is cut in."],
      "Pressed well": ["Pressed well", "The current page sinks in."],
      "Raised button": ["Raised button", "Controls stand up to press."],
      "Raised card": ["Raised card", "Each section lifts off the page."],
      "Engraved divider": ["Engraved divider", "Rows split by a groove."],
      "Reactive capsules": [
        "Reactive capsules",
        "Five styles follow your voice.",
      ],
    },
  },
  pipeline: {
    title: "You choose where each step runs",
    speech: "Speech",
    refinement: "Refinement",
    insertion: "Insertion",
    where: (stage) => `Where ${stage.toLowerCase()} runs`,
    mac: "This Mac",
    cloud: "Cloud",
    plan: "Subscription",
    speechMac: "Audio never leaves your Mac.",
    speechCloud: "Audio goes to the provider, on your own API key.",
    refinementMac: "A local model cleans up the transcript. It stays here.",
    refinementCloud: "The transcript goes to the provider you pick.",
    refinementPlan: "Uses the Claude or ChatGPT plan you already pay for.",
    atCursor: "At your cursor",
    insertionLine:
      "Vocabulary fixes names last, then the text goes into the app you’re typing in.",
    heard: "um meet me in cooper tino at nine",
    refined: "Meet me in cooper tino at nine.",
    fix: ["Meet me in", "at nine."],
  },
  get: {
    title: "Get Airdraft",
    build: "Build it yourself",
    free: "Free",
    note: "Every feature. Needs Xcode on an Apple silicon Mac.",
    action: "Build instructions",
    notify: {
      lead: "Hear when the ready-to-run app goes on sale:",
      releases: "Watch releases on GitHub",
      feed: "Changelog RSS feed",
    },
  },
  license: {
    title: "Ready-to-run app",
    count: "Number of Macs",
    once: "one-time",
    use: (macs) => `Personal use on ${macs}.`,
    rest: " Every feature, with a 14-day trial first.",
    restNotOnSale: " Every feature, with a 14-day trial once it’s on sale.",
    see: "See pricing",
    plans: {
      "one-mac": { name: "1 Mac", title: "One Mac", macs: "one Mac" },
      "three-macs": {
        name: "3 Macs",
        title: "Three Macs",
        macs: "up to three Macs",
      },
    },
  },
  guideLinks: {
    labels: {
      "offline-dictation-on-mac": "Offline dictation",
      "mixed-chinese-english-dictation": "Mixed Chinese and English",
      "dictate-to-claude-code-and-terminals": "Claude\u00a0Code, Codex",
      "local-vs-cloud-dictation": "Local or cloud",
      "free-source-or-official-app": "Free or official app",
      "private-meeting-transcription": "Transcribe meetings privately",
      "compare-mac-dictation-apps": "Compare Airdraft",
    },
  },
  pricing: {
    title: "Airdraft pricing: free source build or one-time license",
    description:
      "Airdraft is free to build from source. The ready-to-run app is a one-time license: $29 for one Mac or $49 for up to three.",
    heading: "Pricing",
    intro: "Build it free, or buy the ready-to-run app once.",
    source: "Open source",
    build: "Build it yourself",
    buildAction: "Build instructions",
    sourceList: "The source build includes",
    sourceIncludes: [
      "Dictation and transcription",
      "Every feature, no locks",
      "Needs Xcode to build",
    ],
    app: "Ready-to-run app",
    once: "one-time",
    buy: (macs) => `Buy for ${macs}`,
    notOnSale: "Not on sale yet",
    appList: "Every license includes",
    licenseIncludes: [
      "Dictation and transcription",
      "Every feature, no Xcode",
      "14-day full-feature trial",
      "Updates to the version you buy",
      "Move it between Macs yourself",
    ],
    currency: "US dollars, before tax.",
    costTitle: "What a year of dictation costs",
    costIntro: (count) => `The same ${count} dictations a month, five ways.`,
    columns: ["Setup", "Per month", "First year", "Three years"],
    groups: ["Airdraft", "Subscriptions"],
    rows: {
      local: { name: "All local", detail: "Nothing leaves your Mac" },
      "local-cerebras": {
        name: "Local speech + Cerebras",
        detail: "Transcripts go to Cerebras",
      },
      "groq-cerebras": {
        name: "Groq + Cerebras",
        detail: "Audio to Groq, transcripts to Cerebras",
      },
      wispr: { name: "Wispr Flow Pro", detail: "Billed yearly" },
      typeless: { name: "Typeless Pro", detail: "Billed yearly" },
    },
    note: ({ checked, perDay, seconds, inputTokens, outputTokens }) =>
      `${perDay} dictations a workday, ${seconds} seconds each, with the one-Mac license. Speech: Parakeet or Groq Whisper Large v3 Turbo. Refinement: Apple Intelligence, LM Studio or Qwen 3.8 27B on Cerebras (${inputTokens} tokens in, ${outputTokens} out). List prices, ${checked}.`,
    checked: monthYear("en-US"),
    questions: "Questions",
    faq: {
      subscription: [
        "Is it a subscription?",
        [
          "No. A license is a one-time purchase and doesn’t expire. Updates to the version you buy are included.",
        ],
      ],
      licenses: [
        "What’s the difference between the licenses?",
        [
          "Only how many Macs can use it at once. To move a license, deactivate the old Mac.",
        ],
      ],
      trial: [
        "Can I try it first?",
        [
          "Yes. The app has a 14-day trial with every feature, starting when you choose, not when you install.",
        ],
      ],
      trialNotOnSale: [
        "Can I try it first?",
        [
          "Once the official app is on sale, it includes a 14-day trial with every feature, starting when you choose, not when you install. It isn’t on sale yet, so there is no trial to download; the free source build has every feature now.",
        ],
      ],
      editions: [
        "What do both editions include?",
        [
          "The same app: dictation into any app, Transcribe (record app audio and your microphone or import audio and video, with optional speaker labels, summaries and TXT, JSON, SRT or VTT export), profiles, vocabulary and history. The official app adds no features; it saves building with Xcode. See the ",
          { link: "meetingGuide", text: "meeting guide" },
          ".",
        ],
      ],
      providers: [
        "What do cloud providers cost?",
        [
          "They bill you directly, per use, with your own API key kept in the Keychain. Local models are free; see ",
          { link: "offlineGuide", text: "which one fits your language" },
          " and ",
          { link: "mixedGuide", text: "mixed Chinese and English" },
          ". Claude Code and Codex use your existing subscription; see ",
          { link: "agentGuide", text: "dictating into coding agents" },
          ".",
        ],
      ],
      compare: [
        "How does it compare with other apps?",
        [
          "See the dated ",
          {
            link: "comparison",
            text: "comparison with VoiceInk, Handy, Typeless and Apple Dictation",
          },
          ", including where they are better.",
        ],
      ],
    },
  },
};
