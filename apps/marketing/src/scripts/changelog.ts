/** The reading position fills a recessed rail and slides the version selection.
 * Reveals play once; CSS is already readable if scripts or motion are disabled. */
import { settleIsland } from "./island";

const root = document.querySelector<HTMLElement>("[data-changelog]");

if (root) {
  const nav = root.querySelector<HTMLElement>(".release-nav")!;
  const timeline = root.querySelector<HTMLElement>(".release-timeline")!;
  const entries = [...root.querySelectorAll<HTMLElement>("[data-release]")];
  const links = [
    ...root.querySelectorAll<HTMLAnchorElement>("[data-release-link]"),
  ];
  const anchors = links.map((link) =>
    document.getElementById(link.hash.slice(1))!,
  );
  const motion = matchMedia("(prefers-reduced-motion: reduce)");
  let frame = 0;
  let selected: HTMLAnchorElement | undefined;
  let current: HTMLElement | undefined;

  function update() {
    frame = 0;
    // Actual viewport coordinates account for the shared island's opening hold.
    const readingLine = Math.min(200, innerHeight * 0.3);
    let index = 0;
    anchors.forEach((anchor, i) => {
      if (anchor.getBoundingClientRect().top <= readingLine) index = i;
    });
    const link = links[index];
    if (selected !== link) {
      selected?.removeAttribute("aria-current");
      link.setAttribute("aria-current", "location");
      selected = link;
    }
    nav.style.setProperty("--thumb-x", `${link.offsetLeft}px`);
    nav.style.setProperty("--thumb-y", `${link.offsetTop}px`);
    nav.style.setProperty("--thumb-width", `${link.offsetWidth}px`);
    nav.style.setProperty("--thumb-height", `${link.offsetHeight}px`);
    nav.dataset.ready = "";

    let active = entries[0];
    for (const entry of entries) {
      if (entry.getBoundingClientRect().top <= readingLine) active = entry;
      else break;
    }
    if (current !== active) {
      current?.removeAttribute("data-current");
      active.dataset.current = "";
      current = active;
    }
    const bounds = timeline.getBoundingClientRect();
    const progress = Math.max(
      0,
      Math.min(1, (readingLine - bounds.top) / bounds.height),
    );
    timeline.style.setProperty("--read-progress", String(progress));
  }
  function schedule() {
    if (!frame) frame = requestAnimationFrame(update);
  }
  addEventListener("scroll", schedule, { passive: true });
  addEventListener("resize", schedule);
  addEventListener("hashchange", schedule);
  new ResizeObserver(schedule).observe(timeline);
  update();

  function jump(hash: string, behavior: ScrollBehavior) {
    const target = entries.find((entry) => `#${entry.id}` === hash);
    if (!target) return;
    // Native fragment scrolling measures the island before its opening hold
    // finishes. Measure the settled layout so a jump lands under the header.
    settleIsland(true);
    const inset =
      parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop) +
      28;
    const top = target.getBoundingClientRect().top + scrollY - inset;
    settleIsland(false);
    target.focus({ preventScroll: true });
    scrollTo({ top, behavior: motion.matches ? "instant" : behavior });
    schedule();
  }
  root.addEventListener("click", (event) => {
    if (
      event.button ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    )
      return;
    const link = (event.target as Element).closest<HTMLAnchorElement>(
      'a[href^="#"]',
    );
    if (!link) return;
    event.preventDefault();
    if (location.hash !== link.hash) history.pushState(null, "", link.hash);
    jump(link.hash, "smooth");
  });
  addEventListener("hashchange", () => jump(location.hash, "instant"));
  if (location.hash) {
    if (document.readyState === "complete") jump(location.hash, "instant");
    else
      addEventListener("load", () => jump(location.hash, "instant"), {
        once: true,
      });
  }

  const running = new Set<Animation>();
  const reveal = new IntersectionObserver(
    (observations) => {
      for (const observation of observations) {
        if (!observation.isIntersecting) continue;
        reveal.unobserve(observation.target);
        if (motion.matches) continue;
        const card = observation.target;
        const parts = [
          card.querySelector("h2")!,
          ...card.querySelectorAll("li"),
        ];
        // The card lifts as a whole; its engraved rows resolve in a short cascade.
        const animations = [
          card.animate(
            [{ transform: "translateY(18px)" }, { transform: "translateY(0)" }],
            { duration: 650, easing: "cubic-bezier(0.16, 1, 0.3, 1)" },
          ),
          ...parts.map((part, index) =>
            part.animate(
              [
                { opacity: 0.35, transform: "translateY(8px)" },
                { opacity: 1, transform: "translateY(0)" },
              ],
              {
                duration: 480,
                delay: index * 55,
                easing: "cubic-bezier(0.16, 1, 0.3, 1)",
                fill: "backwards",
              },
            ),
          ),
        ];
        animations.forEach((animation) => {
          running.add(animation);
          animation.finished
            .finally(() => running.delete(animation))
            .catch(() => {});
        });
      }
    },
    { rootMargin: "0px 0px -8% 0px", threshold: 0 },
  );
  root
    .querySelectorAll(".release-card")
    .forEach((card) => reveal.observe(card));
  motion.addEventListener("change", () => {
    if (motion.matches) running.forEach((animation) => animation.cancel());
  });
}
