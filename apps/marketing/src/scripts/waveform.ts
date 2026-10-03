// Home's hover, as in HomeHero.swift: bars near the pointer grow by up to 28%
// on a Gaussian two and a half bars wide, never past the caret, and the bar
// under the pointer deepens toward the caret's tone. With reduced motion the
// bars keep their size and only the tone changes.

const still = matchMedia("(prefers-reduced-motion: reduce)");

for (const wave of document.querySelectorAll<HTMLElement>(
  "[data-magnify]:not([data-magnify-ready])",
)) {
  wave.dataset.magnifyReady = "";
  const bars = [...wave.querySelectorAll<HTMLElement>(".wave-bar")];
  const caps = bars.map(
    (bar) => Number(bar.style.getPropertyValue("--cap")) || 1.5,
  );
  let pointer: number | null = null;
  let frame = 0;

  const render = () => {
    frame = 0;
    const shown = bars
      .map((bar, index) => ({ bar, index, rect: bar.getBoundingClientRect() }))
      .filter(({ rect }) => rect.width > 0);
    const step =
      shown.length > 1
        ? shown[1].rect.left - shown[0].rect.left
        : (shown[0]?.rect.width ?? 1);
    let hovered: HTMLElement | null = null;
    for (const { bar, index, rect } of shown) {
      if (pointer === null) {
        bar.style.removeProperty("--magnify");
        continue;
      }
      const center = rect.left + rect.width / 2;
      if (Math.abs(center - pointer) <= step / 2) hovered = bar;
      if (still.matches) continue;
      const distance = (center - pointer) / (step * 2.4);
      const magnify = 1 + 0.28 * Math.exp(-distance * distance);
      bar.style.setProperty(
        "--magnify",
        Math.min(caps[index], magnify).toFixed(3),
      );
    }
    for (const bar of bars) bar.classList.toggle("is-hovered", bar === hovered);
  };

  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(render);
  };
  wave.addEventListener("pointermove", (event) => {
    pointer = event.clientX;
    schedule();
  });
  wave.addEventListener("pointerleave", () => {
    pointer = null;
    schedule();
  });
}
