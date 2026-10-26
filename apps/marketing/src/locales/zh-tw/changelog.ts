import type { ChangelogText } from "../../data/changelog";

// TRANSLATE: placeholder English copy; translate every title and description.
// One entry per release id in src/data/changelog.ts, with the same number of
// changes in the same order.
export const changelog: ChangelogText = {
  "0-14-0": {
    title: "Spanish, Japanese and better defaults in every language",
    changes: [
      {
        title: "Use Airdraft in Spanish or Japanese",
        description:
          "The interface, native menus and App Shortcut phrases are available in Spanish and Japanese, following your Mac's language. Shortcut instructions are written as whole sentences in each language, and controls widen to fit longer labels.",
      },
      {
        title: "Defaults that fit your language",
        description:
          "A new setup on a Mac without Chinese no longer starts with Traditional Chinese script or a Taiwanese Apple Speech locale; the Chinese script setting applies only to Mandarin and Cantonese and appears only there. Live preview lists every language your Mac supports.",
      },
      {
        title: "Recommended local models for seven more languages",
        description:
          "First-run setup and Models recommend from Airdraft's own measurement in Spanish, French, Portuguese, Russian, Arabic, Hindi and Indonesian: Qwen3-ASR 1.7B, with lighter choices on Macs with 8 GB of memory or less (Parakeet TDT v3, GigaAM v3 or Whisper Large v3 Turbo, by language).",
      },
      {
        title: "Refinement keeps your language",
        description:
          "Refinement is discarded for the raw transcript when it changes the language you spoke, in any script. Thai, Lao, Khmer and Burmese dictations are no longer skipped as too short, and setup no longer offers Apple Intelligence for a language it cannot write.",
      },
    ],
  },
  "0-13-0": {
    title: "Optional anonymous usage data and crash reports",
    changes: [
      {
        title: "Choose whether to share anonymous usage data",
        description:
          "Downloads from airdraft.app ask once whether to share anonymous usage counts and crash reports, listing what is shared and what never is. Nothing is sent before you choose, Settings > Behavior turns it off at any time, and builds from source never send anything. Your words, transcripts, audio, vocabulary, app names, window titles, URLs, file paths and keys are never sent.",
      },
      {
        title: "Live text from Apple Speech as the selected model",
        description:
          "When Apple Speech is your speech model and Live preview uses the selected model, live text now appears in the recording window and during meetings.",
      },
    ],
  },
  "0-12-1": {
    title: "Steadier insertion on busy Macs",
    changes: [
      {
        title: "Confirm the destination more reliably",
        description:
          "Before recording, Airdraft checks that the text field and cursor have stopped changing. It now also reads them twice in a row, so a slow or busy Mac cannot accept a field that is still moving and later report that the destination changed.",
      },
    ],
  },
  "0-12-0": {
    title: "Profiles by app, live text and Simplified Chinese",
    changes: [
      {
        title: "Choose a profile for each app",
        description:
          "Profiles > Profile by app maps an app, or a family such as code editors, terminals, email, chat or documents, to one of your profiles. It is off by default, and Home names a rule whose profile still needs setup.",
      },
      {
        title: "See live text from your local model",
        description:
          "Live preview can use the selected speech model (Parakeet, SenseVoice or Orukeet) as well as Apple Speech, in the recording window and while recording a meeting. The final transcript is unchanged.",
      },
      {
        title: "Use Airdraft in Simplified Chinese",
        description:
          "The interface, native menus and App Shortcut phrases are available in Simplified Chinese. A new setup on a Mac set to Simplified Chinese starts with Simplified script.",
      },
      {
        title: "A better first model for English, Japanese and Korean",
        description:
          "First-run setup recommends Parakeet TDT v2 for English and Qwen3-ASR 1.7B for Japanese and Korean, based on Airdraft's own measurement. SenseVoice now installs the original multilingual model; the Cantonese fine-tune that 0.11.0 and earlier installed keeps working as SenseVoice Cantonese.",
      },
      {
        title: "Your vocabulary helps on-device recognition",
        description:
          "Qwen3-ASR, Parakeet and Orukeet use the spellings in Vocabulary while they recognize speech. Settings > Behavior turns this off.",
      },
      {
        title: "Cleaner local transcripts",
        description:
          "Repeated loops are cut, a wrongly detected language is retried, and SenseVoice and FireRedASR2 write English in normal case with punctuation. Japanese kanji are no longer converted to Chinese script, and refinement that turns Japanese or Korean into Chinese falls back to your transcript.",
      },
      {
        title: "Meetings remember speaker names",
        description:
          "Speaker names you type are suggested in later meetings, and Summarize offers Brief Summary, Action Items, Decisions & Follow-ups and Meeting Minutes.",
      },
      {
        title: "A simpler Models page",
        description:
          "Models opens with the recommendation for your language and a few alternatives, with Show All Models for the full list and full language names on every row.",
      },
      {
        title: "Paste into Ghostty 1.3 without an error",
        description:
          "Ghostty 1.3 shows a text cursor to Airdraft, which made every paste report that it couldn't be confirmed. It now gets one paste and no notice, like other terminals that draw their own text.",
      },
      {
        title: "Lighter on memory",
        description:
          "When macOS reports memory pressure, idle local speech models and the LM Studio models Airdraft loaded are unloaded. A dictation in progress keeps its model.",
      },
    ],
  },
  "0-11-0": {
    title: "Traditional Chinese interface and dependable delivery",
    changes: [
      {
        title: "Use Airdraft in Traditional Chinese",
        description:
          "The interface, native menus and App Shortcut phrases are available in Traditional Chinese (Taiwan) and follow the macOS language setting. Built-in profile names appear in the interface language until you rename them.",
      },
      {
        title: "Dictate again right after a paste",
        description:
          "A shortcut pressed while the clipboard was being restored or History was saving could be ignored. Airdraft is now ready as soon as delivery is confirmed, and a newer paste never brings back an older clipboard.",
      },
      {
        title: "Paste into terminals that draw their own text",
        description:
          "Warp, Zed, Ghostty, kitty, Alacritty and WezTerm get one paste without an error, and History marks it Pasted, unconfirmed. Your clipboard returns after two seconds. Other apps without a visible cursor still keep the text on the clipboard with a recovery notice.",
      },
      {
        title: "Keep dictating while recordings wait",
        description:
          "A recording kept after a speech failure no longer blocks new dictation. Up to three recordings or 15 minutes of audio wait for retry or discard; when little room remains, the next recording stops early and says why.",
      },
      {
        title: "Clearer setup on Home and in onboarding",
        description:
          "Home counts an installed speech model as ready even before it loads, and names trial, license and kept-recording blockers. Try It now completes with a real dictation, and Ready offers Apple Intelligence refinement when the Mac supports it.",
      },
      {
        title: "Recommended and verified local models",
        description:
          "A Mac set to Chinese is recommended Qwen3-ASR 1.7B, or SenseVoice first with 8 GB of memory or less. Models opens with that recommendation and verified models, with the rest under Experimental. Qwen3-ASR and Whisper downloads are pinned and checked by size and SHA-256 before installation.",
      },
      {
        title: "Adjust text size",
        description:
          "Settings > Appearance > Text size offers Default, Large and Larger, and text wraps instead of clipping at larger sizes. Every control now has a VoiceOver name and state.",
      },
      {
        title: "Start and save dictations faster",
        description:
          "The microphone opens as soon as setup checks pass, refinement prepares while you speak, and saving a dictation no longer scans stored audio. A long recording keeps its local speech model loaded until processing ends.",
      },
      {
        title: "Build Airdraft from source more easily",
        description:
          "Settings > Updates > Acknowledgements lists third-party notices, and source builds now launch without the project's signing team.",
      },
    ],
  },
  "0-10-2": {
    title: "Add AssemblyAI Universal-3.6 Pro preview",
    changes: [
      {
        title: "Choose the 3.6 Pro batch preview",
        description:
          "Models and Profiles now offer Universal-3.6 Pro (Preview) through AssemblyAI's pre-recorded preview API. Universal-3.5 Pro remains available and keeps its saved selections. Preview availability and transcription quality still need verification with an AssemblyAI account.",
      },
      {
        title: "Keep the selected speech model on the request",
        description:
          "AssemblyAI requests use the model you choose. Preview failures do not retry with 3.5 Pro, and a response that reports a different model version is rejected instead of being recorded as a successful 3.6 Pro transcription.",
      },
    ],
  },
  "0-10-1": {
    title: "Recover stalled models and add Disco colors",
    changes: [
      {
        title: "Switch away from a stalled speech model",
        description:
          "Model loading now has a two-minute limit. Cancelling or changing models frees the next selection while unfinished native work cleans up safely. A model still cleaning up stays protected from duplicate loading and deletion.",
      },
      {
        title: "Make recording colors respond to speech",
        description:
          "The saved Disco switch adds flowing colors to Classic, Cube, Sonic, Orbit and Silk. Voice energy and syllable accents shape the palette, which settles during pauses and freezes during delivery. Reduce Motion keeps the colors still.",
      },
    ],
  },
  "0-10-0": {
    title: "More local speech models and guided setup",
    changes: [
      {
        title: "Animated recording-window choices",
        description:
          "Mini is now Classic, with an animated Settings preview and the same capsule size as the other styles. Larger preview tiles show all five styles, including Orbit’s interlocking silver rings and Silk’s folded metallic ribbon.",
      },
      {
        title: "More on-device speech models",
        description:
          "The local catalogue adds Whisper Large v3, compressed Turbo, pinned GGUF and Core ML choices, Distil-Whisper and Orukeet. Models, Profiles and Meetings share the exact model selection, language limits and download checks.",
      },
      {
        title: "Learn dictation step by step",
        description:
          "Six optional setup steps guide you through choosing speech, permissions, shortcut practice and your first dictation. Model downloads continue between steps, and shortcut rehearsal pauses recording.",
      },
      {
        title: "Clearer meetings and consistent controls",
        description:
          "Meeting cards keep the next action beside a compact player. Transcript editing has fixed header and footer actions, while buttons, pickers and text fields share one rounded shape.",
      },
    ],
  },
  "0-9-1": {
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
  },
  "0-9-0": {
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
  },
  "0-8-1": {
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
  },
  "0-8-0": {
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
  },
  "0-7-0": {
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
  },
  "0-6-2": {
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
  },
  "0-6-1": {
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
  },
  "0-6-0": {
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
  },
  "0-5-1": {
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
  },
  "0-5-0": {
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
  },
  "0-4-6": {
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
  },
  "0-4-5": {
    title: "Support editors without an exposed caret",
    changes: [
      {
        title: "Paste through the focused app",
        description:
          "Editors that do not expose an accessible text caret can use the app-window paste path, while changed destinations still trigger recovery.",
      },
    ],
  },
  "0-4-4": {
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
  },
  "0-4-3": {
    title: "Follow you between apps",
    changes: [
      {
        title: "Wait for the destination to settle",
        description:
          "Airdraft waits for the selected app, text field and caret when an app switch is in progress. Transient focus reads can settle before delivery.",
      },
    ],
  },
  "0-4-2": {
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
  },
  "0-4-1": {
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
  },
  "0-4-0": {
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
  },
  "0-3-0": {
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
  },
  "0-2-0": {
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
  },
  "0-1-9": {
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
  },
  "0-1-8": {
    title: "Make writing profiles your own",
    changes: [
      {
        title: "Edit, duplicate and reset",
        description:
          "Profiles gain an open editor, inline renaming and duplication, including Verbatim behavior. Shared rules offer Save, Cancel and Restore Defaults.",
      },
    ],
  },
  "0-1-7": {
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
  },
  "0-1-6": {
    title: "More refinement providers",
    changes: [
      {
        title: "Use Cerebras or Groq",
        description:
          "Choose Cerebras or Groq for text refinement independently of your speech-recognition provider.",
      },
    ],
  },
  "0-1-5": {
    title: "A stable identity for updates",
    changes: [
      {
        title: "Keep signing consistent",
        description:
          "Certificate-signed releases replace the earlier ad-hoc identity. The update process checks signing continuity; upgrading from older builds may require granting permissions again.",
      },
    ],
  },
  "0-1-4": {
    title: "Recover microphone interruptions",
    changes: [
      {
        title: "Resume a disrupted input",
        description:
          "Microphone capture recovers from input interruptions, alongside more consistent spacing across settings.",
      },
    ],
  },
  "0-1-3": {
    title: "Separate development and installed apps",
    changes: [
      {
        title: "Recognize the right app",
        description:
          "Development and installed builds use separate identities, with refreshed permission state so access checks apply to the intended app.",
      },
    ],
  },
  "0-1-2": {
    title: "Respect the system microphone",
    changes: [
      {
        title: "Preserve the selected route",
        description:
          "Capture keeps the system microphone route instead of unexpectedly replacing the input you chose.",
      },
    ],
  },
  "0-1-1": {
    title: "The first packaged builds",
    changes: [
      {
        title: "Remember your microphone choice",
        description:
          "Microphone defaults become part of setup, and locally built releases arrive as a DMG with a signed Sparkle update feed.",
      },
    ],
  },
  "initial-source": {
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
  },
};
