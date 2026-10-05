// Scroll storytelling for the homepage, built on GSAP and ScrollTrigger.
//
//   headings  and bento tiles rise into place as they enter, where the
//             browser has no scroll timelines (motion.css does it elsewhere)
//   bento     each tile's graphic plays a short loop while it is on screen,
//             as does the pipeline board's vocabulary fix
//
// Every element's resting state in CSS is its final state, so the page reads
// the same without JavaScript. With reduced motion none of this runs.
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { settleIsland } from "./island";

gsap.registerPlugin(ScrollTrigger);
// Trigger positions are measured with the page island fully held, the
// layout everywhere past the first scroll (src/scripts/island.ts).
ScrollTrigger.addEventListener("refreshInit", () => settleIsland(true));
ScrollTrigger.addEventListener("refresh", () => settleIsland(false));

const all = <T extends Element = HTMLElement>(
  selector: string,
  root: ParentNode = document,
) => [...root.querySelectorAll<T & Element>(selector)] as T[];
const one = <T extends Element = HTMLElement>(
  selector: string,
  root: ParentNode = document,
) => root.querySelector(selector) as T | null;

/** Wrap each word in a span so words can be typed in one by one. Hidden
 *  words are removed from layout, so the caret follows the typed text. */
function words(paragraph: HTMLElement) {
  const caret = one(".caret", paragraph);
  const text = paragraph.textContent?.trim() ?? "";
  paragraph.replaceChildren(
    ...text.split(/\s+/).map((word, index) => {
      const span = document.createElement("span");
      span.textContent = index ? ` ${word}` : word;
      return span;
    }),
  );
  if (caret) paragraph.append(caret);
  return all<HTMLElement>("span:not(.caret)", paragraph);
}

function reveals() {
  const targets = [
    ...all(".section-heading"),
    ...all("[data-reveal]"),
    ...all("[data-preview]"),
  ];
  for (const target of targets) {
    gsap.from(target, {
      y: 36,
      autoAlpha: 0,
      duration: 0.9,
      ease: "power3.out",
      scrollTrigger: { trigger: target, start: "top 88%" },
    });
  }
  // Flat rises only: a lit card never tips through perspective.
  all("[data-offer]").forEach((offer, index) => {
    gsap.from(offer, {
      y: 40,
      autoAlpha: 0,
      duration: 0.9,
      delay: index * 0.08,
      ease: "power3.out",
      scrollTrigger: { trigger: offer, start: "top 92%" },
    });
  });
  all(".bento .tile").forEach((tile, index) => {
    gsap.from(tile, {
      y: 48,
      autoAlpha: 0,
      duration: 0.9,
      delay: (index % 3) * 0.08,
      ease: "power3.out",
      scrollTrigger: { trigger: tile, start: "top 90%" },
    });
  });
}

/** Loop a tile's graphic only while the tile is on screen. */
function loop(art: HTMLElement, build: (timeline: gsap.core.Timeline) => void) {
  const timeline = gsap.timeline({ repeat: -1, paused: true });
  build(timeline);
  ScrollTrigger.create({
    trigger: art,
    start: "top bottom",
    end: "bottom top",
    onToggle: (self) => (self.isActive ? timeline.play() : timeline.pause()),
  });
}

const arts: Record<
  string,
  (art: HTMLElement, timeline: gsap.core.Timeline) => void
