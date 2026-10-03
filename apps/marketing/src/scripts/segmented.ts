// SoftSegmentedPicker's sliding thumb: one raised face moves between the
// choices on SelectionMotion.curve (CSS), wherever the selection change came
// from (a click, preview.ts, a bento loop or a radio input). The selected
// item has `.is-selected`, `aria-pressed="true"` or a checked radio. Without
// JavaScript the selected item draws its own face instead.

const isSelected = (item: Element) =>
  item.classList.contains("is-selected") ||
  item.getAttribute("aria-pressed") === "true" ||
  Boolean(item.querySelector("input:checked"));

for (const track of document.querySelectorAll<HTMLElement>(
  ".segmented:not(.has-thumb)",
)) {
  const thumb = document.createElement(track.tagName === "UL" ? "li" : "span");
  thumb.className = "segmented-thumb";
  thumb.setAttribute("aria-hidden", "true");
  track.prepend(thumb);
  track.classList.add("has-thumb");
  const items = [...track.children].filter((child) => child !== thumb);

  const place = (instant: boolean) => {
    const item = items.find(isSelected) as HTMLElement | undefined;
    thumb.style.opacity = item ? "1" : "0";
    if (!item) return;
    if (instant) thumb.style.transition = "none";
    thumb.style.width = `${item.offsetWidth}px`;
    thumb.style.transform = `translateX(${item.offsetLeft}px)`;
    if (instant) {
      void thumb.offsetWidth;
      thumb.style.removeProperty("transition");
    }
  };

  place(true);
  track.addEventListener("change", () => place(false));
  new MutationObserver(() => place(false)).observe(track, {
    subtree: true,
    attributes: true,
    attributeFilter: ["class", "aria-pressed"],
  });
  // Also covers a picker that starts hidden and appears later.
  new ResizeObserver(() => place(true)).observe(track);
}
