// A held title that names what passes under it (Section titleMotion
// "cycle": the homepage bento). Once the title has settled under the header
// and the content moves up under it, the title changes to the items' titles
// in turn: the first as the content starts to move, the last just before the
// next section's title comes up, each taking an equal share of the scroll
// between (sticky.ts measures both, --settle and --leave). Scrolling back
// past the start brings the section's own title back. motion.css fades it
// all out as the next section arrives.
//
// The change: the outgoing characters rise out of a blur, the incoming ones
// rise into place behind them one after another, each running briefly
// through the other characters of its own title before it settles, so a
// title never flashes words from another and every language decodes in its
// own script. When titles follow one another faster than a decoding takes
// (a quick scroll, though sticky.ts slows the bento's), the new one rises
// without decoding.
//
// The section's real heading stays where it is for assistive technology;
// the changing title is a decorative copy over it (aria-hidden). Without
// JavaScript, without motion, or before the content moves, the heading
// reads as written.

const reduced = matchMedia("(prefers-reduced-motion: reduce)");

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

const graphemes = (text: string) =>
  "Segmenter" in Intl
    ? Array.from(
        new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(
          text,
        ),
        (part) => part.segment,
      )
    : Array.from(text);

function setUp(section: HTMLElement) {
  const heading = section.querySelector<HTMLElement>(
    ":scope > .section-heading",
  );
  const title = heading?.querySelector<HTMLElement>(":scope > h2");
  const selector = section.dataset.cycle;
  if (!heading || !title || !selector) return;
  const sources = [...section.querySelectorAll<HTMLElement>(selector)];
  if (!sources.length) return;

  const stage = document.createElement("div");
  stage.className = "title-cycle";
  stage.setAttribute("aria-hidden", "true");
  heading.append(stage);

  const titles = sources.map((source) => (source.textContent ?? "").trim());
  let sectionTop = 0;
  function measure() {
    sectionTop = top(section);
    // Match the heading's type exactly.
    const style = getComputedStyle(title!);
    stage.style.font = style.font;
    stage.style.letterSpacing = style.letterSpacing;
    stage.style.top = `${title!.offsetTop}px`;
    stage.style.height = `${title!.offsetHeight}px`;
  }

  const length = (name: string) =>
    parseFloat(section.style.getPropertyValue(name));
  let current = -1;
  let frame = 0;
  function update() {
    frame = 0;
    // Scroll lengths on the section's timeline (cover 0: its top enters).
    const settle = length("--settle") + 20;
    const leave = length("--leave");
    const offset = scrollY - (sectionTop - innerHeight);
    let index = -1;
    if (Number.isFinite(settle) && Number.isFinite(leave)) {
      if (offset >= settle)
        index = Math.min(
          titles.length - 1,
          Math.floor(((offset - settle) / (leave - settle)) * titles.length),
        );
    } else if (section.classList.contains("is-held")) {
      index = 0;
    }
    if (index === current) return;
    current = index;
    show(index < 0 ? null : titles[index]);
  }

  let decoding = 0;
  let shownAt = -Infinity;
  function show(text: string | null) {
    const now = performance.now();
    const quick = now - shownAt < 320;
    shownAt = now;
    // The line on screen leaves upward; more than one leaving goes at once.
    const leaving = stage.querySelectorAll(".title-cycle-line.is-out");
    leaving.forEach((line, index) => {
      if (index < leaving.length - 1) line.remove();
    });
    const old = stage.querySelector<HTMLElement>(
      ".title-cycle-line:not(.is-out)",
    );
    if (old) {
      old.classList.add("is-out");
      setTimeout(() => old.remove(), 520);
    }
    cancelAnimationFrame(decoding);
    heading!.classList.toggle("is-cycling", text !== null);
    if (text === null) return;

    const line = document.createElement("span");
    line.className = "title-cycle-line";
    const letters = graphemes(text);
    // The title's own characters, for the decoding.
    const pool = [...new Set(letters.filter((letter) => letter.trim()))];
    const pick = () => pool[Math.floor(Math.random() * pool.length)] ?? "";
    const characters = letters.map((grapheme, index) => {
      const character = document.createElement("span");
      character.className = "title-cycle-char";
      character.style.setProperty("--i", String(Math.min(index, 16)));
      character.textContent = grapheme;
      line.append(character);
      return { element: character, final: grapheme, index };
    });
    stage.append(line);
    // A title wider than the heading (a phone, a long language) shrinks to
    // fit on one line.
    const room = stage.clientWidth;
    const wide = line.getBoundingClientRect().width;
    if (room && wide > room) line.style.scale = String(room / wide);
    // Each character keeps its final width while it decodes, so the line
    // never jitters.
    for (const character of characters)
      if (character.final.trim())
        character.element.style.width = `${character.element.getBoundingClientRect().width}px`;
    if (quick || pool.length < 2) return;
    const start = performance.now();
    const tick = (now: number) => {
      let busy = false;
      for (const character of characters) {
        if (!character.final.trim()) continue;
        const settleAt = 110 + Math.min(character.index, 16) * 28;
        if (now - start < settleAt) {
          busy = true;
          // A new character every 45 ms until it settles.
          if (
            Math.floor((now - start) / 45) !==
            Number(character.element.dataset.step)
          ) {
            character.element.dataset.step = String(
              Math.floor((now - start) / 45),
            );
            character.element.textContent = pick();
          }
        } else if (character.element.textContent !== character.final) {
          character.element.textContent = character.final;
        }
      }
      if (busy) decoding = requestAnimationFrame(tick);
    };
    decoding = requestAnimationFrame(tick);
  }

  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(update);
  };
  addEventListener("scroll", schedule, { passive: true });
  // sticky.ts measures again on resizes and font loads.
  new MutationObserver(schedule).observe(section, {
    attributes: true,
    attributeFilter: ["class", "style"],
  });
  let timer = 0;
  const remeasure = () => {
    clearTimeout(timer);
    timer = window.setTimeout(() => {
      measure();
      schedule();
    }, 120);
  };
  addEventListener("resize", remeasure);
  addEventListener("load", remeasure);
  document.fonts?.ready.then(remeasure);
  measure();
  schedule();
}

if (!reduced.matches) {
  document
    .querySelectorAll<HTMLElement>('.section-sticky[data-title="cycle"]')
    .forEach(setUp);
}

export {};
