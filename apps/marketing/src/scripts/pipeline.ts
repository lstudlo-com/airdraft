// The provider board's run (components/PipelineStory.astro), the homepage's
// climax: one dictation passes through the visitor's choices, in the order
// dictation runs.
//
//   Speech      the chosen row's check island sinks into its well with a busy
//               status dot while it works, then rises with its check
//   chevron     the raised chevron on the next groove presses as the text
//               passes into the next column
//   Refinement  as Speech
//   Insertion   the misheard words are struck and the dictionary's spelling
//               comes in, then the caret blinks at the end of the line
//
// It runs once when the board has risen (half of it on screen), and again
// from a column whenever its choice changes. Leaving the screen jumps to the
// resting frame, which is the board's CSS without a run. With reduced motion
// it never runs; the choices still swap their tables (CSS).
import { gsap } from "gsap";

const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const board = document.querySelector<HTMLElement>("[data-pipeline]");
if (board) setup(board);

function setup(board: HTMLElement) {
  const stages = [
    ...board.querySelectorAll<HTMLElement>(":scope > .pipe-stage"),
  ];
  const fix = board.querySelector<HTMLElement>("[data-fix-field] .fix");
  let run: gsap.core.Timeline | null = null;
  let queued: gsap.core.Tween | null = null;
  let visible = false;
  let ran = false;

  const rest = () => {
    queued?.kill();
    queued = null;
    run?.kill();
    run = null;
    for (const stage of stages) {
      stage.classList.remove("is-working", "is-passing");
    }
    fix?.style.removeProperty("--fix");
  };

  /** Run from the stage at `from` to Insertion. */
  const play = (from: number) => {
    if (reduced.matches) return;
    rest();
    const timeline = gsap.timeline({ onComplete: rest });
    let at = 0;
    stages.slice(from).forEach((stage, offset) => {
      const index = from + offset;
      // The groove's chevron sits on this stage; it presses as text arrives.
      if (index > 0) {
        timeline
          .call(() => stage.classList.add("is-passing"), [], at)
          .call(() => stage.classList.remove("is-passing"), [], at + 0.22);
        at += 0.24;
      }
      if (index < stages.length - 1) {
        timeline
          .call(() => stage.classList.add("is-working"), [], at)
          .call(() => stage.classList.remove("is-working"), [], at + 0.8);
        at += 1.05;
        return;
      }
      if (!fix) return;
      timeline
        .set(fix, { "--fix": 0 }, 0)
        .to(fix, { "--fix": 1, duration: 1.3, ease: "none" }, at + 0.15);
      at += 1.6;
    });
    run = timeline;
  };

  // Once, when the board has risen.
  new IntersectionObserver(
    ([entry]) => {
      visible = entry.isIntersecting;
      if (!visible) return rest();
      if (!ran && entry.intersectionRatio >= 0.5) {
        ran = true;
        queued = gsap.delayedCall(0.35, () => play(0));
      }
    },
    { threshold: [0, 0.5] },
  ).observe(board);

  // A changed choice runs again from its column, after the table has
  // swapped in (the CSS transition is 480ms).
  stages.forEach((stage, index) =>
    stage.addEventListener("change", () => {
      if (!visible) return;
      rest();
      queued = gsap.delayedCall(0.3, () => play(index));
    }),
  );

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) rest();
  });
}

export {};
