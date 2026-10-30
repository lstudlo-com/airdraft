// The hero in three dimensions: Home's waveform drawn as one folded metal
// ribbon that narrows to nothing where the caret stands, and comes apart
// into a sound wave of fine grains as the hero scrolls away
// (src/scripts/hero3d-scene.ts). This file only decides whether to load it,
// and when.
//
// The HTML card stays the source of truth and the fallback. Without
// JavaScript, without WebGL, or with Save-Data or a reduced-data preference
// the HTML card is the hero. Otherwise, once the page has loaded and gone
// idle, three.js loads (its own chunk, requested only by the homepages) and
// the scene draws over the card, shaped by its bars and the pretend
// dictation (dictate.ts); then the HTML card's visuals fade. The HTML keeps
// its box, so nothing moves when the scene arrives.

const card = document.querySelector<HTMLElement>("[data-dictate]");
const connection = (
  navigator as Navigator & { connection?: { saveData?: boolean } }
).connection;
const lean =
  connection?.saveData === true ||
  matchMedia("(prefers-reduced-data: reduce)").matches;

let teardown: (() => void) | null = null;

function context(canvas: HTMLCanvasElement) {
  try {
    return canvas.getContext("webgl2", {
      alpha: true,
      antialias: true,
      premultipliedAlpha: true,
      powerPreference: "default",
      failIfMajorPerformanceCaveat: true,
    });
  } catch {
    return null;
  }
}

async function start(card: HTMLElement) {
  if (teardown) return;
  const canvas = document.createElement("canvas");
  canvas.className = "hero-3d";
  canvas.setAttribute("aria-hidden", "true");
  const gl = context(canvas);
  if (!gl) return;
  try {
    const { mount } = await import("./hero3d-scene");
    teardown = mount(card, canvas, gl);
  } catch {
    // A failed chunk or shader leaves the HTML card, which is complete.
    canvas.remove();
    card.classList.remove("is-3d");
  }
}

function whenIdle(run: () => void) {
  const go = () =>
    "requestIdleCallback" in window
      ? requestIdleCallback(run, { timeout: 1500 })
      : setTimeout(run, 200);
  if (document.readyState === "complete") go();
  else addEventListener("load", go, { once: true });
}

if (card && !lean) {
  whenIdle(() => start(card));
  // Leaving the page frees the GPU; coming back from the back/forward
  // cache builds the scene again.
  addEventListener("pagehide", () => {
    teardown?.();
    teardown = null;
  });
  addEventListener("pageshow", (event) => {
    if (event.persisted) whenIdle(() => start(card));
  });
}

export {};
