// "Hold, speak, let go" (DictationPreview.astro): one authored dictation told
// in three steps. The whole story is one timeline in milliseconds of "story
// time" and one renderer that draws any moment of it, so the same frames
// serve every way of moving through it:
//
//   scroll   on wide windows with room for it the scene pins (.is-pinned)
//            and the scroll position picks the moment: step 1 listens while
//            the words light up, step 2 lets go (transcribing, then refining
//            strikes the fillers), step 3 types the result at the caret.
//            Scrolling back runs it backwards. Words only "sound" (the pill's
//            meter moves) while the scroll moves.
//   time     phones, short windows and replays play it in real time: once
//            when the scene is first near the middle of the window, then on
//            Run, a profile (which re-runs only the refinement), or a hold of
//            ⌃⌥ while the pointer or focus is on the scene, or a press and
//            hold of its keycaps or the "What you said" well. A replay takes
//            over from the scroll until the visitor scrolls on.
//
// Nothing is recorded. The visually hidden status line speaks each state;
// the result is busy while it types. Reduced motion never pins, plays or
// scrubs: every control shows the finished frame at once. Without
// JavaScript the Clean result rests in place.
import { captureWebsiteEvent } from "./analytics";

type Profile = "clean" | "concise" | "summary";
type State = "idle" | "listening" | "decoding" | "refining" | "typing" | "done";

// English defaults; DictationPreview.astro supplies each page's language.
const defaultExamples: Record<Profile, string> = {
  clean:
    "Hi Maya, I’ll send the draft tomorrow morning. Could we move our check-in to two?",
  concise:
    "Maya, I’ll send the draft tomorrow morning. Can we move our check-in to two?",
  summary:
    "Send Maya the draft tomorrow morning. Ask to move the check-in to two.",
};
const defaultLabels = {
  stop: "Stop",
  again: "Run again",
  run: "Run sample",
  placeholder: "The text appears here when you let go.",
  listening: "Listening…",
  transcribing: "Transcribing…",
  refining: "Refining…",
};

const parse = <T extends object>(raw: string | undefined, fallback: T): T => {
  try {
    return { ...fallback, ...JSON.parse(raw ?? "{}") };
  } catch {
    return fallback;
  }
};
const clamp = (value: number, low = 0, high = 1) =>
  Math.min(high, Math.max(low, value));

const root = document.querySelector<HTMLElement>("[data-preview]");
if (root) setup(root);

