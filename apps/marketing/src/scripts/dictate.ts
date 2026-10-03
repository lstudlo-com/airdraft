// The hero's waveform card does what its caption says. Hold ⌃⌥, or press and
// hold the waveform or its keycaps: the recording pill replaces the caption
// and a live bar grows at the caret. Let go: the pill shows Refining, the bar
// settles at a height from the dictation's length (the app's 0.26 + 0.74 ×
// √share), the oldest bar slides out, and the caret lifts as it does in the
// app when a dictation lands (HomeHero's flare).
//
// Nothing is recorded: the level is a synthetic speech envelope. The card is
// decorative (aria-hidden visuals); the caption carries the instruction. Any
// third key cancels a keyboard hold, so VoiceOver's ⌃⌥ commands never add a
// bar. With reduced motion the live bar holds one level and nothing animates.

type State = "idle" | "recording" | "refining";

const card = document.querySelector<HTMLElement>("[data-dictate]");
if (card) setup(card);

function setup(card: HTMLElement) {
  const wave = card.querySelector<HTMLElement>(".wave")!;
  const caret = wave.querySelector<HTMLElement>(".wave-caret")!;
  const label = card.querySelector<HTMLElement>("[data-hud-label]")!;
  const meter = [...card.querySelectorAll<HTMLElement>(".hud-bars span")];
  const still = matchMedia("(prefers-reduced-motion: reduce)");
  const longest = 6; // seconds that make a full-height bar
  let state: State = "idle";
  let live: HTMLElement | null = null;
  let leaving: HTMLElement | null = null;
  let started = 0;
  let frame = 0;
  let lastMeter = 0;
  let autoStop = 0;
  let visible = false;

  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (!visible) cancel();
  }).observe(card);

  // Syllable-like bursts inside slower phrases, between 0.15 and 1.
  const envelope = (t: number) => {
    const syllable = Math.max(
      0,
      0.5 * Math.sin(t * 11.3) +
        0.35 * Math.sin(t * 4.1 + 1.3) +
        0.15 * Math.sin(t * 23.7),
    );
    const phrase = 0.55 + 0.45 * Math.sin(t * 1.7);
    return Math.min(1, 0.15 + syllable * phrase * 1.15 + Math.random() * 0.06);
  };

  const format = (seconds: number) =>
    `${Math.floor(seconds / 60)}:${(seconds % 60).toFixed(1).padStart(4, "0")}`;

  const resetMeter = () => {
    for (const bar of meter) bar.style.setProperty("--level", "0.14");
  };

  function start() {
    if (state !== "idle") return;
    state = "recording";
    started = performance.now();
    lastMeter = 0;
    card.classList.add("is-recording");
    label.textContent = "0:00.0";
    resetMeter();

    live = document.createElement("span");
    live.className = "wave-bar is-live";
    live.style.setProperty("--h", "1");
    live.style.setProperty("--cap", "1.25");
    live.append(document.createElement("i"));
    wave.insertBefore(live, caret);
    // The oldest bar makes room for the new one.
    leaving = wave.querySelector<HTMLElement>(
      ".wave-bar:not(.is-live):not(.is-leaving)",
    );
    leaving?.classList.add("is-leaving");

    frame = requestAnimationFrame(tick);
    autoStop = window.setTimeout(stop, 8000);
  }

  function tick(now: number) {
    if (state !== "recording" || !live) return;
    const seconds = (now - started) / 1000;
    const level = still.matches ? 0.6 : envelope(seconds);
    live.style.setProperty("--live", level.toFixed(3));
    // The pill's meter advances like the app's: newest sample on the right.
    if (now - lastMeter > 70) {
      lastMeter = now;
      for (let index = 0; index < meter.length - 1; index++) {
        meter[index].style.setProperty(
          "--level",
          meter[index + 1].style.getPropertyValue("--level") || "0.14",
        );
      }
      meter.at(-1)?.style.setProperty("--level", level.toFixed(3));
      label.textContent = format(seconds);
    }
    frame = requestAnimationFrame(tick);
  }

  function stop() {
    if (state !== "recording" || !live) return;
    const seconds = (performance.now() - started) / 1000;
    if (seconds < 0.3) return cancel();
    clearTimeout(autoStop);
    cancelAnimationFrame(frame);
    state = "refining";
    card.classList.replace("is-recording", "is-refining");
    label.textContent = "Refining";

    const settled = live;
    const gone = leaving;
    const height = 0.26 + 0.74 * Math.sqrt(Math.min(1, seconds / longest));
    window.setTimeout(
      () => {
        settled.classList.add("is-settling");
        settled.classList.remove("is-live");
        settled.style.setProperty("--h", height.toFixed(3));
        settled.style.setProperty("--cap", (60 / (48 * height)).toFixed(3));
        settled.style.removeProperty("--live");
        settled.dataset.bar = "";
        window.setTimeout(() => settled.classList.remove("is-settling"), 520);
        gone?.remove();
        caret.classList.remove("is-flare");
        void caret.offsetWidth;
        caret.classList.add("is-flare");
        card.classList.remove("is-refining");
        live = null;
        leaving = null;
        state = "idle";
        resetMeter();
      },
      still.matches ? 0 : 650,
    );
  }

  function cancel() {
    if (state !== "recording") return;
    clearTimeout(autoStop);
    cancelAnimationFrame(frame);
    live?.remove();
    leaving?.classList.remove("is-leaving");
    live = null;
    leaving = null;
    card.classList.remove("is-recording");
    state = "idle";
    resetMeter();
  }

  // Keyboard: ⌃⌥ alone, while the card is on screen.
  const held = new Set<string>();
  const shortcutOnly = () =>
    [...held].every((key) => key === "Control" || key === "Alt");
  window.addEventListener("keydown", (event) => {
    held.add(event.key);
    if (state === "recording" && !shortcutOnly()) return cancel();
    if (
      event.ctrlKey &&
      event.altKey &&
      !event.metaKey &&
      !event.shiftKey &&
      shortcutOnly() &&
      visible
    ) {
      start();
    }
  });
  window.addEventListener("keyup", (event) => {
    held.delete(event.key);
    if (event.key === "Control" || event.key === "Alt") stop();
  });
  window.addEventListener("blur", () => {
    held.clear();
    cancel();
  });

  // Pointer: press and hold the waveform or the caption's keycaps.
  for (const target of [
    wave,
    ...card.querySelectorAll<HTMLElement>(".hero-caption kbd"),
  ]) {
    target.addEventListener("pointerdown", (event) => {
      if (event.button !== 0) return;
      // Keep receiving the release even if the pointer leaves the target.
      try {
        target.setPointerCapture(event.pointerId);
      } catch {
        // Synthetic pointers cannot be captured; the release still arrives.
      }
      start();
    });
    target.addEventListener("pointerup", stop);
    // A touch that turns into a scroll is not a dictation.
    target.addEventListener("pointercancel", cancel);
  }
}

export {};
