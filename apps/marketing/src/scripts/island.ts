/**
 * The page island fills the window once the visitor scrolls, and becomes an
 * inset island again as its end nears the footer. `--island-fill` runs from 0
 * (inset, rounded) to 1 (edge to edge, square) over the first `RANGE` pixels
 * of scroll, and back to 0 over the last `RANGE` pixels before the island's
 * bottom edge enters the window. The CSS draws the inset with `clip-path`, so
 * the page's layout and line breaks never change while it moves.
 *
 * It follows the scroll position directly, without its own timing. Without
 * JavaScript the island stays inset.
 *
 * The header's progressive blur appears only once the island has filled the
 * window (`.is-blurred`); at the top of the page there is nothing under it.
 */
const RANGE = 120;

const island = document.querySelector<HTMLElement>("main.island");
const header = document.querySelector<HTMLElement>(".site-header");

if (island) {
  let frame = 0;
  let current = -1;

  const clamp = (value: number) => Math.min(1, Math.max(0, value));

  const update = () => {
    frame = 0;
    const opening = clamp(window.scrollY / RANGE);
    header?.classList.toggle("is-blurred", opening === 1);
    const closing = clamp(
      (island.getBoundingClientRect().bottom - window.innerHeight) / RANGE,
    );
    // Rounded to keep style writes rare once the island is full.
    const fill = Math.round(Math.min(opening, closing) * 1000) / 1000;
    if (fill === current) return;
    current = fill;
    island.style.setProperty("--island-fill", String(fill));
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
