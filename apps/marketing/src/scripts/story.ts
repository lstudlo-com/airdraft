// Scroll storytelling for the homepage, built on GSAP and ScrollTrigger:
// headings, the sample, panels, bento tiles and offers rise into place as
// they enter, where the browser has no scroll timelines (motion.css does it
// elsewhere). The bento's graphics perform in bento.ts, the Meetings player
// in meetings.ts and the provider board's run in pipeline.ts.
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

const media = gsap.matchMedia();
media.add("(prefers-reduced-motion: no-preference)", () => {
  // motion.css raises these from the scroll position where it can.
  if (!CSS.supports("animation-timeline: view()")) reveals();
});
