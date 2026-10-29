// The Transcribe panel (components/MeetingsSection.astro): the sample
// recording turns into its transcript. An accent playhead crosses the
// speaker lanes, each bar rises as the playhead reaches it, and each turn
// appears when its speaker starts. Nothing is heard; the sample runs three
// times faster than real time so its 20 seconds read at a glance.
//
// It runs once when the panel is on screen and rests on the finished
// transcript. Leaving the screen finishes it, so the panel never rests half
// written. Afterwards the play key runs it again (and pauses it), a turn's
// time runs it from that turn, and a click on the lanes runs it from there.
// With reduced motion nothing runs and the key stays hidden; without
// JavaScript the panel is the finished frame.

const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const card = document.querySelector<HTMLElement>("[data-transcript]");
if (card && !reduced.matches) setup(card);

function setup(card: HTMLElement) {
  const end = Number(card.dataset.end);
  const play = card.querySelector<HTMLButtonElement>("[data-transcript-play]")!;
  const lanes = card.querySelector<HTMLElement>("[data-lanes]")!;
  const bars = [...lanes.querySelectorAll<HTMLElement>("[data-t]")].map(
    (bar) => ({ bar, t: Number(bar.dataset.t) }),
  );
  const turns = [...card.querySelectorAll<HTMLElement>("[data-at]")].map(
    (turn) => ({ turn, t: Number(turn.dataset.at) }),
  );
  const speed = 3;

  let time = end;
  let frame = 0;
  let last = 0;
  let played = false;
  let visible = false;

  // Only what crosses the playhead changes, so a frame touches a few nodes.
  const draw = () => {
    card.style.setProperty("--p", (time / end).toFixed(4));
    for (const { bar, t } of bars) bar.classList.toggle("is-ahead", t > time);
    for (const { turn, t } of turns)
      turn.classList.toggle("is-ahead", t > time);
    card.classList.toggle("is-partial", time < end);
  };
  const pause = () => {
    cancelAnimationFrame(frame);
    frame = 0;
    card.classList.remove("is-playing");
  };
  const finish = () => {
    pause();
    time = end;
    draw();
  };
  const tick = (now: number) => {
    time = Math.min(end, time + ((now - last) / 1000) * speed);
    last = now;
    draw();
    if (time >= end) return pause();
    frame = requestAnimationFrame(tick);
  };
  const start = (from: number) => {
    pause();
    played = true;
    time = from;
    draw();
    card.classList.add("is-playing");
    last = performance.now();
    frame = requestAnimationFrame(tick);
  };

  card.classList.add("is-live");
  play.hidden = false;

  play.addEventListener("click", () => {
    if (frame) return pause();
    start(time >= end ? 0 : time);
  });
  for (const { turn, t } of turns) {
    turn.querySelector("[data-seek]")?.addEventListener("click", () => {
      start(t);
    });
  }
  lanes.addEventListener("click", (event) => {
    const track = (event.target as Element).closest(".lane-bars");
    if (!track) return;
    const box = track.getBoundingClientRect();
    const share = (event.clientX - box.left) / box.width;
    start(Math.max(0, Math.min(1, share)) * end);
  });

  // The panel goes blank only as it nears the screen, and rests finished
  // again if the visitor turns back before it plays, so nobody meets a
  // half-written transcript.
  new IntersectionObserver(
    ([entry]) => {
      if (played) return;
      if (!entry.isIntersecting) return finish();
      time = 0;
      draw();
    },
    { rootMargin: "0px 0px 30% 0px" },
  ).observe(card);
  // It plays once it is well on screen, and leaving the screen finishes it.
  new IntersectionObserver(
    ([entry]) => {
      visible = entry.isIntersecting;
      if (!visible) return played ? finish() : undefined;
      if (played) return;
      played = true;
      // Let the panel rise first (motion.css), then transcribe.
      window.setTimeout(() => visible && !frame && start(0), 450);
    },
    { rootMargin: "0px 0px -25% 0px" },
  ).observe(card);

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) finish();
  });
}

export {};
