/** The reading position moves a knob down a recessed rail and slides the
 * version selection. The knob marks the current release: it sits on that
 * release's stud and, while the release's version and date stay in view
 * beside a long card (sticky), travels down with them. The rail is filled
 * down to the knob, never past it. The knob and the fill follow on a
 * critically damped spring measured in time, not frames, so they trail the
 * same way at any frame rate, never overshoot, trail further the faster the
 * page moves and ease back to rest. With reduced motion they move directly.
 * Reveals play once; CSS is already readable if scripts or motion are
 * disabled. */
import { settleIsland } from "./island";

const root = document.querySelector<HTMLElement>("[data-changelog]");

// The spring's smoothing time: half way in a quarter second, 87% in half a
// second, settled in about a second, at any frame rate.
const SMOOTH_SECONDS = 0.28;

if (root) {
  const nav = root.querySelector<HTMLElement>(".release-nav")!;
  const timeline = root.querySelector<HTMLElement>(".release-timeline")!;
  const track = timeline.querySelector<HTMLElement>(".release-track")!;
  const entries = [...root.querySelectorAll<HTMLElement>("[data-release]")];
  const studs = entries.map((entry) =>
    entry.querySelector<HTMLElement>(".release-stud")!,
  );
  const metas = entries.map((entry) =>
    entry.querySelector<HTMLElement>(".release-meta")!,
  );
  const links = [
    ...root.querySelectorAll<HTMLAnchorElement>("[data-release-link]"),
  ];
  const anchors = links.map((link) =>
    document.getElementById(link.hash.slice(1))!,
  );
  const motion = matchMedia("(prefers-reduced-motion: reduce)");
  let frame = 0;
  let selected: HTMLAnchorElement | undefined;

  // Stud centres and the rail's top, in the timeline's coordinates. Both
  // sides of each difference share every transform above the timeline (the
  // island's opening hold), and the studs sit outside the rising cards.
  let centres: number[] = [];
  let railTop = 0;
  const measure = () => {
    const origin = timeline.getBoundingClientRect().top;
    centres = studs.map((stud) => {
      const box = stud.getBoundingClientRect();
      return box.top + box.height / 2 - origin;
    });
    railTop = track.getBoundingClientRect().top - origin;
  };

  // The knob's position and speed, and where it is heading.
  let position = 0;
  let velocity = 0;
  let target = 0;
  let glide = 0;
  let last = 0;

  const draw = () => {
    timeline.style.setProperty("--knob", `${position.toFixed(2)}px`);
    timeline.style.setProperty(
      "--fill",
      `${Math.max(0, position - railTop).toFixed(2)}px`,
    );
  };
  // One step of a critically damped spring over dt seconds (the closed
  // form's usual polynomial approximation of e^-x), stopped at the target.
  const step = (dt: number) => {
    const omega = 2 / SMOOTH_SECONDS;
    const x = omega * dt;
    const decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
    const offset = position - target;
    const pull = (velocity + omega * offset) * dt;
    velocity = (velocity - omega * pull) * decay;
    const next = target + (offset + pull) * decay;
    // Never past the target: a spring that overshot would carry the fill
    // beyond the stud it is heading for.
    if (target - position > 0 === next > target) {
      position = target;
      velocity = 0;
    } else position = next;
  };
  const tick = (now: number) => {
    // Frames are rarely longer than this; a backgrounded tab resumes from
    // where it was instead of jumping.
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    step(dt);
    if (Math.abs(target - position) < 0.25 && Math.abs(velocity) < 2) {
      position = target;
      velocity = 0;
      glide = 0;
    } else glide = requestAnimationFrame(tick);
    draw();
  };
  const aim = (index: number, snap: boolean) => {
    // How far the release's sticky version and date have travelled down
    // its entry (none where they don't stick).
    const shift = Math.max(
      0,
      metas[index].getBoundingClientRect().top -
        entries[index].getBoundingClientRect().top,
    );
    target = (centres[index] ?? 0) + shift;
    if (snap || motion.matches) {
      cancelAnimationFrame(glide);
      glide = 0;
      position = target;
      velocity = 0;
      draw();
      return;
    }
    if (!glide && position !== target) {
      last = performance.now();
      glide = requestAnimationFrame(tick);
    }
  };

  function update(snap = false) {
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

    let active = 0;
    for (let i = 1; i < entries.length; i++) {
      if (entries[i].getBoundingClientRect().top > readingLine) break;
      active = i;
    }
    aim(active, snap);
  }
  function schedule() {
    if (!frame) frame = requestAnimationFrame(() => update());
  }
  // A changed layout moves every stud: the knob follows at once.
  const relayout = () => {
    measure();
    update(true);
  };
  addEventListener("scroll", schedule, { passive: true });
  addEventListener("resize", relayout);
  addEventListener("hashchange", schedule);
  new ResizeObserver(relayout).observe(timeline);
  relayout();
  timeline.dataset.ready = "";

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
        const parts = [...card.querySelectorAll("li")];
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
