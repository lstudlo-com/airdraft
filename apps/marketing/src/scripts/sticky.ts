// Sticky story sections (components/ui/Section.astro `sticky`): the title
// holds one header height below the site header while the content scrolls
// up under it (global.css). This script measures, for each such section,
// the scroll lengths its CSS animations run over, all on the section's own
// view timeline (--sticky, where cover 0 is the moment the section's top
// enters the window):
//
//   --in       on each item (data-follow, bento tiles, Transcribe beats,
//              provider cards): when it starts to rise. Items arrive in
//              order, a step apart, never before the title is about to
//              settle and never before they come up into the window.
//   pinning    a story stage ([data-pin]) that fits under the settled title
//              pins there (.is-pinned, --pin-top) while its runway
//              ([data-pin-runway]) scrolls past.
//   --story-0, --story-1
//              on the section: the scroll the story runs over, the runway
//              while pinned, or from the first item's arrival to past the
//              last's when not.
//   .is-held   on the section while its title rests under the header, so
//              the title's blur band (global.css) shows only then.
//   --settle, --leave
//              on the section: the scroll length at which its title settles
//              under the header, and the one at which the next section's
//              title comes up into the window, as the visitor leaves the
//              section. A title with `titleMotion` (Section.astro) holds
//              while its content plays and leaves from --leave (motion.css).
//   slowing    a section with `data-slow` (Section `slow`) moves its content
//              (the element after the heading) slower than the scroll from
//              the moment its first item starts to rise until the visitor
//              leaves it: the speed eases down to that share, holds, and
//              eases back to the scroll's own before the next section comes
//              up. The scroll reading the section grows by --slow-extra, a
//              space after the content, which the content moves down into
//              (.is-slowed, --slow-0, --slow-1, --slow-ease: motion.css), so
//              everything after the section stays where it was. Items arrive
//              and the title leaves where they would without it, on screen.
//
// Only lengths inside each section are measured, so nothing above it
// changes them; they are measured again when the window changes size or the
// fonts arrive. Without scroll timelines, or with reduced motion, nothing
// pins and the CSS fallbacks apply.
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const timelines = CSS.supports("animation-timeline: view()");
const items =
  ":is([data-follow], .bento > .tile, .ts-beat, .pipe-stage):not([data-follow] *)";

const px = (element: Element, property: string, fallback: number) => {
  const value = parseFloat(
    getComputedStyle(element).getPropertyValue(property),
  );
  return Number.isFinite(value) ? value : fallback;
};

// Layout position in the document, unaffected by transforms (the island's
// opening hold) or by animations' translate.
const top = (element: HTMLElement) => {
  let y = 0;
  for (
    let node: HTMLElement | null = element;
    node;
    node = node.offsetParent as HTMLElement | null
  )
    y += node.offsetTop;
  return y;
};

// The next section in the flow (scripts and other boxless siblings skipped).
function following(section: HTMLElement) {
  let next = section.nextElementSibling;
  while (next && !(next instanceof HTMLElement && next.offsetHeight > 0))
    next = next.nextElementSibling;
  return next as HTMLElement | null;
}

const smoothstep = (t: number) => {
  const c = Math.min(1, Math.max(0, t));
  return c * c * (3 - 2 * c);
};

// The slowing (see above), between two scroll lengths of the unslowed
// section: from `from`, where the first item starts to rise, to `to`, where
// the visitor leaves. `share` is the speed it eases down to. Returns how far
// the content has been held back after each unslowed length (`held`), the
// space that adds, and the CSS easing that holds it back on the scroll.
function slowing(from: number, to: number, share: number, view: number) {
  const ramp = Math.min(view * 0.32, (to - from) / 4);
  const speed = (y: number) =>
    1 -
    (1 - share) *
      Math.min(smoothstep((y - from) / ramp), smoothstep((to - y) / ramp));
  const steps = 240;
  const step = (to - from) / steps;
  const lengths = [from];
  const holds = [0];
  for (let i = 1; i <= steps; i++) {
    const y = from + i * step;
    const middle = y - step / 2;
    lengths.push(y);
    holds.push(holds[i - 1] + (1 / speed(middle) - 1) * step);
  }
  const extra = holds[steps];
  const held = (y: number) => {
    if (y <= from) return 0;
    if (y >= to) return extra;
    const i = Math.min(steps - 1, Math.floor((y - from) / step));
    const t = (y - lengths[i]) / step;
    return holds[i] + (holds[i + 1] - holds[i]) * t;
  };
  // The easing maps the scroll's progress through the slowing (the unslowed
  // length plus what has been held back) to the share of --slow-extra held.
  const span = to - from + extra;
  const points: string[] = [];
  for (let i = 0; i <= steps; i += 8) {
    const progress = ((lengths[i] - from + holds[i]) / span) * 100;
    points.push(`${(holds[i] / extra).toFixed(4)} ${progress.toFixed(3)}%`);
  }
  return { extra, held, ease: `linear(${points.join(", ")})` };
}

