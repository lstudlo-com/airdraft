// Scroll storytelling for the homepage, built on GSAP and ScrollTrigger.
//
//   headings  and bento tiles rise into place as they enter, where the
//             browser has no scroll timelines (motion.css does it elsewhere)
//   bento     each tile's graphic plays a short loop while it is on screen
//   pipeline  on desktop the section pins: one card stays in place while
//             its scenes cross-fade and a selection well steps through each
//             scene's providers; on narrow screens the cards rise into place
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
    ...all(".section-heading:not(.story-intro)"),
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

/** Desktop: pin the pipeline. One raised card stays in place on the right;
 *  each scene holds while its selection well steps row by row through the
 *  providers (or the vocabulary fix plays), then the next scene cross-fades
 *  in. The well moves on the app's selection curve (CSS) whenever the
 *  scrubbed position reaches a new row, and its check island follows. */
function pipeline() {
  const story = one("[data-story]");
  if (!story) return;
  const cards = all("[data-scene-card]", story);
  const copies = all("[data-scene-copy]", story);
  const stages = all("[data-stage]", story).map((stage) => ({
    element: stage,
    fill: one("[data-stage-fill]", stage),
    range: JSON.parse(stage.dataset.range ?? "[0,0]") as [number, number],
  }));
  const lists = cards.map((card) => {
    const list = one(".choices", card);
    return {
      list,
      rows: list ? all("li", list) : [],
      position: { w: 0 },
      selected: 0,
    };
  });
  const deck = one("[data-deck]", story);
  const steps = all(".story-stages li", story);
  const intro = 0.9;
  const hold = 1.1;
  const move = 1;
  story.style.setProperty(
    "--units",
    String(intro + cards.length * hold + (cards.length - 1) * move),
  );
  story.classList.add("is-pinned");

  const state = { t: 0 };
  let active = -1;
  const render = () => {
    const t = state.t;
    for (const stage of stages) {
      const [first, last] = stage.range;
      const progress = gsap.utils.clamp(
        0,
        1,
        (t - first + 1) / (last - first + 1),
      );
      if (stage.fill) stage.fill.style.transform = `scaleX(${progress})`;
    }
    for (const entry of lists) {
      if (!entry.list) continue;
      const selected = Math.round(entry.position.w);
      if (selected === entry.selected) continue;
      entry.selected = selected;
      entry.list.style.setProperty("--sel", String(selected));
      entry.rows.forEach((row, index) =>
        row.classList.toggle("is-selected", index === selected),
      );
    }
    const current = Math.round(t);
    if (current === active) return;
    active = current;
    cards.forEach((card, index) => {
      card.classList.toggle("is-active", index === current);
      card.classList.toggle("is-past", index < current);
    });
    copies.forEach((copy, index) =>
      copy.classList.toggle("is-active", index === current),
    );
    stages.forEach(({ element, range }) =>
      element.classList.toggle(
        "is-active",
        current >= range[0] && current <= range[1],
      ),
    );
  };

  const fix = cards.find((card) => one(".fix", card));
  if (fix) gsap.set(fix, { "--fix": 0 });
  render();

  const timeline = gsap.timeline({
    onUpdate: render,
    scrollTrigger: {
      trigger: story,
      start: "top top",
      end: "bottom bottom",
      scrub: 0.7,
    },
  });
  // The story opens with its three steps rising in turn, then the card rises
  // out of the island with the first scene: it grows to full size while
  // --deck-depth (motion.css) lifts its shadow from flat to raised.
  timeline.from(steps, {
    autoAlpha: 0,
    y: 12,
    duration: 0.3,
    stagger: 0.2,
    ease: "power2.out",
  });
  if (deck) {
    timeline.fromTo(
      deck,
      { "--deck-depth": 1, scale: 0.94, autoAlpha: 0, y: 40 },
      {
        "--deck-depth": 0,
        scale: 1,
        autoAlpha: 1,
        y: 0,
        duration: 0.6,
        ease: "power2.out",
      },
      intro - 0.6,
    );
  }
  cards.forEach((card, index) => {
    const { list, rows, position } = lists[index];
    if (card === fix) {
      timeline.to(card, { "--fix": 1, duration: hold, ease: "none" });
    } else if (list) {
      timeline.to(position, {
        w: Math.max(0, rows.length - 1),
        duration: hold,
        ease: "none",
      });
    }
    if (index < cards.length - 1) {
      timeline.to(state, {
        t: index + 1,
        duration: move,
        ease: "power2.inOut",
      });
      // The card dips into the island and rises again between scenes.
      if (deck) {
        timeline.to(
          deck,
          {
            "--deck-depth": 0.45,
            scale: 0.973,
            duration: move / 2,
            ease: "sine.inOut",
            yoyo: true,
            repeat: 1,
          },
          "<",
        );
      }
    }
  });
  ScrollTrigger.refresh();

  return () => {
    story.classList.remove("is-pinned");
    story.style.removeProperty("--units");
    for (const element of [
      ...cards,
      ...copies,
      ...stages.map((stage) => stage.element),
    ]) {
      element.classList.remove("is-active", "is-past");
    }
    for (const { list, rows } of lists) {
      list?.style.removeProperty("--sel");
      rows.forEach((row, index) =>
        row.classList.toggle("is-selected", index === 0),
      );
    }
    gsap.set(cards, { clearProps: "all" });
    if (deck) gsap.set(deck, { clearProps: "all" });
    gsap.set(steps, { clearProps: "all" });
    stages.forEach(({ fill }) => fill?.style.removeProperty("transform"));
  };
}

/** Narrow screens: the stacked cards rise into place as they arrive. */
function sceneReveals() {
  for (const card of all("[data-scene-card]")) {
    gsap.from(card, {
      y: 48,
      autoAlpha: 0,
      duration: 0.9,
      ease: "power3.out",
      scrollTrigger: { trigger: card, start: "top 92%" },
    });
  }
}

const media = gsap.matchMedia();
media.add(
  {
    motion: "(prefers-reduced-motion: no-preference)",
    desktop: "(min-width: 1000px) and (min-height: 700px)",
  },
  (context) => {
    const { motion, desktop } = context.conditions as Record<string, boolean>;
    if (!motion) return;
    const cleanups = [desktop ? pipeline() : sceneReveals()];
    // motion.css raises these from the scroll position where it can.
    if (!CSS.supports("animation-timeline: view()")) reveals();
    bento();
    return () => cleanups.forEach((cleanup) => cleanup?.());
  },
);
