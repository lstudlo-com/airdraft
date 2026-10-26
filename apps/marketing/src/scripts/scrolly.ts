// The homepage's scroll story (StoryScroll.astro). While the visitor
// scrolls through the pinned section, one dictation plays out, scrubbed by
// the scroll position in both directions:
//
//   0.00–0.06  rest
//   0.06–0.60  the shortcut is held: the keys sink and the pill records
//              (timer and live bars) while the spoken words arrive
//   0.60–0.80  release: the pill refines, the fillers are struck out and
//              fold away
//   0.80–0.97  the result types in at the caret
//
// The steps beside it light in turn and the rail fills. A short smoothing
// (scrub) keeps it calm. Without JavaScript, and with reduced motion, the
// section is short and shows every step and the final frame (story.css).
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

gsap.registerPlugin(ScrollTrigger);

/** A steady pseudo-random level per bar and step, so scrubbing back and
 *  forth shows the same frames. */
const noise = (bar: number, step: number) => {
  const value = Math.sin(bar * 12.9898 + step * 78.233) * 43758.5453;
  return (0.22 + 0.78 * (value - Math.floor(value))).toFixed(3);
};
const between = (p: number, from: number, to: number) =>
  Math.min(1, Math.max(0, (p - from) / (to - from)));

function setup(section: HTMLElement) {
  const all = <T extends HTMLElement = HTMLElement>(selector: string) => [
    ...section.querySelectorAll<T>(selector),
  ];
  const keys = section.querySelector<HTMLElement>(".keys")!;
  const hud = section.querySelector<HTMLElement>("[data-hud]")!;
  const label = hud.querySelector<HTMLElement>("[data-hud-label]")!;
  const refining = hud.dataset.refining ?? "";
  const bars = all(".hud-bars span");
  const tokens = all("[data-token]");
  const fillers = tokens.filter((token) => token.hasAttribute("data-filler"));
  const words = all("[data-word]");
  const steps = all(".story-step");
  const rail = section.querySelector<HTMLElement>("[data-rail]")!;
  const header = () =>
    parseFloat(
      getComputedStyle(document.documentElement).getPropertyValue("--header"),
    ) || 60;

  // Fillers fold to nothing; each keeps its measured width to fold from.
  const measure = () => {
    for (const token of fillers) {
      token.style.removeProperty("--w");
      token.style.setProperty("--w", `${token.scrollWidth + 1}px`);
    }
  };

  let lastStep = -1;
  let lastBars = -1;
  const render = (p: number) => {
    const recording = p >= 0.06 && p < 0.6;
    keys.classList.toggle("is-pressed", recording);
    section.dataset.phase =
      p < 0.06
        ? "idle"
        : recording
          ? "recording"
          : p < 0.8
            ? "refining"
            : "typing";
    label.textContent = recording
      ? `0:${(between(p, 0.06, 0.6) * 6.4).toFixed(1).padStart(4, "0")}`
      : p >= 0.6
        ? refining
        : "0:00.0";
    const frame = recording ? Math.floor(p * 240) : -1;
    if (frame !== lastBars) {
      lastBars = frame;
      bars.forEach((bar, index) =>
        bar.style.setProperty(
          "--level",
          recording ? noise(index, frame) : "0.14",
        ),
      );
    }
    const heard = Math.round(between(p, 0.12, 0.56) * tokens.length);
    tokens.forEach((token, index) =>
      token.classList.toggle("is-heard", index < heard),
    );
    for (const filler of fillers) {
      filler.classList.toggle("struck", p >= 0.63);
      filler.classList.toggle("is-gone", p >= 0.71);
    }
    const typed = Math.round(between(p, 0.8, 0.97) * words.length);
    words.forEach((word, index) =>
      word.classList.toggle("is-typed", index < typed),
    );
    const step = p < 0.12 ? 0 : p < 0.6 ? 1 : p < 0.8 ? 2 : 3;
    if (step !== lastStep) {
      lastStep = step;
      steps.forEach((item, index) => {
        item.classList.toggle("is-active", index === step);
        item.classList.toggle("is-past", index < step);
      });
    }
    rail.style.transform = `scaleY(${p.toFixed(4)})`;
  };

  const media = gsap.matchMedia();
  media.add("(prefers-reduced-motion: no-preference)", () => {
    section.classList.add("is-scrolly");
    measure();
    lastStep = -1;
    render(0);
    const state = { p: 0 };
    const tween = gsap.to(state, {
      p: 1,
      ease: "none",
      onUpdate: () => render(state.p),
      scrollTrigger: {
        trigger: section,
        start: () => `top ${header()}px`,
        end: "bottom bottom",
        scrub: 0.4,
        invalidateOnRefresh: true,
        onRefreshInit: measure,
      },
    });
    return () => {
      tween.scrollTrigger?.kill();
      tween.kill();
      section.classList.remove("is-scrolly");
      delete section.dataset.phase;
      keys.classList.remove("is-pressed");
      for (const element of [...tokens, ...words, ...steps])
        element.classList.remove(
          "is-heard",
          "is-gone",
          "is-typed",
          "is-active",
          "is-past",
        );
      for (const filler of fillers) filler.classList.add("struck");
      rail.style.removeProperty("transform");
      label.textContent = "0:00.0";
    };
  });
}

const section = document.querySelector<HTMLElement>("[data-story]");
if (section) setup(section);

export {};
