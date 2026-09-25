// Scroll storytelling for the homepage, built on GSAP and ScrollTrigger.
//
//   hero      the 3D icon tilts toward the pointer; on scroll it orbits,
//             sinks and falls behind the headline (parallax)
//   headings  and bento tiles rise into place as they enter
//   bento     each tile's graphic plays a short loop while it is on screen
//   pipeline  on desktop the section pins and flies six cards through 3D
//             space; on narrow screens the cards tip up into place
//
// Every element's resting state in CSS is its final state, so the page reads
// the same without JavaScript. With reduced motion none of this runs.
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";

gsap.registerPlugin(ScrollTrigger);

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

function hero(fine: boolean) {
  const section = one("[data-hero]");
  const plateau = one("[data-plateau]");
  if (!section || !plateau) return;
  gsap.set(plateau, { "--tp": 0, "--xp": 0, "--ts": 0, "--xs": 0 });

  // Orbit and sink as the hero scrolls away; the copy moves a little faster.
  gsap
    .timeline({
      scrollTrigger: {
        trigger: section,
        start: "top top",
        end: "+=900",
        scrub: 0.8,
      },
    })
    .to(
      plateau,
      { "--ts": 22, "--xs": 14, y: 220, scale: 0.88, ease: "none" },
      0,
    )
    .to(one("[data-hero-copy]"), { y: -50, ease: "none" }, 0);

  if (!fine) return;
  const twist = gsap.quickTo(plateau, "--tp", { duration: 1, ease: "power3" });
  const tilt = gsap.quickTo(plateau, "--xp", { duration: 1, ease: "power3" });
  const move = (event: PointerEvent) => {
    const bounds = section.getBoundingClientRect();
    twist(((event.clientX - bounds.left) / bounds.width - 0.5) * 12);
    tilt(-((event.clientY - bounds.top) / bounds.height - 0.5) * 10);
  };
  const leave = () => {
    twist(0);
    tilt(0);
  };
  section.addEventListener("pointermove", move);
  section.addEventListener("pointerleave", leave);
  return () => {
    section.removeEventListener("pointermove", move);
    section.removeEventListener("pointerleave", leave);
  };
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
  all("[data-offer]").forEach((offer, index) => {
    gsap.from(offer, {
      y: 60,
      rotateX: -16,
      autoAlpha: 0,
      transformPerspective: 1000,
      transformOrigin: "50% 100%",
      duration: 1,
      delay: index * 0.1,
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
    const items = all("li", art);
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
    const items = all(".art-toggle li", art);
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
    const typed = words(one("[data-typed]", art)!);
    timeline
      .set(typed, { display: "none" })
      .call(() => {
        status.textContent = "Refining…";
      })
      .to({}, { duration: 1.3 })
      .call(() => {
        status.textContent = "Refinement failed";
      })
      .to(status, { x: -3, duration: 0.05, repeat: 5, yoyo: true })
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

/** Desktop: pin the pipeline and fly its cards through 3D space. Each scene
 *  holds while its picker wheel turns through the names (or the vocabulary
 *  fix plays), then the card flies past to the lower left as the next one
 *  hops forward from the queue in the upper right. The pointer tilts the
 *  whole deck. */
function pipeline(fine: boolean) {
  const story = one("[data-story]");
  const deck = one("[data-deck]", story ?? document);
  if (!story || !deck) return;
  const cards = all("[data-scene-card]", story);
  const copies = all("[data-scene-copy]", story);
  const stages = all("[data-stage]", story).map((stage) => ({
    element: stage,
    fill: one("[data-stage-fill]", stage),
    range: JSON.parse(stage.dataset.range ?? "[0,0]") as [number, number],
  }));
  const hold = 1.1;
  const move = 1;
  story.style.setProperty(
    "--units",
    String(cards.length * hold + (cards.length - 1) * move),
  );
  story.classList.add("is-pinned");

  const state = { t: 0 };
  let active = -1;
  const render = () => {
    const t = state.t;
    deck.style.setProperty("--t", t.toFixed(4));
    cards.forEach((card, index) => {
      card.classList.toggle("is-away", t - index > 1 || index - t > 3.4);
    });
    for (const stage of stages) {
      const [first, last] = stage.range;
      const progress = gsap.utils.clamp(
        0,
        1,
        (t - first + 1) / (last - first + 1),
      );
      if (stage.fill) stage.fill.style.transform = `scaleX(${progress})`;
    }
    const current = Math.round(t);
    if (current === active) return;
    active = current;
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

  gsap.set(cards, { "--w": 0 });
  const fix = cards.find((card) => one(".fix", card));
  if (fix) gsap.set(fix, { "--fix": 0 });
  render();

  // The queue flies forward as the section scrolls into view.
  gsap.fromTo(
    deck,
    { "--enter": 0 },
    {
      "--enter": 1,
      ease: "power2.out",
      scrollTrigger: {
        trigger: story,
        start: "top 80%",
        end: "top top",
        scrub: 0.6,
      },
    },
  );

  const timeline = gsap.timeline({
    onUpdate: render,
    scrollTrigger: {
      trigger: story,
      start: "top top",
      end: "bottom bottom",
      scrub: 0.7,
    },
  });
  cards.forEach((card, index) => {
    const count = Number(card.style.getPropertyValue("--count")) || 1;
    if (card === fix) {
      timeline.to(card, { "--fix": 1, duration: hold, ease: "none" });
    } else {
      timeline.to(card, { "--w": count - 1, duration: hold, ease: "none" });
    }
    if (index < cards.length - 1) {
      timeline.to(state, {
        t: index + 1,
        duration: move,
        ease: "power2.inOut",
      });
    }
  });
  ScrollTrigger.refresh();

  let leave: (() => void) | undefined;
  if (fine) {
    const turn = gsap.quickTo(deck, "--px", { duration: 1.2, ease: "power3" });
    const tilt = gsap.quickTo(deck, "--py", { duration: 1.2, ease: "power3" });
    const sticky = one(".story-sticky", story)!;
    const onMove = (event: PointerEvent) => {
      const bounds = sticky.getBoundingClientRect();
      turn(((event.clientX - bounds.left) / bounds.width - 0.5) * 14);
      tilt(-((event.clientY - bounds.top) / bounds.height - 0.5) * 10);
    };
    const onLeave = () => {
      turn(0);
      tilt(0);
    };
    story.addEventListener("pointermove", onMove);
    story.addEventListener("pointerleave", onLeave);
    leave = () => {
      story.removeEventListener("pointermove", onMove);
      story.removeEventListener("pointerleave", onLeave);
    };
  }

  return () => {
    leave?.();
    story.classList.remove("is-pinned");
    story.style.removeProperty("--units");
    deck.style.removeProperty("--t");
    for (const element of [
      ...cards,
      ...copies,
      ...stages.map((s) => s.element),
    ]) {
      element.classList.remove("is-active", "is-away");
    }
    gsap.set([deck, ...cards], { clearProps: "all" });
    stages.forEach(({ fill }) => fill?.style.removeProperty("transform"));
  };
}

/** Narrow screens: the stacked cards tip up into place as they arrive. */
function sceneReveals() {
  for (const card of all("[data-scene-card]")) {
    gsap.from(card, {
      y: 56,
      rotateX: -24,
      autoAlpha: 0,
      transformPerspective: 900,
      transformOrigin: "50% 100%",
      duration: 1,
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
    fine: "(hover: hover) and (pointer: fine)",
  },
  (context) => {
    const { motion, desktop, fine } = context.conditions as Record<
      string,
      boolean
    >;
    if (!motion) return;
    const cleanups = [hero(fine), desktop ? pipeline(fine) : sceneReveals()];
    reveals();
    bento();
    return () => cleanups.forEach((cleanup) => cleanup?.());
  },
);
