// The homepage's thread: what is left of the hero's ribbon, laid on the
// island and drawn on down the page by the scroll. It leaves the ribbon's
// right end, where text lands, and runs beside the content, a fixed step out
// from the content's edge, as a margin rule runs beside a page. Between two
// story sections it crosses to the other side inside the empty space that
// separates them, below the last content and above the next title, so it
// never runs over a title or a card and each crossing reads as the line
// between two sections. Short sections keep its side. It ends in the middle,
// over Get Airdraft's title, as a bead.
//
// Its tip is where the scroll has reached (seven tenths of the way down the
// window), so scrolling down draws it further and scrolling up takes it
// back; a crossing draws across as that line comes up to it, and a few
// grains trail the tip, as the hero's ribbon comes apart into grains.
//
// It is the same material as the hero's ribbon, drawn thin: a fine silver
// band that turns slowly about its own length, never edge on, so it brightens
// and dims without breaking. Light from the top left: a hairline of shade
// under it, and its tip is a small silver bead.
//
// It lives behind everything on the island (z-index -1 in the island's own
// stacking context), only where the margins are wide enough to hold it, and
// only within the window: each frame redraws the part on screen. Without
// JavaScript there is none; with reduced motion it rests whole and still.

const island = document.querySelector<HTMLElement>("main.island.home");
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const SVG = "http://www.w3.org/2000/svg";

// Half the band's width at its narrowest and widest, how long a full turn is
// along it, and how far its tip reaches down the window.
const THIN = 0.75;
const FULL = 1.5;
const TURN = 640;
const TIP = 0.72;
// The narrowest margin it runs in, and the most it stands off the content.
const ROOM = 64;
const STEP = 48;
// How far ahead of a crossing the tip starts across it.
const LEAD = 160;
// The band's tones, as shares of its lit face over its shaded one, and the
// light: up and to the left, in front.
const TONES = Array.from({ length: 9 }, (_, index) => 20 + index * 10);
const LIGHT = { x: -0.45, y: -0.55, z: 0.7 };

interface Sample {
  x: number;
  y: number;
  nx: number;
  ny: number;
  s: number;
}

// A stretch of the path the tip draws as the window's line passes a height
// range rather than at the height it has reached: a crossing, and the last
// turn into the middle.
interface Sweep {
  from: number;
  to: number;
  s0: number;
  s1: number;
}

const smoothstep = (t: number) => {
  const c = Math.min(1, Math.max(0, t));
  return c * c * c * (c * (c * 6 - 15) + 10);
};
const clamp = (t: number) => Math.min(1, Math.max(0, t));

function within(element: HTMLElement, root: HTMLElement) {
  let y = 0;
  let x = 0;
  for (
    let node: HTMLElement | null = element;
    node && node !== root;
    node = node.offsetParent as HTMLElement | null
  ) {
    y += node.offsetTop;
    x += node.offsetLeft;
  }
  return { x, y };
}