function measure(section: HTMLElement) {
  const root = document.documentElement;
  const view = innerHeight;
  const header = px(root, "--header", 72);
  const heading = section.querySelector<HTMLElement>(
    ":scope > .section-heading",
  )!;
  const stage = section.querySelector<HTMLElement>("[data-pin]");
  const runway = section.querySelector<HTMLElement>("[data-pin-runway]");
  const motion = timelines && !reduced.matches;
  const share = parseFloat(section.dataset.slow ?? "");
  const slow = motion && share > 0 && share < 1;

  // Natural positions: sticky boxes measured where they sit in the flow,
  // and no space added for a slowing.
  root.classList.add("sticky-measure");
  section.style.setProperty("--slow-extra", "0px");
  const sectionTop = top(section);
  const headingTop = top(heading);
  // The scroll length, from cover 0, at which the title settles.
  const settle = headingTop - header - sectionTop + view;
  section.style.setProperty("--settle", `${Math.round(settle)}px`);

  // Pin the stage if it fits under the settled title. Its runway then adds
  // to the section, so this comes before anything below it is measured.
  let pinTop = 0;
  let pinned = false;
  if (stage && motion && innerWidth > 1000) {
    pinTop = Math.round(top(stage) - headingTop + header);
    pinned = pinTop + stage.offsetHeight + 16 <= view;
  }
  section.classList.toggle("is-pinned", pinned);
  if (pinned) section.style.setProperty("--pin-top", `${pinTop}px`);

  // The visitor leaves as the next section's title comes up into the
  // window: its top a little above the window's foot.
  const next = following(section);
  let leave = next
    ? Math.max(settle + 200, top(next) - sectionTop - view * 0.06)
    : settle + 100000;

  // Each item rises in order, a step after the one before.
  const lead = settle - px(section, "--follow-lead", 260);
  let previous = -Infinity;
  const list = [...section.querySelectorAll<HTMLElement>(items)];
  const arrivals: number[] = [];
  for (const item of list) {
    const entry = top(item) - sectionTop + view * 0.1;
    const arrival = Math.max(lead, entry, previous);
    arrivals.push(arrival);
    previous = arrival + px(item, "--follow-step", 70);
  }

  // Slow the content from the first item's arrival until the visitor
  // leaves; what arrives meanwhile arrives where it would on screen.
  let held = (_: number) => 0;
  section.classList.remove("is-slowed");
  if (slow && arrivals.length && leave - arrivals[0] > 600) {
    const from = arrivals[0];
    const slowed = slowing(from, leave, share, view);
    held = slowed.held;
    section.style.setProperty("--slow-extra", `${Math.round(slowed.extra)}px`);
    section.style.setProperty("--slow-0", `${Math.round(from)}px`);
    section.style.setProperty(
      "--slow-1",
      `${Math.round(leave + slowed.extra)}px`,
    );
    section.style.setProperty("--slow-ease", slowed.ease);
    section.classList.add("is-slowed");
    leave += slowed.extra;
  }
  section.style.setProperty("--leave", `${Math.round(leave)}px`);
  const shown = arrivals.map((arrival) => Math.round(arrival + held(arrival)));
  list.forEach((item, index) =>
    item.style.setProperty("--in", `${shown[index]}px`),
  );

  if (runway && stage && shown.length) {
    const first = shown[0];
    const last = shown[shown.length - 1];
    let from: number;
    let to: number;
    if (pinned) {
      const release =
        top(runway) +
        runway.offsetHeight -
        stage.offsetHeight -
        pinTop -
        sectionTop +
        view;
      from = Math.max(settle + 40, last + 160);
      to = Math.max(from + 200, release - view * 0.12);
    } else {
      from = first + 160;
      to = Math.max(last + 460, from + 400);
    }
    section.style.setProperty("--story-0", `${Math.round(from)}px`);
    section.style.setProperty("--story-1", `${Math.round(to)}px`);
  }
  root.classList.remove("sticky-measure");
}

// Held: the title's box rests at the header's foot. Approaching, it sits
// lower; at the section's end the section pushes it up past the header.
function hold(section: HTMLElement) {
  const heading = section.querySelector<HTMLElement>(
    ":scope > .section-heading",
  )!;
  const header = px(document.documentElement, "--header", 72);
  const offset = heading.getBoundingClientRect().top - header;
  section.classList.toggle("is-held", Math.abs(offset) < 1);
}

const sections = [...document.querySelectorAll<HTMLElement>(".section-sticky")];
if (sections.length) {
  // Scroll events arrive once per frame, after layout, so reading three
  // boxes here costs no extra layout.
  const held = () => sections.forEach(hold);
  addEventListener("scroll", held, { passive: true });
  const all = () => {
    sections.forEach(measure);
    held();
  };
  let timer = 0;
  const later = () => {
    clearTimeout(timer);
    timer = window.setTimeout(all, 120);
  };
  all();
  addEventListener("resize", later);
  addEventListener("load", all);
  // A page restored from the back/forward cache may have a new window size.
  addEventListener("pageshow", (event) => event.persisted && all());
  document.fonts?.ready.then(all);
  reduced.addEventListener("change", all);
}

export {};
