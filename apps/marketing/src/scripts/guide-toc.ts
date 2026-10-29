// "On this page" (components/GuideToc.astro): the section being read takes
// aria-current and a raised thumb slides to it on the selection curve (CSS),
// like the changelog's version navigator. Without JavaScript the links work
// and no thumb shows.
const nav = document.querySelector<HTMLElement>("[data-guide-toc]");
if (nav) setup(nav);

function setup(nav: HTMLElement) {
  const links = [...nav.querySelectorAll<HTMLAnchorElement>("[data-toc-link]")];
  const targets = links.map((link) =>
    document.getElementById(decodeURIComponent(link.hash.slice(1))),
  );
  let frame = 0;
  let selected: HTMLAnchorElement | undefined;

  const update = () => {
    frame = 0;
    // A heading is being read once it passes a line just below the header.
    const line = Math.min(220, innerHeight * 0.3);
    let index = 0;
    targets.forEach((target, i) => {
      if (target && target.getBoundingClientRect().top <= line) index = i;
    });
    // At the bottom of the page the last section is the one being read.
    if (innerHeight + scrollY >= document.documentElement.scrollHeight - 4)
      index = links.length - 1;
    const link = links[index];
    if (selected !== link) {
      selected?.removeAttribute("aria-current");
      link.setAttribute("aria-current", "location");
      selected = link;
    }
    const item = link.parentElement!;
    nav.style.setProperty("--thumb-y", `${item.offsetTop}px`);
    nav.style.setProperty("--thumb-height", `${item.offsetHeight}px`);
    nav.dataset.ready = "";
  };
  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(update);
  };
  addEventListener("scroll", schedule, { passive: true });
  addEventListener("resize", schedule);
  addEventListener("hashchange", schedule);
  update();
}

export {};
