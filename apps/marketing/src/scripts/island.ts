/**
 * The page island fills the window once the visitor scrolls, and becomes an
 * inset island again as its end nears the footer (see `.island` in
 * global.css). The fill is the lesser of two values:
 *
 * - `--island-open`, 0 to 1 over the first `OPEN` pixels of scroll. Where the
 *   browser has scroll timelines and motion is allowed, CSS drives it with
 *   `.island-scroll`, together with the hold that keeps content almost still
 *   while the island opens; both follow the scroll in the same frame, which a
 *   script cannot do without the content jittering. Elsewhere this script
 *   sets it, without a hold.
 * - `--island-close`, 1 to 0 over the last `CLOSE` pixels before the island's
 *   bottom edge enters the window. Only the clip changes there, so a script
 *   that follows a frame later is enough.
 *
 * The header's progressive blur appears (`.is-blurred`) once the island is
 * full, before any held content reaches the header; without the hold, as
 * soon as the page scrolls. Without JavaScript the island stays inset.
 */
const OPEN = 160;
const CLOSE = 120;

const root = document.documentElement;
const island = document.querySelector<HTMLElement>("main.island");
const header = document.querySelector<HTMLElement>(".site-header");
const driven =
  CSS.supports("animation-timeline: scroll()") &&
  matchMedia("(prefers-reduced-motion: no-preference)").matches;

if (island) {
  if (driven) root.classList.add("island-scroll");
  let frame = 0;
  let openShown = -1;
  let closeShown = -1;

  const clamp = (value: number) => Math.min(1, Math.max(0, value));
  // Rounded to keep style writes rare once the island is full.
  const round = (value: number) => Math.round(value * 1000) / 1000;

  const update = () => {
    frame = 0;
    const open = clamp(window.scrollY / OPEN);
    header?.classList.toggle("is-blurred", driven ? open === 1 : open > 0);
    if (!driven && open !== openShown) {
      openShown = open;
      island.style.setProperty("--island-open", String(round(open)));
    }
    const close = round(
      clamp(
        (island.getBoundingClientRect().bottom - window.innerHeight) / CLOSE,
      ),
    );
    if (close === closeShown) return;
    closeShown = close;
    island.style.setProperty("--island-close", String(close));
  };

  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(update);
  };

  addEventListener("scroll", schedule, { passive: true });
  addEventListener("resize", schedule);
  // Content below the fold (fonts, the pinned story) can change the
  // island's height without a scroll.
  new ResizeObserver(schedule).observe(island);
  update();
}

/**
 * Scroll-linked scripts measure positions for the rest of the page, where the
 * hold has finished. `settleIsland(true)` applies that layout for the
 * measurement; `settleIsland(false)` returns to the scroll position's.
 */
export function settleIsland(on: boolean) {
  root.classList.toggle("island-measure", on);
}
