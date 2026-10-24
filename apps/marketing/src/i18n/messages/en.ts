import { monthYear } from "./format";
import type { Messages } from "./types";

export const en: Messages = {
  gap: " ",
  english: "",
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
    homeOnly: "home page",
  },
  footer: {
    nav: "Footer",
    build: "Build instructions",
    pricing: "Pricing",
    guides: "Guides",
    support: "Support",
    donate: "Donate",
    changelog: "Changelog",
    rss: "RSS",
    privacy: "Privacy",
    license: "License",
    languages: "Languages",
  },
  analytics: {
    title: "Optional website analytics",
    body: "Help us understand visits and which features interest people. No recordings or typed text.",
    privacy: "Privacy details",
    decline: "Decline",
    allow: "Allow Analytics",
  },
  home: {
    headline: [
      "Speak in your language,",
      "English terms and all.",
      "Transcribe your meetings.",
    ],
    headlineGap: " ",
    get: "Get Airdraft",
    source: "View source",
    sample: "Try the sample",
    facts: [
      "Open source",
      "On your Mac, or with your own provider",
      "macOS 15+ on Apple silicon",
    ],
    guidesTitle: "Choose your dictation setup",
    guidesIntro:
      "Set up offline dictation in your language, mix Chinese and English, dictate prompts into Claude Code and terminals, choose local or cloud, or transcribe meetings.",
    featuresTitle: "What Airdraft handles for you",
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
      profiles: ["Profiles", "Four built in. Rewrite any of them."],
      vocabulary: ["Your vocabulary", "Teach it names and jargon once."],
      history: ["History", "Search it, flip to the original, copy."],
      fallback: ["Nothing is lost", "If cleanup fails, the raw text goes in."],
      privacy: [
        "Stays on your Mac",
        "With local models, nothing leaves. Keys live in the Keychain.",
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
    title: "Meetings, transcribed on your Mac",
    intro:
      "Record a call or import a file, then turn it into a transcript with speakers.",
    sample: "Sample meeting transcript",
    meeting: "Design review",
    meta: "Oct 21 · 32:14 · Whisper Large v3 Turbo",
    turns: [
      [1, "0:12", "Let’s ship the onboarding changes on Thursday."],
      [2, "0:31", "Then I’ll update the screenshots before the release."],
    ],
    points: [
      [
        "Record any app",
        "One app or all app audio, plus your microphone. No screen video is kept.",
      ],
      [
        "Or import a file",
        "Audio or video up to two hours, with one audio track.",
      ],
      [
        "Speakers, estimated locally",
        "Optional speaker labels you can rename and reassign.",
      ],
      [
        "Local unless you choose cloud",
        "A local model keeps the audio here; Soniox uploads only after you confirm.",
      ],
      [
        "Edit, then export",
        "Keep the original beside your edits. Export TXT, JSON, SRT or VTT.",
      ],
    ],
    guide: "Read the Meeting Guide",
  },
  interface: {
    title: "An interface you’ll love to open",
    intro: "Raised keys, pressed wells and carved grooves, in light and dark.",
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
    keysLabel: "Control Option",
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
    intro:
      "Speech and refinement run separately. Pick local or cloud for each.",
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
      "Your vocabulary fixes names last. Then the text goes into the app you’re typing in.",
    fix: ["Meet me in", "at nine."],
  },
  get: {
    title: "Get Airdraft",
    intro:
      "Free to build from source, or a one-time license for the ready-to-run app.",
    notOnSale: "The official app isn’t on sale yet.",
    build: "Build it yourself",
    free: "Free",
    note: "Every feature. Needs Xcode on an Apple silicon Mac.",
    action: "Build instructions",
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
  guideLinks: { read: "Read Guide", readLabel: "Read guide: " },
  pricing: {
    title: "Pricing — Airdraft",
    description:
      "Airdraft is free to build from source. The ready-to-run app is a one-time license: $29 for one Mac or $49 for up to three.",
    heading: "Pricing",
    intro: "Build it free, or buy the ready-to-run app once.",
    source: "Open source",
    build: "Build it yourself",
    buildAction: "Build instructions",
    sourceList: "The source build includes",
    sourceIncludes: [
      "Dictation and Meetings",
      "Every feature, no locks",
      "Needs Xcode to build",
    ],
    app: "Ready-to-run app",
    once: "one-time",
    buy: (macs) => `Buy for ${macs}`,
    notOnSale: "Not on sale yet",
    appList: "Every license includes",
    licenseIncludes: [
      "Dictation and Meetings",
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
          "Once the official app is on sale, it includes a 14-day trial with every feature, starting when you choose, not when you install. It isn’t on sale yet, so there is no trial to download today. The free source build has every feature now.",
        ],
      ],
      editions: [
        "What do both editions include?",
        [
          "The same app: dictation into any app, Meetings (record app audio and your microphone or import audio and video, with optional speaker labels and TXT, JSON, SRT or VTT export), profiles, vocabulary and history. The official app adds no features; it saves building with Xcode. See the ",
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
