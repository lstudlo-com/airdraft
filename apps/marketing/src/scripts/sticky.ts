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
//              title comes up into the window. A title with `titleMotion`
//              (Section.astro) leaves from one of them (motion.css).
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

  // Natural positions: sticky boxes measured where they sit in the flow.
  root.classList.add("sticky-measure");
  const sectionTop = top(section);
  const headingTop = top(heading);
  // The scroll length, from cover 0, at which the title settles.
  const settle = headingTop - header - sectionTop + view;
  section.style.setProperty("--settle", `${Math.round(settle)}px`);
  // The next section's title reaches the window's foot a little after this.
  const next = section.nextElementSibling as HTMLElement | null;
  const leave = next
    ? Math.max(settle + 200, top(next) - sectionTop - view * 0.06)
    : settle + 100000;
  section.style.setProperty("--leave", `${Math.round(leave)}px`);

  // Pin the stage if it fits under the settled title.
  let pinTop = 0;
  let pinned = false;
  if (stage && motion && innerWidth > 1000) {
    pinTop = Math.round(top(stage) - headingTop + header);
    pinned = pinTop + stage.offsetHeight + 16 <= view;
  }
  section.classList.toggle("is-pinned", pinned);
  if (pinned) section.style.setProperty("--pin-top", `${pinTop}px`);

  // Each item rises in order, a step after the one before.
  const lead = settle - px(section, "--follow-lead", 260);
  let previous = -Infinity;
  const arrivals: number[] = [];
  for (const item of section.querySelectorAll<HTMLElement>(items)) {
    const entry = top(item) - sectionTop + view * 0.1;
    const arrival = Math.round(Math.max(lead, entry, previous));
    item.style.setProperty("--in", `${arrival}px`);
    arrivals.push(arrival);
    previous = arrival + px(item, "--follow-step", 70);
  }

  if (runway && stage && arrivals.length) {
    const first = arrivals[0];
    const last = arrivals[arrivals.length - 1];
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
