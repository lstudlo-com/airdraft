// The interface section (components/InterfaceShowcase.astro).
//
//   compare   dragging the window (or the keyboard on its range input) moves
//             the divider between the light and dark renders
//   specimens each answers the pointer; with motion allowed, each also plays
//             a short loop while on screen, until the visitor touches it
//
// Resting CSS is the final state, so the section reads without JavaScript.

const reduced = matchMedia("(prefers-reduced-motion: reduce)");

function compare(frame: HTMLElement) {
  const range = frame.querySelector<HTMLInputElement>("[data-compare-range]");
  if (!range) return;
  range.hidden = false;

  const set = (percent: number) => {
    const value = Math.round(Math.min(100, Math.max(0, percent)));
    frame.classList.remove("awaits-sweep", "is-sweeping");
    frame.style.setProperty("--split", `${value}%`);
    range.value = String(value);
    range.setAttribute(
      "aria-valuetext",
      value >= 100
        ? "All light"
        : value <= 0
          ? "All dark"
          : `${value}% light, ${100 - value}% dark`,
    );
  };
  const fromPointer = (event: PointerEvent) => {
    const box = frame.getBoundingClientRect();
    set(((event.clientX - box.left) / box.width) * 100);
  };

  frame.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    frame.setPointerCapture(event.pointerId);
    frame.classList.add("is-dragging");
    fromPointer(event);
  });
  frame.addEventListener("pointermove", (event) => {
    if (frame.hasPointerCapture(event.pointerId)) fromPointer(event);
  });
  const release = () => frame.classList.remove("is-dragging");
  frame.addEventListener("pointerup", release);
  frame.addEventListener("pointercancel", release);
  range.addEventListener("input", () => set(Number(range.value)));

  // The one-time sweep: hold the divider at the right edge until the window
  // is half in view, then let it travel to the middle.
  if (reduced.matches || !CSS.supports("transition-property", "--split"))
    return;
  frame.classList.add("awaits-sweep");
  const watcher = new IntersectionObserver(
    ([entry]) => {
      if (!entry.isIntersecting) return;
      watcher.disconnect();
      if (!frame.classList.contains("awaits-sweep")) return;
      frame.classList.add("is-sweeping");
      frame.classList.remove("awaits-sweep");
      setTimeout(() => frame.classList.remove("is-sweeping"), 1300);
    },
    { threshold: 0.5 },
  );
  watcher.observe(frame);
}

/** Run `step` every `period` ms while `element` is on screen, until the
 *  visitor interacts with it. Never with reduced motion. */
function loop(element: HTMLElement, period: number, step: () => void) {
  let timer = 0;
  let stopped = false;
  const stop = () => {
    stopped = true;
    clearInterval(timer);
  };
  element.addEventListener("pointerdown", stop, { once: true });
  new IntersectionObserver(
    ([entry]) => {
      clearInterval(timer);
      if (entry.isIntersecting && !stopped && !reduced.matches) {
        timer = window.setInterval(step, period);
      }
    },
    { threshold: 0.6 },
  ).observe(element);
}

function press(root: HTMLElement) {
  const keys = root.querySelector<HTMLElement>(".keys");
  const caps = [...root.querySelectorAll<HTMLElement>("kbd")];
  for (const cap of caps) {
    const up = () => cap.classList.remove("is-down");
    cap.addEventListener("pointerdown", () => cap.classList.add("is-down"));
    cap.addEventListener("pointerup", up);
    cap.addEventListener("pointerleave", up);
    cap.addEventListener("pointercancel", up);
  }
  loop(root, 2600, () => {
    keys?.classList.add("is-pressed");
    setTimeout(() => keys?.classList.remove("is-pressed"), 1300);
  });
}

function sidebar(root: HTMLElement) {
  const well = root.querySelector<HTMLElement>("[data-spec-well]");
  const island = root.querySelector<HTMLElement>("[data-spec-island]");
  const rows = [...root.querySelectorAll<HTMLElement>("[data-spec-row]")];
  if (!well || !island) return;
  let current = 0;

  const select = (index: number) => {
    if (index === current) return;
    const from = rows[current].offsetTop;
    const to = rows[index].offsetTop;
    rows.forEach((row, position) =>
      row.classList.toggle("is-selected", position === index),
    );
    well.style.transform = `translateY(${to}px)`;
    // The island stays where it was, inside the moving well, then follows.
    island.style.transition = "none";
    island.style.transform = `translateY(${from - to}px)`;
    void island.offsetWidth;
    island.style.removeProperty("transition");
    island.style.transform = "translateY(0)";
    current = index;
  };

  rows.forEach((row, index) =>
    row.addEventListener("click", () => select(index)),
  );
  loop(root, 2200, () => select((current + 1) % rows.length));
}

function controls(root: HTMLElement) {
  const toggle = root.querySelector<HTMLElement>("[data-spec-switch]");
  const items = [
    ...root.querySelectorAll<HTMLElement>(
      "[data-spec-segmented] > li:not(.segmented-thumb)",
    ),
  ];
  const flip = () => toggle?.classList.toggle("is-on");
  const choose = (index: number) =>
    items.forEach((item, position) =>
      item.classList.toggle("is-selected", position === index),
    );
  const chosen = () =>
    items.findIndex((item) => item.classList.contains("is-selected"));

  toggle?.addEventListener("click", flip);
  items.forEach((item, index) =>
    item.addEventListener("click", () => choose(index)),
  );
  let beat = 0;
  loop(root, 1400, () => {
    if (beat++ % 2) choose((chosen() + 1) % items.length);
    else flip();
  });
}

for (const frame of document.querySelectorAll<HTMLElement>("[data-compare]")) {
  compare(frame);
}
for (const root of document.querySelectorAll<HTMLElement>(
  "[data-spec-press]",
)) {
  press(root);
}
for (const root of document.querySelectorAll<HTMLElement>(
  "[data-spec-sidebar]",
)) {
  sidebar(root);
}
for (const root of document.querySelectorAll<HTMLElement>(
  "[data-spec-controls]",
)) {
  controls(root);
}