if (island) {
  const svg = document.createElementNS(SVG, "svg");
  svg.classList.add("thread");
  svg.setAttribute("aria-hidden", "true");
  const shade = document.createElementNS(SVG, "path");
  shade.classList.add("thread-shade");
  const paths = TONES.map((tone) => {
    const path = document.createElementNS(SVG, "path");
    path.classList.add("thread-tone");
    path.style.setProperty("--tone", `${tone}%`);
    return path;
  });
  const grains = document.createElementNS(SVG, "path");
  grains.classList.add("thread-grains");
  const bead = document.createElementNS(SVG, "circle");
  bead.classList.add("thread-bead");
  bead.setAttribute("r", "2.4");
  svg.append(shade, ...paths, grains, bead);
  island.prepend(svg);

  let samples: Sample[] = [];
  let sweeps: Sweep[] = [];
  let on = false;

  // The thread's centre line, in the island's own coordinates: a function
  // of height, sampled along its length.
  function build() {
    samples = [];
    sweeps = [];
    const width = island!.clientWidth;
    const wrap = island!.querySelector<HTMLElement>(":scope > .wrap");
    const card = island!.querySelector<HTMLElement>(".hero-card");
    const sections = [
      ...island!.querySelectorAll<HTMLElement>(":scope > section"),
    ].filter((section) => section.offsetHeight > 0);
    if (!wrap || !card || sections.length < 3) return false;
    const inset = parseFloat(getComputedStyle(island!).paddingLeft) || 0;
    const left = wrap.offsetLeft;
    const room = left - inset;
    if (room < ROOM) return false;
    // A lane each side, a step out from the content's edge.
    const out = Math.min(STEP, room / 2);
    const lanes = [left - out, width - left + out];
    const view = innerHeight;

    // The ribbon ends just past the waveform's caret (hero3d-scene.ts), at
    // the middle of its well.
    const cardBox = within(card, island!);
    const wave = card.querySelector<HTMLElement>(".wave");
    const caret = wave?.querySelector<HTMLElement>(".wave-caret");
    const start =
      wave && caret && caret.offsetWidth
        ? {
            x: within(caret, island!).x + caret.offsetWidth / 2 + 4,
            y: within(wave, island!).y + wave.offsetHeight / 2,
          }
        : {
            x: cardBox.x + card.offsetWidth - 22,
            y: cardBox.y + card.offsetHeight / 2,
          };
    const finale = sections[sections.length - 1];
    const finaleTitle =
      finale.querySelector<HTMLElement>(".section-heading") ?? finale;
    const end = { x: width / 2, y: within(finaleTitle, island!).y - 30 };

    // Each crossing sits in the space above a section after the first
    // story, inside it: clear of the last content above (its section's
    // bottom) and of the next title (its section's top). Short sections
    // keep the side they are on. The last one turns into the middle.
    interface Bend {
      from: number;
      to: number;
      side: number;
    }
    const bends: Bend[] = [];
    let side = 1;
    for (let i = 2; i < sections.length; i++) {
      const above = sections[i - 1];
      const bottom = within(above, island!).y + above.offsetHeight;
      const top = within(sections[i], island!).y;
      const last = i === sections.length - 1;
      if (!last && sections[i].offsetHeight < view * 0.8) continue;
      const gap = top - bottom;
      side = last ? -1 : 1 - side;
      bends.push({
        from: bottom + gap * 0.2,
        to: last ? end.y : top - gap * 0.3,
        side,
      });
    }

    // Where the path is at height y, off its lane by a slow meander.
    const wander = (y: number) => Math.sin(y / 240) * Math.min(8, room / 10);
    const x = (y: number) => {
      // From the ribbon's end on out to the right, then down into the
      // right lane.
      if (y < start.y + 280) {
        const t = clamp((y - start.y) / 280);
        return start.x + (lanes[1] + wander(y) - start.x) * (1 - (1 - t) ** 3);
      }
      let lane = 1;
      for (const bend of bends) {
        if (y <= bend.from) break;
        const target = bend.side < 0 ? end.x : lanes[bend.side];
        const from = lanes[lane] + wander(bend.from);
        if (y < bend.to) {
          const t = smoothstep((y - bend.from) / (bend.to - bend.from));
          const to = bend.side < 0 ? end.x : target + wander(bend.to);
          return from + (to - from) * t;
        }
        if (bend.side < 0) return end.x;
        lane = bend.side;
      }
      return lanes[lane] + wander(y);
    };

    // Sample it about every 3px along its length.
    let y = start.y;
    let px = x(y);
    let py = y;
    let s = 0;
    samples.push({ x: px, y: py, nx: 0, ny: 0, s: 0 });
    while (y < end.y) {
      const slope = Math.abs(x(y + 0.25) - x(y)) * 4;
      y = Math.min(end.y, y + Math.max(0.05, 3 / Math.sqrt(1 + slope * slope)));
      const nx = x(y);
      s += Math.hypot(nx - px, y - py);
      samples.push({ x: nx, y, nx: 0, ny: 0, s });
      px = nx;
      py = y;
    }
    // Normals.
    for (let i = 0; i < samples.length; i++) {
      const a = samples[Math.max(0, i - 1)];
      const b = samples[Math.min(samples.length - 1, i + 1)];
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const length = Math.hypot(dx, dy) || 1;
      samples[i].nx = -dy / length;
      samples[i].ny = dx / length;
    }
    // The tip starts across each bend a little before the window's line
    // reaches it and is across as the line passes its end.
    for (const bend of bends) {
      const from = bend.from - LEAD;
      sweeps.push({
        from,
        to: bend.to,
        s0: samples[find(from)].s,
        s1: samples[find(bend.to)].s,
      });
    }
    const height = island!.offsetHeight;
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    svg.style.height = `${height}px`;
    return true;
  }

  // The first sample at or below height y, or at or past arc length s.
  function find(y: number, key: "y" | "s" = "y") {
    let low = 0;
    let high = samples.length - 1;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (samples[mid][key] < y) low = mid + 1;
      else high = mid;
    }
    return low;
  }

  // How far along the thread the tip is when the window's line is at y.
  function reach(y: number) {
    for (const sweep of sweeps)
      if (y > sweep.from && y < sweep.to)
        return (
          sweep.s0 +
          (sweep.s1 - sweep.s0) *
            smoothstep((y - sweep.from) / (sweep.to - sweep.from))
        );
    return samples[find(y)].s;
  }

  const point = (n: number) => n.toFixed(1);

  function draw() {
    frame = 0;
    if (!on || !samples.length) return;
    const rect = island!.getBoundingClientRect();
    const still = reduced.matches;
    // The window, in the island's coordinates.
    const top = -rect.top - 40;
    const bottom = -rect.top + innerHeight + 40;
    const total = samples[samples.length - 1].s;
    const tipS = still ? total : reach(-rect.top + innerHeight * TIP);
    const tipIndex = Math.min(samples.length - 1, find(tipS, "s"));
    const first = find(top);
    const last = Math.min(tipIndex, find(bottom));
    const spin = still ? 0 : scrollY * 0.002;

    // Each short piece of band takes one of the tones, from its face's
    // angle to the light: as the band turns, a face brightens toward the
    // light and dims away from it, and it narrows, never to nothing.
    const tones = TONES.map(() => "");
    let shadePath = "";
    let previous: {
      a: [number, number];
      b: [number, number];
      lit: number;
    } | null = null;
    for (let i = first; i <= last; i++) {
      const p = samples[i];
      const turn = (p.s / TURN) * Math.PI * 2 + spin;
      const c = Math.cos(turn);
      // Thin where it leaves the ribbon and toward its tip.
      const taper =
        clamp(p.s / 90) * (still ? 1 : 0.35 + 0.65 * clamp((tipS - p.s) / 140));
      const half = (THIN + (FULL - THIN) * Math.abs(c)) * taper;
      const across = Math.sign(c || 1) * Math.sin(turn);
      const lit = clamp(
        0.5 +
          0.5 *
            (Math.abs(c) * LIGHT.z +
              across * (p.nx * LIGHT.x + p.ny * LIGHT.y)),
      );
      const edge = {
        a: [p.x + p.nx * half, p.y + p.ny * half] as [number, number],
        b: [p.x - p.nx * half, p.y - p.ny * half] as [number, number],
        lit,
      };
      if (previous) {
        const quad = `M${point(previous.a[0])} ${point(previous.a[1])}L${point(edge.a[0])} ${point(edge.a[1])}L${point(edge.b[0])} ${point(edge.b[1])}L${point(previous.b[0])} ${point(previous.b[1])}Z`;
        const tone = Math.min(
          TONES.length - 1,
          Math.floor(((previous.lit + lit) / 2) * TONES.length),
        );
        tones[tone] += quad;
        shadePath += quad;
      }
      previous = edge;
    }
    paths.forEach((path, index) => path.setAttribute("d", tones[index]));
    shade.setAttribute("d", shadePath);

    // The bead at the tip, and a few grains trailing it.
    const tip = samples[tipIndex];
    const showing = tip.y > top && tip.y < bottom && tipIndex > 0;
    bead.style.display = showing ? "" : "none";
    if (showing) {
      bead.setAttribute("cx", point(tip.x));
      bead.setAttribute("cy", point(tip.y));
    }
    let grainPath = "";
    if (!still && showing && tipS < total) {
      const t = performance.now() / 1000;
      for (let k = 0; k < 9; k++) {
        const s = tipS - 10 - k * 14;
        if (s < 0) break;
        const p = samples[find(s, "s")];
        const drift = Math.sin(k * 1.9 + scrollY * 0.012 + t * 0.6) * (3 + k);
        const r = Math.max(0.45, 1.2 - k * 0.08);
        const gx = p.x + p.nx * drift;
        const gy = p.y + p.ny * drift;
        grainPath += `M${point(gx - r)} ${point(gy)}a${r} ${r} 0 1 0 ${point(r * 2)} 0a${r} ${r} 0 1 0 ${point(-r * 2)} 0`;
      }
    }
    grains.setAttribute("d", grainPath);
  }

  let frame = 0;
  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(draw);
  };
  const rebuild = () => {
    on = build();
    svg.classList.toggle("is-on", on);
    schedule();
  };
  let timer = 0;
  const later = () => {
    clearTimeout(timer);
    timer = window.setTimeout(rebuild, 150);
  };
  addEventListener("scroll", schedule, { passive: true });
  addEventListener("resize", later);
  addEventListener("load", rebuild);
  document.fonts?.ready.then(rebuild);
  new ResizeObserver(later).observe(island);
  reduced.addEventListener("change", schedule);
  rebuild();
}

export {};
