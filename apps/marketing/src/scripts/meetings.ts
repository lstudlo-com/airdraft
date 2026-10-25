// The Meetings card's player (components/MeetingsSection.astro), as the
// app's transcript editor has it: the play key toggles playback, and a
// timestamp plays from that point. The sample has no audio, so nothing is
// heard; the playhead and clock move six times faster than real time so the
// short sample reads at a glance.
//
// It plays once when the card is mostly on screen, from 0:00 to the resting
// frame (0:31, the card's CSS). Later playback runs to the end of the
// sample's speech and stops. Leaving the screen pauses it. With reduced
// motion it never plays by itself and the playhead jumps instead of moving:
// a timestamp moves it to that point, the play key to the end.

const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const player = document.querySelector<HTMLElement>("[data-meeting-player]");
const card = player?.closest<HTMLElement>(".meeting-card");
if (player && card) setup(player, card);

function setup(player: HTMLElement, card: HTMLElement) {
  const play = player.querySelector<HTMLElement>("[data-meeting-play]")!;
  const track = player.querySelector<HTMLElement>("[data-meeting-track]")!;
  const clock = player.querySelector<HTMLElement>("[data-meeting-time]")!;
  const stamps = [...card.querySelectorAll<HTMLElement>("[data-seek]")];
  const seconds = (stamp: string) => {
    const [minutes, rest] = stamp.split(":").map(Number);
    return minutes * 60 + rest;
  };
  // The resting frame: 0:31 with the playhead at 32% (meetings.css), so the
  // track spans about 97 seconds of the sample.
  const resting = seconds(clock.textContent?.trim() ?? "0:31");
  const span = resting / 0.32;
  // Playback ends 15 seconds after the last passage starts.
  const end =
    Math.max(...stamps.map((s) => seconds(s.dataset.seek ?? "0"))) + 15;
  const speed = 6;

  let time = resting;
  let stopAt = end;
  let frame = 0;
  let last = 0;
  let visible = false;
  let played = false;

  const format = (value: number) => {
    const whole = Math.floor(value);
    return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
  };
  const draw = () => {
    // The fill slides inside its track (meetings.css); nothing reflows.
    track.style.setProperty("--played", Math.min(1, time / span).toFixed(4));
    clock.textContent = format(time);
  };
  const pause = () => {
    cancelAnimationFrame(frame);
    frame = 0;
    card.classList.remove("is-playing");
  };
  const tick = (now: number) => {
    time = Math.min(stopAt, time + ((now - last) / 1000) * speed);
    last = now;
    draw();
    if (time >= stopAt) return pause();
    frame = requestAnimationFrame(tick);
  };
  const start = (from: number, to = end) => {
    pause();
    time = from;
    stopAt = to;
    if (reduced.matches) return draw();
    draw();
    card.classList.add("is-playing");
    last = performance.now();
    frame = requestAnimationFrame(tick);
  };

  card.classList.add("is-live");

  play.addEventListener("click", () => {
    played = true;
    if (frame) return pause();
    // With reduced motion the playhead jumps to where playback would end.
    if (reduced.matches) {
      time = time >= end ? 0 : end;
      return draw();
    }
    start(time >= end ? 0 : time);
  });
  for (const stamp of stamps) {
    stamp.addEventListener("click", () => {
      played = true;
      start(seconds(stamp.dataset.seek ?? "0"));
    });
  }

  new IntersectionObserver(
    ([entry]) => {
      visible = entry.isIntersecting;
      if (!visible) return pause();
      if (played || reduced.matches || entry.intersectionRatio < 0.6) return;
      played = true;
      // Once the card has risen (motion.css), play the sample to its rest.
      window.setTimeout(() => visible && start(0, resting), 300);
    },
    { threshold: [0, 0.6] },
  ).observe(card);

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) pause();
  });
}

export {};
