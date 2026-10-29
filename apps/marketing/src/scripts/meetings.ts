// The Transcribe story (components/MeetingsSection.astro): the recording
// comes in, its speaker lanes fill, the turns are written out, the formats
// export. One number, --ts-p, runs from 0 to 1 across those beats; CSS turns
// it into everything on screen and rests at 1, the finished transcript.
//
// Where the browser has scroll timelines, motion.css scrubs --ts-p with the
// scroll and this script only adds controls: the play key plays the whole
// story in time (and pauses it), a turn's time plays it from that turn and
// a click on the lanes plays it from there. While it plays in time the root
// carries .is-timed and an important --ts-p, which win over the scroll's
// animations without stopping them; the scroll takes
// it back once it would show the same finished frame, or once the story
// leaves the screen (or the tab hides).
//
// Elsewhere the story plays in time once when it is on screen, as the
// panel did before: it goes blank only as it nears the screen, and leaving
// the screen finishes it, so it never rests half written. With reduced
// motion nothing runs and the key stays hidden; without JavaScript the
// story is the finished frame.

const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const root = document.querySelector<HTMLElement>("[data-transcript]");
if (root && !reduced.matches) setup(root);

function setup(root: HTMLElement) {
  const scrolled = CSS.supports("animation-timeline: view()");
  const play = root.querySelector<HTMLButtonElement>("[data-transcript-play]")!;
  const lanes = root.querySelector<HTMLElement>("[data-lanes]")!;
  // A beat's share of the story, from its --a and --b.
  const share = (selector: string) => {
    const beat = root.querySelector<HTMLElement>(selector)!;
    const style = getComputedStyle(beat);
    const a = Number(style.getPropertyValue("--a"));
    const b = Number(style.getPropertyValue("--b"));
    return (k: number) => a + k * (b - a);
  };
  const inLanes = share("[data-beat-lanes]");
  const inTurns = share("[data-beat-turns]");
  // The whole story in nine seconds, the lanes in under three.
  const duration = 9000;

  let p = 1;
  let frame = 0;
  let last = 0;
  let played = false;

  const set = (value: number) => {
    p = value;
    // Important, so it wins over the scroll animation underneath.
    root.style.setProperty("--ts-p", p.toFixed(4), "important");
  };
  const pause = () => {
    cancelAnimationFrame(frame);
    frame = 0;
    root.classList.remove("is-playing");
  };
  const beatsList = [...root.querySelectorAll<HTMLElement>(".ts-beat")];
  // Whether the scroll alone would show the finished story here (every
  // scroll animation at its end): then handing it back changes nothing on
  // screen. The scroll animations keep running underneath a timed play.
  const finishedByScroll = () => {
    const animations = [root, ...beatsList].flatMap((element) =>
      element.getAnimations(),
    );
    return (
      animations.length > 0 &&
      animations.every(
        (animation) =>
          (animation.effect?.getComputedTiming().progress ?? 0) >= 0.999,
      )
    );
  };
  const tick = (now: number) => {
    set(Math.min(1, p + (now - last) / duration));
    last = now;
    if (p >= 1) {
      pause();
      if (scrolled && finishedByScroll()) settle();
      return;
    }
    frame = requestAnimationFrame(tick);
  };
  const start = (from: number) => {
    pause();
    played = true;
    root.classList.add("is-timed", "is-playing");
    set(from);
    last = performance.now();
    frame = requestAnimationFrame(tick);
  };
  // Back to the resting state: the scroll's position where it drives the
  // story, the finished transcript where it doesn't.
  const settle = () => {
    pause();
    if (scrolled) {
      root.classList.remove("is-timed");
      root.style.removeProperty("--ts-p");
      p = 1;
    } else set(1);
  };

  root.classList.add("is-live");
  play.hidden = false;

  play.addEventListener("click", () => {
    if (frame) return pause();
    const timed = root.classList.contains("is-timed");
    start(timed && p < 1 ? p : 0);
  });
  root.querySelectorAll<HTMLElement>(".turn").forEach((turn) => {
    const at = Number(getComputedStyle(turn).getPropertyValue("--at"));
    turn.querySelector("[data-seek]")?.addEventListener("click", () => {
      start(inTurns(at));
    });
  });
  lanes.addEventListener("click", (event) => {
    const track = (event.target as Element).closest(".lane-bars");
    if (!track) return;
    const box = track.getBoundingClientRect();
    const k = (event.clientX - box.left) / box.width;
    start(inLanes(Math.max(0, Math.min(1, k))));
  });

  // A finished or paused story goes back to the scroll as soon as the
  // scroll reaches the end of the story, or when it leaves the screen.
  if (scrolled)
    window.addEventListener(
      "scroll",
      () => {
        if (frame || !root.classList.contains("is-timed")) return;
        if (finishedByScroll()) settle();
      },
      { passive: true },
    );
  // Leaving the screen hands the story back.
  new IntersectionObserver(([entry]) => {
    if (!entry.isIntersecting && root.classList.contains("is-timed")) settle();
  }).observe(root);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden && root.classList.contains("is-timed")) settle();
  });

  if (scrolled) return;

  // Without scroll timelines: the story goes blank only as it nears the
  // screen, and rests finished again if the visitor turns back before it
  // plays, so nobody meets a half-written transcript.
  new IntersectionObserver(
    ([entry]) => {
      if (played) return;
      if (!entry.isIntersecting) return set(1);
      set(0);
    },
    { rootMargin: "0px 0px 30% 0px" },
  ).observe(root);
  // It plays once it is well on screen.
  new IntersectionObserver(
    ([entry]) => {
      if (played || !entry.isIntersecting) return;
      played = true;
      // Let the stage rise first (story.ts), then play.
      window.setTimeout(() => !frame && start(0), 450);
    },
    { rootMargin: "0px 0px -25% 0px" },
  ).observe(root);
}

export {};
