// Homepage flourishes that answer the visitor rather than tell the story:
//
//   headings   section headings rise word by word (character pairs in
//              Chinese and Japanese) as they come into view, once
//   content    the content under them rises the same way, block by block:
//              guide tiles, guide and text-page sections, pricing questions and changelog cards.
//              Blocks that come into view together rise one after another.
//              Blocks the scroll timelines already raise (everything under a
//              homepage title, offers) are left to motion.css; pricing plans stay still
//   depth      the hero card and the copy above it drift a few pixels with
//              the pointer, the card toward it and the copy away, so the
//              raised card reads closer than the text. Translation only:
//              the light stays at the top left, nothing tilts
//
// Resting CSS is the final state, so without JavaScript every heading reads
// whole and nothing moves. With reduced motion none of this runs.
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const finePointer = matchMedia("(hover: hover) and (pointer: fine)");

function headings() {
  const targets = [
    ...document.querySelectorAll<HTMLElement>(".section-heading > :is(h2, h1)"),
  ];
  const watcher = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add("is-in");
        watcher.unobserve(entry.target);
      }
    },
    { rootMargin: "0px 0px -12% 0px" },
  );
  for (const heading of targets) {
    if (heading.children.length) continue;
    const text = heading.textContent ?? "";
    const cjk = /^(ja|zh)/.test(
      heading.closest("[lang]")?.getAttribute("lang") ?? "",
    );
    const parts = cjk
      ? Array.from(text.trim()).reduce<string[]>((chunks, char, index) => {
          if (index % 2 === 0) chunks.push(char);
          else chunks[chunks.length - 1] += char;
          return chunks;
        }, [])
      : (text.trim().match(/\S+\s*/g) ?? []);
    heading.setAttribute("aria-label", text.trim());
    heading.replaceChildren(
      ...parts.map((part, index) => {
        const word = document.createElement("span");
        word.className = "reveal-word";
        word.setAttribute("aria-hidden", "true");
        word.style.setProperty("--i", String(index));
        word.textContent = part;
        return word;
      }),
    );
    heading.classList.add("reveal-words");
    watcher.observe(heading);
  }
}

// Content blocks that rise like the headings above them.
const contentBlocks = [
  ".guide-pick",
  ".guide-section",
  ".guide-breadcrumbs",
  ".guide-hub-note",
  ".guide-actions",
  ".question-list",
  ".release-body",
].join(", ");

function content() {
  // On the homepage motion.css raises these from the scroll, behind their
  // titles, where it can.
  const scrolled = CSS.supports("animation-timeline: view()");
  const blocks = [
    ...document.querySelectorAll<HTMLElement>(contentBlocks),
  ].filter((block) => !(scrolled && block.closest(".home")));
  const watcher = new IntersectionObserver(
    (entries) => {
      // Blocks arriving in the same frame rise in reading order, a step
      // apart; one arriving alone rises at once.
      entries
        .filter((entry) => entry.isIntersecting)
        .map((entry) => entry.target as HTMLElement)
        .sort((a, b) =>
          a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING
            ? -1
            : 1,
        )
        .forEach((block, index) => {
          block.style.setProperty("--i", String(Math.min(index, 6)));
          block.classList.add("is-in");
          watcher.unobserve(block);
        });
    },
    { rootMargin: "0px 0px -10% 0px" },
  );
  for (const block of blocks) {
    block.classList.add("reveal-block");
    watcher.observe(block);
    // Once risen, the block gets its own transitions back.
    const settle = (event: TransitionEvent) => {
      if (event.target !== block || event.propertyName !== "translate") return;
      block.classList.remove("reveal-block", "is-in");
      block.style.removeProperty("--i");
      block.removeEventListener("transitionend", settle);
    };
    block.addEventListener("transitionend", settle);
  }
}

function depth() {
  const hero = document.querySelector<HTMLElement>("[data-hero]");
  if (!hero) return;
  const target = { x: 0, y: 0 };
  const current = { x: 0, y: 0 };
  let frame = 0;
  const step = () => {
    current.x += (target.x - current.x) * 0.08;
    current.y += (target.y - current.y) * 0.08;
    hero.style.setProperty("--px", current.x.toFixed(4));
    hero.style.setProperty("--py", current.y.toFixed(4));
    frame =
      Math.abs(target.x - current.x) + Math.abs(target.y - current.y) > 0.001
        ? requestAnimationFrame(step)
        : 0;
  };
  const aim = (x: number, y: number) => {
    target.x = x;
    target.y = y;
    if (!frame) frame = requestAnimationFrame(step);
  };
  hero.addEventListener("pointermove", (event) => {
    if (event.pointerType !== "mouse" || !finePointer.matches) return;
    const box = hero.getBoundingClientRect();
    aim(
      ((event.clientX - box.left) / box.width) * 2 - 1,
      ((event.clientY - box.top) / box.height) * 2 - 1,
    );
  });
  hero.addEventListener("pointerleave", () => aim(0, 0));
}

if (!reduced.matches) {
  document.documentElement.classList.add("flourish");
  headings();
  content();
  depth();
}

export {};
