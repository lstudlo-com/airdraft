export interface ChangelogEntry {
  id: string;
  date: string;
  version?: string;
  title: string;
  changes: { title: string; description: string }[];
  source: { label: string; url: string };
}

// Newest first, one entry per product version. Rebuilds share an entry.
// Publication dates: GitHub Releases, in Asia/Taipei, checked 2026-10-08.
// Descriptions: published notes and commits between the corresponding tags.
// These are personal-use Apple Development builds, not notarized distribution.
// Keep summaries out of this schema: release title, then described change items.
export const changelog: ChangelogEntry[] = [
  {
    id: "0-9-1",
    version: "0.9.1",
    date: "2026-10-08",
    title: "Fix meeting audio and controls",
    changes: [
      {
        title: "Read and choose meeting apps",
        description:
          "The app chooser now gives each app a full-height row, grows as sources load and scrolls longer lists. Refresh, empty states and errors remain visible.",
      },
      {
        title: "Hear new recordings in both channels",
        description:
          "New and recovered meetings mix microphone and app audio into identical left and right channels. Previously saved files stay unchanged. Meeting meters now use the same linear response and ten-cell display as the microphone picker.",
      },
      {
        title: "Keep primary controls consistent",
        description:
          "Recording, transcription and transcript-save actions use blue raised capsules with the same pressed and disabled states as Airdraft’s other neumorphic buttons.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.9.1-build.203",
    },
  },
  {
    id: "0-9-0",
    version: "0.9.0",
    date: "2026-10-08",
    title: "A dedicated home for meetings",
    changes: [
      {
        title: "Find every meeting and transcript",
        description:
          "Meetings now has its own sidebar page. Each recording has a direct transcription action, saved transcript versions, recovery controls, Finder access and audio export. History stays focused on dictation.",
      },
      {
        title: "Choose more local transcription models",
        description:
          "Speaker-labelled media transcription supports eight local model choices, including both Qwen3-ASR sizes, Cohere, SenseVoice, FireRed, Parakeet and Apple Speech alongside Whisper Turbo. Additional engines show segment timestamps; Whisper retains word timestamps.",
      },
      {
        title: "Start recording with fewer steps",
        description:
          "A compact meeting sheet lets you select app audio and include your microphone. The app chooser opens immediately, and saved recordings stay visible after restarting. Models now appears above Settings, the new name for Configuration.",
      },
      {
        title: "More cloud speech choices and clearer recovery",
        description:
          "Native speech integrations add AssemblyAI, Cartesia, Speechmatics, xAI, Mistral and Gemini. Blocked data and recovery screens now allow normal quitting while active cleanup remains protected.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.9.0-build.202",
    },
  },
  {
    id: "0-8-1",
    version: "0.8.1",
    date: "2026-10-07",
    title: "Recover text when a paste cannot be confirmed",
    changes: [
      {
        title: "Keep unconfirmed text available",
        description:
          "Airdraft now checks the destination text before reporting a successful paste. If an editor ignores the paste or cannot expose its text, your transcript stays on the clipboard and a recovery notice appears. Check the destination before pasting again; Airdraft never retries an uncertain paste automatically.",
      },
      {
        title: "Preserve recovery details in History",
        description:
          "History saves the transcript and delivery diagnostic when a paste cannot be confirmed, including after successful refinement. If another app changes the clipboard, its newer content is preserved and the notice points you to History.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.8.1-build.197",
    },
  },
  {
    id: "0-8-0",
    version: "0.8.0",
    date: "2026-10-07",
    title: "Recordings, meeting capture and configuration search",
    changes: [
      {
        title: "Keep audio independently of transcripts",
        description:
          "Browse and export recordings, import media, edit speaker transcripts and capture meeting audio. Saved audio remains available for transcription and recovery, with separate cleanup controls for recordings and text.",
      },
      {
        title: "Find settings and choose your recording window",
        description:
          "Search Configuration by setting name or description. Choose Mini, Cube or Sonic recording windows, enable an optional timer, and select separate light and dark app icons.",
      },
      {
        title: "Protect privacy and interrupted work",
        description:
          "Provider redirect checks, browser context boundaries and interrupted cleanup recovery are stricter. Shared busy-state checks protect active operations, while History scrolling and recovery notices receive reliability fixes.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.8.0-build.194",
    },
  },
  {
    id: "0-7-0",
    version: "0.7.0",
    date: "2026-10-06",
    title: "Hold to start with Trigger Delay",
    changes: [
      {
        title: "Prevent accidental dictation",
        description:
          "Set Trigger Delay from 0 to 1000 ms in Configuration. Short presses keep the shortcut key’s normal action; holding past the delay starts dictation. The default is off, and stopping stays immediate.",
      },
      {
        title: "Keep recordings within ten minutes",
        description:
          "The recording limit now ranges from 10 seconds to 10 minutes. Longer saved limits are reduced to ten minutes, while shorter choices and the five-minute default are preserved. Imported audio keeps its separate limits.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.7.0-build.175",
    },
  },
  {
    id: "0-6-2",
    version: "0.6.2",
    date: "2026-10-05",
    title: "Speech languages follow each model",
    changes: [
      {
        title: "Choose a supported language",
        description:
          "Language choices now follow the active speech model, including profile overrides. Unsupported combinations stop before recording with an explanation. Parakeet does not support Chinese.",
      },
      {
        title: "Set the language for Cohere",
        description:
          "The local Cohere Transcribe model now requires a language choice. Auto Detect is unavailable in this runtime because it can turn Chinese speech into incorrect English output.",
      },
      {
        title: "Apply language choices consistently",
        description:
          "SenseVoice receives the chosen language, Qwen uses the expected language names, and Apple Speech shows available system locales. Switching models preserves your shared preference.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.6.2-build.169",
    },
  },
  {
    id: "0-6-1",
    version: "0.6.1",
    date: "2026-10-05",
    title: "App context is now opt-in",
    changes: [
      {
        title: "Choose when to share app context",
        description:
          "Read app context now defaults to off when no preference is saved. Existing choices are preserved, and cursor insertion continues to work independently.",
      },
      {
        title: "A neutral app icon",
        description:
          "The app icon now uses the same neutral grays, raised waveform and graphite caret as the app window.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.6.1-build.157",
    },
  },
  {
    id: "0-6-0",
    version: "0.6.0",
    date: "2026-10-04",
    title: "A speech model for every profile",
    changes: [
      {
        title: "Choose speech per profile",
        description:
          "Bind a speech model to a writing profile, or keep using the app default. Switching profiles applies that choice to the next recording.",
      },
      {
        title: "Read a dictation from Home",
        description:
          "Click a waveform bar to open its transcript. Expand long text, copy it, or switch to another dictation without leaving Home.",
      },
      {
        title: "Find models more easily",
        description:
          "Browse speech models by provider, with brand icons and hosting labels. Browsing a filter leaves your active model unchanged.",
      },
      {
        title: "Clearer progress and controls",
        description:
          "Download bars and percentages move together. Shorter page headers leave more room for content, and the menu groups model controls and recovery actions.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.6.0-build.139",
    },
  },
  {
    id: "0-5-1",
    version: "0.5.1",
    date: "2026-10-03",
    title: "Models ready when you are",
    changes: [
      {
        title: "Start after an idle break",
        description:
          "Beginning a dictation reloads an installed speech model automatically. Idle unloading defaults to 30 minutes, with 5, 10, 30 minutes and Never available.",
      },
      {
        title: "Watch real download progress",
        description:
          "Model downloads report incoming bytes throughout each file. Preparing and unpacking show activity instead of an invented percentage.",
      },
      {
        title: "Messages leave on their own",
        description:
          "Errors, recovery notices and confirmations stay for five seconds, then fade. Recovery details remain available on Home and in History where applicable.",
      },
      {
        title: "A more precise sidebar",
        description:
          "A raised icon follows the sliding selection well. The microphone button, page toggle and card shadows keep consistent placement and depth.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.5.1-build.130",
    },
  },
  {
    id: "0-5-0",
    version: "0.5.0",
    date: "2026-10-02",
    title: "The app takes a new shape",
    changes: [
      {
        title: "One material across the window",
        description:
          "Rounded page islands, raised cards and controls, recessed selections and a neutral Home waveform share the same light and shadow in both appearances.",
      },
      {
        title: "Navigation moves with you",
        description:
          "The selected sidebar well slides between pages. The carved brand mark and opaque window chrome complete the new interface.",
      },
      {
        title: "Keep English in English",
        description:
          "Chinese script hints are sent only when Chinese is selected, avoiding unwanted translation during automatic speech-language detection.",
      },
      {
        title: "Quieter clipboard confirmations",
        description:
          "Clipboard confirmations dismiss automatically. The following 0.5.1 release extends timed dismissal to all HUD messages.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.5.0-build.119",
    },
  },
  {
    id: "0-4-6",
    version: "0.4.6",
    date: "2026-10-01",
    title: "Keep the words you just said",
    changes: [
      {
        title: "Keep past dictations out of new ones",
        description:
          "Refinement separates context from the current transcript and checks fidelity to reduce reused sentences and unintended translation.",
      },
      {
        title: "A compact menu and clearer selection",
        description:
          "Long dynamic menu titles fit within the menu width, while the active sidebar destination sits in a deeper recessed well.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.4.6-build.100",
    },
  },
  {
    id: "0-4-5",
    version: "0.4.5",
    date: "2026-10-01",
    title: "Support editors without an exposed caret",
    changes: [
      {
        title: "Paste through the focused app",
        description:
          "Editors that do not expose an accessible text caret can use the app-window paste path, while changed destinations still trigger recovery.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.4.5-build.95",
    },
  },
  {
    id: "0-4-4",
    version: "0.4.4",
    date: "2026-10-01",
    title: "Read the whole error",
    changes: [
      {
        title: "Make room for diagnostics",
        description:
          "The recording capsule expands to show complete error and recovery messages. Oversized messages scroll within the screen.",
      },
      {
        title: "Copy the full message",
        description:
          "A trailing Copy Message action copies the diagnostic without taking focus from the app you were using.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.4.4-build.93",
    },
  },
  {
    id: "0-4-3",
    version: "0.4.3",
    date: "2026-10-01",
    title: "Follow you between apps",
    changes: [
      {
        title: "Wait for the destination to settle",
        description:
          "Airdraft waits for the selected app, text field and caret when an app switch is in progress. Transient focus reads can settle before delivery.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.4.3-build.91",
    },
  },
  {
    id: "0-4-2",
    version: "0.4.2",
    date: "2026-09-30",
    title: "A single, safer paste path",
    changes: [
      {
        title: "Avoid conflicting insertion attempts",
        description:
          "Text delivery uses one normal paste path instead of a speculative Accessibility write followed by paste.",
      },
      {
        title: "Preserve text during cancellation",
        description:
          "If cancellation happens after delivery begins, the dictated text remains on the clipboard long enough for the destination to read it.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.4.2-build.90",
    },
  },
  {
    id: "0-4-1",
    version: "0.4.1",
    date: "2026-09-30",
    title: "More reliable everyday dictation",
    changes: [
      {
        title: "Leave unselected iPhones disconnected",
        description:
          "Opening the microphone picker previews a Continuity microphone only when it is selected, including through System Default.",
      },
      {
        title: "Follow History with accessibility",
        description:
          "Visible timestamps follow timeline navigation, and offscreen entries leave the accessibility representation when you return to the top.",
      },
      {
        title: "Recover focus and provider failures",
        description:
          "Insertion waits for editor focus and selection. Claude failures preserve the original transcript with an actionable diagnostic; the License sheet uses fewer controls.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.4.1-build.86",
    },
  },
  {
    id: "0-4-0",
    version: "0.4.0",
    date: "2026-09-30",
    title: "A guided first dictation",
    changes: [
      {
        title: "Set up by doing",
        description:
          "Optional onboarding walks through permissions and speech setup, then lets you try a real dictation.",
      },
      {
        title: "Trial and activate the official build",
        description:
          "Official builds add a user-started, full-feature 14-day trial and license activation. Self-built editions remain fully unlocked.",
      },
      {
        title: "Keep long text inside History",
        description:
          "Long transcripts and text selections stay within their cards. The recording capsule fits its label and fades after successful delivery.",
      },
      {
        title: "An explicit open-source license",
        description:
          "The repository adopts GPL-3.0-only, with the license linked from the website.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.4.0-build.79",
    },
  },
  {
    id: "0-3-0",
    version: "0.3.0",
    date: "2026-09-28",
    title: "Local intelligence, replay and automation",
    changes: [
      {
        title: "Refine with Apple Intelligence",
        description:
          "On supported Macs running macOS 26 or later, an on-device Foundation Models session cleans up each dictation. Unavailable or failed refinement preserves the raw transcript.",
      },
      {
        title: "More ways to hear and review speech",
        description:
          "Parakeet TDT v3 joins local speech recognition. Optional live transcription previews show provisional words while recording.",
      },
      {
        title: "Save and replay audio",
        description:
          "Opt in to retaining dictation audio, replay it from History, and retry transcription from the saved recording.",
      },
      {
        title: "Connect dictation to your workflow",
        description:
          "Start and stop through Shortcuts, and send delivered text to a configured script.",
      },
      {
        title: "Better text fidelity and History",
        description:
          "Refinement corrects terms while preserving literal text. History bounds work during scrolling, adds calendar dates to its timeline, and gains progressive header blur.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.3.0-build.65",
    },
  },
  {
    id: "0-2-0",
    version: "0.2.0",
    date: "2026-09-26",
    title: "New speech controls and a refreshed interface",
    changes: [
      {
        title: "Check your connection",
        description:
          "Test API access for Soniox, Groq, ElevenLabs, OpenAI and Deepgram before you dictate. OpenRouter adds model and provider controls.",
      },
      {
        title: "Compare supported speech models",
        description:
          "Browse provider models with pricing and available quality and speed information linked to official documentation. Unpublished metrics stay marked.",
      },
      {
        title: "A refreshed native interface",
        description:
          "A collapsible sidebar, live microphone meters and a scrolling History timeline join consistent settings and model lists.",
      },
      {
        title: "Recover interrupted work",
        description:
          "Recording prerequisites are checked before capture. Failed speech audio stays available to retry or discard, and refinement errors preserve the raw transcript.",
      },
      {
        title: "A version for the feature release",
        description:
          "This release carries the same feature set as 0.1.9 build 44 under a new minor version. Its installer uses Apple Development signing and is not notarized.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.2.0-build.46",
    },
  },
  {
    id: "0-1-9",
    version: "0.1.9",
    date: "2026-09-26",
    title: "Desktop controls take shape",
    changes: [
      {
        title: "Choose and preview a microphone",
        description:
          "The microphone overlay adds a live input-level preview. Sidebar and profile controls become more compact across this series of builds.",
      },
      {
        title: "Edit the shared refinement rules",
        description:
          "Base prompt editing joins profile customization, so shared instructions can be saved or restored.",
      },
      {
        title: "A website and branded installer",
        description:
          "The Astro website and a custom drag-to-Applications disk image join the project. Later builds in this series lead into the 0.2.0 feature release.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.1.9-build.44",
    },
  },
  {
    id: "0-1-8",
    version: "0.1.8",
    date: "2026-09-23",
    title: "Make writing profiles your own",
    changes: [
      {
        title: "Edit, duplicate and reset",
        description:
          "Profiles gain an open editor, inline renaming and duplication, including Verbatim behavior. Shared rules offer Save, Cancel and Restore Defaults.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.1.8-build.12",
    },
  },
  {
    id: "0-1-7",
    version: "0.1.7",
    date: "2026-09-23",
    title: "Fewer interruptions during setup",
    changes: [
      {
        title: "Ask for key access deliberately",
        description:
          "Page navigation and background checks stop requesting Keychain approval. Protected keys get an explicit access action, and denied reads preserve saved credentials.",
      },
      {
        title: "Capture the selected input channel",
        description:
          "Microphone capture uses the chosen channel. Releasing the shortcut while permission is pending prevents a delayed recording from starting.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.1.7-build.10",
    },
  },
  {
    id: "0-1-6",
    version: "0.1.6",
    date: "2026-09-22",
    title: "More refinement providers",
    changes: [
      {
        title: "Use Cerebras or Groq",
        description:
          "Choose Cerebras or Groq for text refinement independently of your speech-recognition provider.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.1.6-build.8",
    },
  },
  {
    id: "0-1-5",
    version: "0.1.5",
    date: "2026-09-21",
    title: "A stable identity for updates",
    changes: [
      {
        title: "Keep signing consistent",
        description:
          "Certificate-signed releases replace the earlier ad-hoc identity. The update process checks signing continuity; upgrading from older builds may require granting permissions again.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.1.5-build.7",
    },
  },
  {
    id: "0-1-4",
    version: "0.1.4",
    date: "2026-09-21",
    title: "Recover microphone interruptions",
    changes: [
      {
        title: "Resume a disrupted input",
        description:
          "Microphone capture recovers from input interruptions, alongside more consistent spacing across settings.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.1.4-build.6",
    },
  },
  {
    id: "0-1-3",
    version: "0.1.3",
    date: "2026-09-21",
    title: "Separate development and installed apps",
    changes: [
      {
        title: "Recognize the right app",
        description:
          "Development and installed builds use separate identities, with refreshed permission state so access checks apply to the intended app.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.1.3-build.5",
    },
  },
  {
    id: "0-1-2",
    version: "0.1.2",
    date: "2026-09-21",
    title: "Respect the system microphone",
    changes: [
      {
        title: "Preserve the selected route",
        description:
          "Capture keeps the system microphone route instead of unexpectedly replacing the input you chose.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.1.2-build.4",
    },
  },
  {
    id: "0-1-1",
    version: "0.1.1",
    date: "2026-09-21",
    title: "The first packaged builds",
    changes: [
      {
        title: "Remember your microphone choice",
        description:
          "Microphone defaults become part of setup, and locally built releases arrive as a DMG with a signed Sparkle update feed.",
      },
    ],
    source: {
      label: "Release notes",
      url: "https://github.com/lstudlo-com/airdraft/releases/tag/v0.1.1-build.3",
    },
  },
  {
    id: "initial-source",
    date: "2026-09-18",
    title: "Airdraft is on GitHub",
    changes: [
      {
        title: "Speak into the app you use",
        description:
          "Hold a shortcut, speak and release to insert text at the cursor. Airdraft stays in the menu bar between recordings.",
      },
      {
        title: "Choose each step independently",
        description:
          "Use local or cloud speech recognition and choose refinement separately. Editable writing profiles, vocabulary corrections and local History are part of the source build.",
      },
    ],
    source: {
      label: "Initial source",
      url: "https://github.com/lstudlo-com/airdraft/commit/16a392ed2dd2d4d7ec4a86eb23d5be74ae0bb31c",
    },
  },
];