function setup(root: HTMLElement) {
  const examples = parse(root.dataset.examples, defaultExamples);
  const labels = parse(root.dataset.labels, defaultLabels);
  const find = <T extends Element>(selector: string) =>
    root.querySelector<T>(selector)!;
  const track = find<HTMLElement>("[data-sample-track]");
  const pin = find<HTMLElement>("[data-sample-pin]");
  const scene = find<HTMLElement>(".sample-scene");
  const said = find<HTMLElement>("[data-sample-said]");
  const play = find<HTMLButtonElement>("[data-play]");
  const playLabel = find<HTMLElement>("[data-play-label]");
  const picker = find<HTMLElement>("[data-profile-picker]");
  const spoken = find<HTMLElement>("[data-spoken]");
  const result = find<HTMLElement>("[data-result]");
  const status = find<HTMLElement>("[data-status]");
  const hudLabel = find<HTMLElement>("[data-hud-label]");
  // The HUD's states in the page's language (Hud.astro).
  const hud = find<HTMLElement>("[data-hud]").dataset;
  const bars = [...root.querySelectorAll<HTMLElement>(".hud-bars span")];
  const profiles = [
    ...picker.querySelectorAll<HTMLButtonElement>("[data-profile]"),
  ];
  const fillers = [...spoken.querySelectorAll<HTMLElement>(".filler")];
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const wide = matchMedia(
    "(min-width: 701px) and (prefers-reduced-motion: no-preference)",
  );

  // Wrap each spoken word so it can light up as it is "said". Filler phrases
  // stay one unit so their strike-through reads as a single correction.
  const words: HTMLElement[] = [];
  for (const node of [...spoken.childNodes]) {
    if (node instanceof HTMLElement) {
      node.classList.add("word");
      node.classList.remove("struck");
      words.push(node);
      continue;
    }
    const parts = (node.textContent ?? "").split(/(\s+)/);
    const fragment = document.createDocumentFragment();
    for (const part of parts) {
      if (!part.trim()) {
        if (part) fragment.append(" ");
        continue;
      }
      const word = document.createElement("span");
      word.className = "word";
      word.textContent = part;
      fragment.append(word);
      words.push(word);
    }
    node.replaceWith(fragment);
  }

  // The story's timeline. Each word starts after the one before it, longer
  // words taking longer; fillers are slower and quieter, and a sentence
  // ends in a short silence.
  const lead = 280;
  const starts: number[] = [];
  const levels: { at: number; level: number }[] = [];
  let time = lead;
  for (const word of words) {
    const text = word.textContent ?? "";
    const isFiller = word.classList.contains("filler");
    starts.push(time);
    levels.push({ at: time, level: isFiller ? 0.42 : 1 });
    time += isFiller ? 320 : 70 + text.length * 12;
    if (/[.,”。，」、]$/.test(text)) {
      levels.push({ at: time, level: 0.14 });
      time += 140;
    }
  }
  const listenEnd = time;
  const decodeEnd = listenEnd + 520;
  const refineEnd = decodeEnd + 760;
  const typeStep = 48;
  const strikeAt = (index: number) => decodeEnd + 120 + index * 220;

  // Typed in words where the text has spaces, otherwise two characters at
  // a time (Chinese and Japanese).
  const tokensOf = (text: string) =>
    /\s/.test(text)
      ? text.split(/(?<=\s)/)
      : Array.from(text).reduce<string[]>((chunks, char, index) => {
          if (index % 2 === 0) chunks.push(char);
          else chunks[chunks.length - 1] += char;
          return chunks;
        }, []);

  let selected: Profile = "clean";
  let tokens = tokensOf(examples.clean);
  const typeEnd = () => refineEnd + tokens.length * typeStep + 120;
  const format = (ms: number) => `0:${(ms / 1000).toFixed(1).padStart(4, "0")}`;
  const recorded = format(listenEnd - lead);

  // What was last drawn, so a frame only touches what changed.
  let drawn = {
    state: "" as State | "",
    said: -1,
    struck: -1,
    typed: -2,
    text: "",
    label: "",
    fill1: -1,
    fill2: -1,
  };
  let typedText: Text | null = null;
  let voiceUntil = 0;
  let lastBars = 0;
  let hasRun = false;

  const setLevels = (value: number) => {
    bars.forEach((bar, index) => {
      const shape =
        0.5 + 0.5 * Math.sin((Math.PI * (index + 0.5)) / bars.length);
      const jitter = value > 0.2 ? 0.55 + Math.random() * 0.45 : 1;
      bar.style.setProperty(
        "--level",
        Math.max(0.14, value * shape * jitter).toFixed(3),
      );
    });
  };
  const levelAt = (t: number) => {
    let level = 0.14;
    for (const mark of levels) {
      if (mark.at > t) break;
      level = mark.level;
    }
    return level;
  };
  const stateAt = (t: number): State =>
    t < 0
      ? "idle"
      : t < listenEnd
        ? "listening"
        : t < decodeEnd
          ? "decoding"
          : t < refineEnd
            ? "refining"
            : t < typeEnd()
              ? "typing"
              : "done";

  const showPlaceholder = () => {
    const paragraph = document.createElement("p");
    paragraph.className = "placeholder";
    paragraph.textContent = labels.placeholder;
    result.replaceChildren(paragraph);
    typedText = null;
  };
  const showTyped = (text: string) => {
    if (!typedText) {
      const paragraph = document.createElement("p");
      typedText = document.createTextNode("");
      const caret = document.createElement("span");
      caret.className = "caret";
      caret.setAttribute("aria-hidden", "true");
      paragraph.append(typedText, caret);
      result.replaceChildren(paragraph);
    }
    typedText.data = text;
  };

  // Draws the story at time t (t < 0 is the moment before it starts).
  const render = (t: number) => {
    const state = stateAt(t);
    if (state !== drawn.state) {
      root.dataset.state = state;
      status.textContent =
        state === "listening"
          ? labels.listening
          : state === "decoding"
            ? labels.transcribing
            : state === "refining"
              ? labels.refining
              : "";
      if (state === "typing") result.setAttribute("aria-busy", "true");
      else result.removeAttribute("aria-busy");
      if (state === "done") {
        hasRun = true;
        updateLabel();
      }
    }

    const saidCount =
      state === "idle"
        ? 0
        : state === "listening"
          ? starts.filter((start) => start <= t).length
          : words.length;
    if (saidCount !== drawn.said) {
      words.forEach((word, index) =>
        word.classList.toggle("said", index < saidCount),
      );
    }

    const struckCount =
      t < decodeEnd
        ? 0
        : fillers.filter((_, index) => strikeAt(index) <= t).length;
    if (struckCount !== drawn.struck) {
      fillers.forEach((filler, index) =>
        filler.classList.toggle("struck", index < struckCount),
      );
    }

    const typed =
      t < refineEnd
        ? -1
        : Math.min(tokens.length, Math.floor((t - refineEnd) / typeStep) + 1);
    const text = typed < 0 ? "" : tokens.slice(0, typed).join("");
    if (typed !== drawn.typed || text !== drawn.text) {
      if (typed < 0) showPlaceholder();
      else showTyped(text);
    }

    const label =
      state === "idle"
        ? format(0)
        : state === "listening"
          ? format(Math.max(0, t - lead))
          : state === "decoding"
            ? (hud.transcribing ?? "Transcribing")
            : state === "refining"
              ? (hud.refining ?? "Refining")
              : recorded;
    if (label !== drawn.label) hudLabel.textContent = label;

    const fill1 = state === "idle" ? 0 : clamp(t / listenEnd);
    const fill2 = clamp((t - listenEnd) / (refineEnd - listenEnd));
    if (fill1 !== drawn.fill1) root.style.setProperty("--fill-1", `${fill1}`);
    if (fill2 !== drawn.fill2) root.style.setProperty("--fill-2", `${fill2}`);

    drawn = {
      state,
      said: saidCount,
      struck: struckCount,
      typed,
      text,
      label,
      fill1,
      fill2,
    };
    return state;
  };

  // The pill's meter moves only while the voice is "audible": during a
  // replay, or for a moment after the scroll moves the words on.
  let meterFrame = 0;
  const meter = (now: number) => {
    meterFrame = 0;
    const speaking =
      drawn.state === "listening" && (now < voiceUntil || playback !== null);
    if (!speaking) {
      setLevels(0.14);
      return;
    }
    if (now - lastBars > 70) {
      lastBars = now;
      setLevels(levelAt(current));
    }
    meterFrame = requestAnimationFrame(meter);
  };
  const wakeMeter = () => {
    if (!meterFrame) meterFrame = requestAnimationFrame(meter);
  };

  // ---- Time: real-time playback from one moment to another.
  let current = -1;
  let playback: {
    from: number;
    until: number;
    began: number;
    hold: boolean;
  } | null = null;
  let playFrame = 0;
  // Who owns the frame: the scroll (pinned) or a playback.
  let owner: "scroll" | "time" = "time";
  let takeoverY = 0;

  const updateLabel = () => {
    playLabel.textContent = playback
      ? labels.stop
      : hasRun
        ? labels.again
        : labels.run;
    root.classList.toggle("is-playing", playback !== null);
  };
  const tick = (now: number) => {
    playFrame = 0;
    if (!playback) return;
    let t = playback.from + (now - playback.began);
    if (playback.hold) t = Math.min(t, listenEnd - 1);
    if (t >= playback.until) {
      stop(playback.until);
      return;
    }
    current = t;
    render(t);
    wakeMeter();
    playFrame = requestAnimationFrame(tick);
  };
  const start = (from: number, hold = false) => {
    cancelAnimationFrame(playFrame);
    owner = "time";
    takeoverY = scrollY;
    playback = {
      from,
      until: hold ? Infinity : typeEnd(),
      began: performance.now(),
      hold,
    };
    updateLabel();
    playFrame = requestAnimationFrame(tick);
  };
  // Ends a playback on a frame (by default the finished one).
  function stop(at = typeEnd()) {
    cancelAnimationFrame(playFrame);
    playback = null;
    current = at;
    render(at);
    setLevels(0.14);
    updateLabel();
  }

  // ---- Scroll: the pinned scene's runway picks the moment.
  let pinned = false;
  let pinTop = 96;
  let runway = 0;
  // Scroll progress (0 to 1 across the runway) to story time: step 1 takes
  // the first half, the tidy-up a quarter, the typing most of the rest, and
  // the finished frame holds briefly before the scene moves on.
  const scrollTime = () => {
    const progress = (pinTop - track.getBoundingClientRect().top) / runway;
    if (progress < 0) return -1;
    const points: [number, number][] = [
      [0, 0],
      [0.04, lead],
      [0.46, listenEnd],
      [0.56, decodeEnd],
      [0.68, refineEnd],
      [0.9, typeEnd()],
    ];
    for (let index = 1; index < points.length; index++) {
      const [s1, t1] = points[index];
      if (progress <= s1) {
        const [s0, t0] = points[index - 1];
        return t0 + ((progress - s0) / (s1 - s0)) * (t1 - t0);
      }
    }
    return typeEnd();
  };
  let scrollFrame = 0;
  const onScroll = () => {
    if (!pinned || scrollFrame) return;
    scrollFrame = requestAnimationFrame(() => {
      scrollFrame = 0;
      if (owner === "time") {
        if (holding || Math.abs(scrollY - takeoverY) < 48) return;
        cancelAnimationFrame(playFrame);
        playback = null;
        updateLabel();
        owner = "scroll";
      }
      const t = scrollTime();
      if (t !== current && stateAt(t) === "listening") {
        voiceUntil = performance.now() + 180;
        wakeMeter();
      }
      current = t;
      render(t);
    });
  };

  // The stage's middle column fits the pill's widest state, so the well
  // and the card never move while the pill changes (sample.css).
  const pill = find<HTMLElement>("[data-hud]");
  const measurePill = () => {
    const shown = hudLabel.textContent;
    let widest = 0;
    for (const label of [
      recorded,
      hud.transcribing ?? "",
      hud.refining ?? "",
    ]) {
      hudLabel.textContent = label;
      widest = Math.max(widest, pill.offsetWidth);
    }
    hudLabel.textContent = shown;
    // Layout width, scaled by the pill's own scale (never its ancestors').
    const scale = parseFloat(getComputedStyle(pill).scale) || 1;
    root.style.setProperty(
      "--hud-column",
      `${Math.ceil(widest * scale) + 40}px`,
    );
  };

  const layout = () => {
    measurePill();
    const header =
      parseFloat(
        getComputedStyle(document.documentElement).getPropertyValue("--header"),
      ) || 72;
    // Sticky positioning never changes the pin's own height.
    const height = pin.offsetHeight;
    const room = innerHeight - header;
    const fits = wide.matches && height + 32 <= room;
    if (fits) {
      pinTop = Math.round(header + Math.max(16, (room - height) / 2));
      runway = Math.round(Math.max(900, innerHeight * 1.7));
      root.style.setProperty("--pin-top", `${pinTop}px`);
      root.style.setProperty("--runway", `${runway}px`);
    }
    root.classList.toggle("is-pinned", fits);
    if (fits === pinned) return;
    pinned = fits;
    if (pinned) {
      if (!playback) {
        owner = "scroll";
        current = scrollTime();
        render(current);
      }
    } else if (owner === "scroll") {
      owner = "time";
      stop();
    }
  };

  // ---- The shortcut: hold ⌃⌥ (or press and hold the keycaps or the well).
  let holding = false;
  let holdBegan = 0;
  let beforeHold = -1;
  const startHold = () => {
    if (holding || playback?.hold) return;
    holding = true;
    holdBegan = performance.now();
    beforeHold = current;
    captureWebsiteEvent("demo_started", {
      demo: "sample",
      profile: selected,
      placement: "sample",
    });
    if (reducedMotion.matches) return;
    start(0, true);
  };
  const cancelHold = () => {
    if (!holding) return;
    holding = false;
    if (reducedMotion.matches) return;
    cancelAnimationFrame(playFrame);
    playback = null;
    updateLabel();
    if (pinned) {
      owner = "scroll";
      current = scrollTime();
      render(current);
    } else stop(beforeHold < 0 ? typeEnd() : beforeHold);
    setLevels(0.14);
  };
  const releaseHold = () => {
    if (!holding) return;
    if (performance.now() - holdBegan < 300) return cancelHold();
    holding = false;
    if (reducedMotion.matches) return stop();
    start(listenEnd);
  };

  // Only while the visitor is at the scene (the pointer over it or focus
  // inside), so VoiceOver's ⌃⌥ commands elsewhere never start it.
  let visible = false;
  const engaged = () =>
    scene.matches(":hover") || scene.contains(document.activeElement);
  const held = new Set<string>();
  const shortcutOnly = () =>
    [...held].every((key) => key === "Control" || key === "Alt");
  window.addEventListener("keydown", (event) => {
    held.add(event.key);
    if (holding && !shortcutOnly()) return cancelHold();
    if (
      event.ctrlKey &&
      event.altKey &&
      !event.metaKey &&
      !event.shiftKey &&
      shortcutOnly() &&
      visible &&
      engaged()
    ) {
      startHold();
    }
  });
  window.addEventListener("keyup", (event) => {
    held.delete(event.key);
    if (event.key === "Control" || event.key === "Alt") releaseHold();
  });
  window.addEventListener("blur", () => {
    held.clear();
    cancelHold();
  });
  for (const target of [
    said,
    ...root.querySelectorAll<HTMLElement>(".step-hold kbd"),
  ]) {
    target.addEventListener("pointerdown", (event) => {
      if (event.button !== 0) return;
      try {
        target.setPointerCapture(event.pointerId);
      } catch {
        // Synthetic pointers cannot be captured; the release still arrives.
      }
      startHold();
    });
    target.addEventListener("pointerup", releaseHold);
    // A touch that turns into a scroll is not a dictation.
    target.addEventListener("pointercancel", cancelHold);
  }

  // ---- Controls.
  play.addEventListener("click", () => {
    if (playback) return stop();
    captureWebsiteEvent("demo_started", {
      demo: "sample",
      profile: selected,
      placement: "sample",
    });
    hasRun = true;
    if (reducedMotion.matches) return stop();
    start(0);
  });
  profiles.forEach((button) => {
    button.addEventListener("click", () => {
      selected = button.dataset.profile as Profile;
      tokens = tokensOf(examples[selected]);
      captureWebsiteEvent("demo_profile_selected", {
        profile: selected,
        placement: "sample",
      });
      profiles.forEach((profile) =>
        profile.setAttribute("aria-pressed", String(profile === button)),
      );
      drawn.text = "\u0000";
      if (reducedMotion.matches) return stop();
      // Re-run only the refinement of what was said.
      start(decodeEnd);
    });
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden && playback && !holding) stop();
  });

  play.hidden = false;
  picker.hidden = false;
  root.classList.add("is-live");

  if (reducedMotion.matches || !("IntersectionObserver" in window)) {
    stop();
    return;
  }

  // Off screen, a playback rests on its finished frame; on screen (and not
  // pinned) the story plays once, the first time the scene's centre (or the
  // centre of the part that fits) reaches 60% of the window's height.
  let autoplayed = false;
  new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        visible = entry.isIntersecting;
        if (!visible) {
          if (playback && !holding) stop();
          continue;
        }
        if (autoplayed || pinned || playback) continue;
        const { top, height } = entry.boundingClientRect;
        const centre = top + Math.min(height, innerHeight) / 2;
        if (centre <= innerHeight * 0.6) {
          autoplayed = true;
          hasRun = true;
          start(0);
        }
      }
    },
    { threshold: Array.from({ length: 21 }, (_, index) => index / 20) },
  ).observe(scene);

  render(-1);
  layout();
  addEventListener("scroll", onScroll, { passive: true });
  addEventListener("resize", () => {
    layout();
    if (pinned && owner === "scroll") {
      current = scrollTime();
      render(current);
    }
  });
  wide.addEventListener("change", layout);
  document.fonts?.ready.then(measurePill);
  reducedMotion.addEventListener("change", () => {
    layout();
    if (reducedMotion.matches) stop();
  });
}