> = {
  cursor(art, timeline) {
    const typed = words(one("[data-typed]", art)!);
    const label = one("[data-hud-label]", art)!;
    const bars = all(".hud-bars span", art);
    const clock = { seconds: 0 };
    timeline
      .set(typed, { display: "none" })
      .set(clock, { seconds: 0 })
      .to(clock, {
        seconds: 2.4,
        duration: 1.8,
        ease: "none",
        onUpdate: () => {
          label.textContent = `0:0${clock.seconds.toFixed(1)}`;
        },
      })
      .to(
        bars,
        {
          "--level": () => gsap.utils.random(0.2, 1),
          duration: 0.16,
          repeat: 10,
          repeatRefresh: true,
          ease: "sine.inOut",
          stagger: 0.01,
        },
        "<",
      )
      .call(() => {
        label.textContent = "Refining";
      })
      .to(bars, { "--level": 0.14, duration: 0.3 })
      .to(typed, { display: "inline", duration: 0, stagger: 0.09 }, "+=0.4")
      .to({}, { duration: 2.2 })
      .to(typed, { autoAlpha: 0, duration: 0.35 })
      .set(typed, { display: "none", autoAlpha: 1 });
  },
  shortcut(art, timeline) {
    const keys = one(".keys", art)!;
    timeline
      .to({}, { duration: 0.8 })
      .call(() => keys.classList.add("is-pressed"))
      .to({}, { duration: 1.8 })
      .call(() => keys.classList.remove("is-pressed"))
      .to({}, { duration: 1 });
  },
  profiles(art, timeline) {
    const holder = one(".art-profiles", art)!;
    const outputs: string[] = JSON.parse(holder.dataset.outputs ?? "[]");
    const items = all("li:not(.segmented-thumb)", art);
    const output = one("[data-output]", art)!;
    [1, 2, 3, 0].forEach((index) => {
      timeline
        .to({}, { duration: 1.6 })
        .to(output, { autoAlpha: 0, y: -6, duration: 0.22 })
        .call(() => {
          items.forEach((item, position) =>
            item.classList.toggle("is-selected", position === index),
          );
          output.textContent = outputs[index];
        })
        .fromTo(
          output,
          { y: 6 },
          { autoAlpha: 1, y: 0, duration: 0.35, ease: "power2.out" },
        );
    });
  },
  vocabulary(art, timeline) {
    const wrong = one("[data-wrong]", art)!;
    const right = one("[data-right]", art)!;
    timeline
      .set(wrong, { "--strike": 0 })
      .set(right, { autoAlpha: 0, scale: 0.8 })
      .to({}, { duration: 0.8 })
      .to(wrong, { "--strike": 1, duration: 0.5, ease: "power2.inOut" })
      .to(right, {
        autoAlpha: 1,
        scale: 1,
        duration: 0.55,
        ease: "back.out(2.2)",
      })
      .to({}, { duration: 2 })
      .to(right, { autoAlpha: 0, duration: 0.3 });
  },
  history(art, timeline) {
    const deck = one(".art-deck", art)!;
    const texts: string[] = JSON.parse(deck.dataset.texts ?? "[]");
    const items = all(".art-toggle li:not(.segmented-thumb)", art);
    const text = one("[data-history]", art)!;
    const flip = (index: number) => () => {
      items.forEach((item, position) =>
        item.classList.toggle("is-selected", position === index),
      );
      text.textContent = texts[index];
      gsap.fromTo(
        text,
        { autoAlpha: 0, y: 4 },
        { autoAlpha: 1, y: 0, duration: 0.3 },
      );
    };
    timeline
      .to({}, { duration: 1.6 })
      .call(flip(1))
      .to({}, { duration: 2 })
      .call(flip(0));
  },
  fallback(art, timeline) {
    const status = one("[data-status]", art)!;
    const dot = one(".status-dot", art)!;
    const chip = status.parentElement!;
    const typed = words(one("[data-typed]", art)!);
    timeline
      .set(typed, { display: "none" })
      .call(() => {
        status.textContent = "Refining…";
        dot.dataset.tone = "busy";
      })
      .to({}, { duration: 1.3 })
      .call(() => {
        status.textContent = "Refinement failed";
        dot.dataset.tone = "attention";
      })
      .to(chip, { x: -3, duration: 0.05, repeat: 5, yoyo: true })
      .to(typed, { display: "inline", duration: 0, stagger: 0.08 }, "+=0.2")
      .to({}, { duration: 2 })
      .to(typed, { autoAlpha: 0, duration: 0.35 })
      .set(typed, { display: "none", autoAlpha: 1 });
  },
  fix(art, timeline) {
    // The heard words are struck out and the dictionary's spelling rises in.
    const fix = one(".fix", art)!;
    const sentence = one("p", art)!;
    timeline
      .set(fix, { "--fix": 0 })
      .to({}, { duration: 1 })
      .to(fix, { "--fix": 1, duration: 1.3, ease: "none" })
      .to({}, { duration: 2.6 })
      .to(sentence, { autoAlpha: 0, duration: 0.3 })
      .set(fix, { "--fix": 0 })
      .to(sentence, { autoAlpha: 1, duration: 0.3 });
  },
  privacy(art, timeline) {
    // A signal travels from the microphone to the caret without leaving the Mac.
    all("[data-dot]", art).forEach((dot, index) => {
      const start = index * 0.6;
      timeline
        .fromTo(
          dot,
          { left: "0%" },
          { left: "100%", duration: 0.6, ease: "none" },
          start,
        )
        .fromTo(dot, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.12 }, start)
        .to(dot, { autoAlpha: 0, duration: 0.12 }, start + 0.48);
    });
    timeline.to({}, { duration: 0.9 });
  },
};

function bento() {
  for (const art of all("[data-art]")) {
    const build = arts[art.dataset.art ?? ""];
    if (build) loop(art, (timeline) => build(art, timeline));
  }
}

const media = gsap.matchMedia();
media.add("(prefers-reduced-motion: no-preference)", () => {
  // motion.css raises these from the scroll position where it can.
  if (!CSS.supports("animation-timeline: view()")) reveals();
  bento();
});
