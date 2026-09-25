// A shared "voice" for every waveform on the page ([data-waveform]): the 3D
// capsules use `--lift` (px); the flat logo uses `--gain` (0–1).
// Moving the pointer or scrolling is treated as speaking: the faster the
// movement, the louder the voice, and the bars rise and fall with it. Bars in a
// waveform marked [data-follow] also lean toward the pointer. The loop runs
// only while the voice is audible and a waveform is on screen; with reduced
// motion nothing moves.

interface Bar {
  element: HTMLElement;
  base: number;
  index: number;
}

interface Waveform {
  element: HTMLElement;
  bars: Bar[];
  voice: number;
  follow: boolean;
  visible: boolean;
}

const still = matchMedia("(prefers-reduced-motion: reduce)");
const waveforms: Waveform[] = [];
let energy = 0;
let level = 0;
let frame = 0;
let pointerX = -1;
let last = { x: 0, y: 0, time: 0 };
let lastScroll = window.scrollY;

function register() {
  for (const element of document.querySelectorAll<HTMLElement>(
    "[data-waveform]:not([data-voice-ready])",
  )) {
    element.dataset.voiceReady = "";
    const waveform: Waveform = {
      element,
      voice: Number(element.dataset.voice ?? 0),
      follow: "follow" in element.dataset,
      visible: true,
      bars: [...element.querySelectorAll<HTMLElement>("[data-bar]")].map(
        (bar) => ({
          element: bar,
          base: Number(bar.dataset.base ?? 0),
          index: Number(bar.dataset.index ?? 0),
        }),
      ),
    };
    waveforms.push(waveform);
    new IntersectionObserver(([entry]) => {
      waveform.visible = entry.isIntersecting;
    }).observe(element);
  }
}

function speak(amount: number) {
  if (still.matches) return;
  energy = Math.min(1, energy + amount);
  if (!frame) frame = requestAnimationFrame(tick);
}

function tick(time: number) {
  energy *= 0.93;
  level += (energy - level) * 0.16;
  const seconds = time / 1000;

  for (const waveform of waveforms) {
    if (!waveform.visible) continue;
    const bounds =
      waveform.follow && pointerX >= 0
        ? waveform.element.getBoundingClientRect()
        : null;
    const count = waveform.bars.length;
    for (const bar of waveform.bars) {
      const wobble =
        0.5 + 0.5 * Math.sin(seconds * (6 + bar.index * 1.7) + bar.index * 2.1);
      let focus = 1;
      if (bounds) {
        const barX = bounds.left + ((bar.index + 0.5) / count) * bounds.width;
        focus = Math.max(0.25, 1 - Math.abs(pointerX - barX) / bounds.width);
      }
      const gain = level * (0.3 + 0.7 * wobble) * focus;
      bar.element.style.setProperty(
        "--lift",
        `${(bar.base + waveform.voice * gain).toFixed(2)}px`,
      );
      bar.element.style.setProperty("--gain", gain.toFixed(3));
    }
  }

  if (energy < 0.003 && level < 0.003) {
    level = 0;
    energy = 0;
    for (const waveform of waveforms) {
      for (const bar of waveform.bars) {
        bar.element.style.setProperty("--lift", `${bar.base}px`);
        bar.element.style.setProperty("--gain", "0");
      }
    }
    frame = 0;
    return;
  }
  frame = requestAnimationFrame(tick);
}

register();

window.addEventListener(
  "pointermove",
  (event) => {
    const elapsed = Math.max(event.timeStamp - last.time, 8);
    const distance = Math.hypot(event.clientX - last.x, event.clientY - last.y);
    last = { x: event.clientX, y: event.clientY, time: event.timeStamp };
    pointerX = event.clientX;
    speak(Math.min(0.35, (distance / elapsed) * 0.08));
  },
  { passive: true },
);

window.addEventListener(
  "scroll",
  () => {
    const moved = Math.abs(window.scrollY - lastScroll);
    lastScroll = window.scrollY;
    speak(Math.min(0.3, moved * 0.004));
  },
  { passive: true },
);

document.addEventListener("pointerleave", () => {
  pointerX = -1;
});

// A short burst, e.g. when the logo is hovered.
export function pulse(amount = 0.6) {
  speak(amount);
}
