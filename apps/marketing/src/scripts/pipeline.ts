// The provider story (components/PipelineStory.astro). One dictation runs
// through Speech, Refinement and Insertion as the visitor scrolls; every
// state is derived in CSS from one number, --p (src/styles/pipeline.css).
//
// Where the browser has scroll timelines, CSS runs --p by itself and this
// script only answers a changed choice. Elsewhere it sets --p from the scroll
// position over the same ranges: while the cards are pinned on desktop
// (`contain`), and over 10% to 82% of the stack's `cover` range when they
// are stacked. The cards stay still while --p changes (pinned, or each
// state is only a lift of a few pixels), so a frame of lag never shows as
// jitter. With reduced motion none of it runs and the resting frame (the
// finished dictation) shows.
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const stacked = matchMedia("(max-width: 1000px)");
const scroller = document.querySelector<HTMLElement>("[data-pipeline]");
if (scroller) setup(scroller);

function setup(scroller: HTMLElement) {
  const clamp = (value: number) => Math.min(1, Math.max(0, value));
  let frame = 0;

  const measure = () => {
    frame = 0;
    const box = scroller.getBoundingClientRect();
    const view = innerHeight;
    const p = stacked.matches
      ? ((view - box.top) / (box.height + view) - 0.1) / 0.72
      : -box.top / Math.max(1, box.height - view);
    scroller.style.setProperty("--p", clamp(p).toFixed(4));
  };
  const queue = () => {
    if (!frame) frame = requestAnimationFrame(measure);
  };

  const scrub = () => {
    const on = !reduced.matches && !CSS.supports("animation-timeline: view()");
    scroller.classList.toggle("is-scrubbed", on);
    removeEventListener("scroll", queue);
    removeEventListener("resize", queue);
    if (!on) {
      scroller.style.removeProperty("--p");
      return;
    }
    addEventListener("scroll", queue, { passive: true });
    addEventListener("resize", queue);
    queue();
  };
  scrub();
  reduced.addEventListener("change", scrub);
  stacked.addEventListener("change", queue);

  // A changed choice works again in place for a moment: the new table's
  // check island sinks with a busy dot, then its check returns.
  for (const stage of scroller.querySelectorAll<HTMLElement>(".pipe-stage")) {
    let timer = 0;
    stage.addEventListener("change", () => {
      if (reduced.matches) return;
      clearTimeout(timer);
      stage.classList.add("is-rerun");
      timer = window.setTimeout(() => stage.classList.remove("is-rerun"), 900);
    });
  }
}

export {};
