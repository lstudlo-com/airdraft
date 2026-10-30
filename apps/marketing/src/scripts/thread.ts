// The homepage's thread: what is left of the hero's ribbon, drawn on down the
// page by the scroll. It leaves the ribbon's right end, where text lands,
// and runs down the island's open margins beside the sections, swinging
// from one side to the other in the space between two sections, and ends
// over Get Airdraft's title. Its tip is wherever the scroll has reached
// (seven tenths of the way down the window), so scrolling down draws it
// further and scrolling up takes it back; a few grains trail the tip, as
// the hero's ribbon comes apart into grains.
//
// It is the same material as the hero's ribbon, flattened: a narrow silver
// band seen face on, turning slowly about its own length (each half-turn
// shows its lighter face, then its darker back) and turning a little more as
// the page scrolls. Light from the top left: a hairline of shade under it.
//
// It lives behind everything on the island (z-index -1 in the island's own
// stacking context), only where the margins are wide enough that it never
// crosses text, and only within the window: each frame redraws the part on
// screen. Without JavaScript there is none; with reduced motion it rests
// whole and still.

const island = document.querySelector<HTMLElement>("main.island.home");
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const SVG = "http://www.w3.org/2000/svg";

// Half the band's width, how long a full turn is along it, and how far
// its tip reaches down the window.
const WIDTH = 3.8;
const TURN = 460;
const TIP = 0.72;
// The narrowest margin it will run in.
const ROOM = 64;
// The band's eleven tones, as shares of its lit face over its shaded one, and
// the light: up and to the left, in front.
const TONES = Array.from({ length: 11 }, (_, index) => index * 10);
const LIGHT = { x: -0.45, y: -0.55, z: 0.7 };

interface Sample {
  x: number;
  y: number;
  nx: number;
  ny: number;
  s: number;
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
  svg.append(shade, ...paths, grains);
  island.prepend(svg);

  let samples: Sample[] = [];
  let on = false;

  // The thread's centre line, in the island's own coordinates: a function
  // of height, so the tip is wherever the window's line crosses it.
  function build() {
    samples = [];
    const width = island!.clientWidth;
    const wrap = island!.querySelector<HTMLElement>(":scope > .wrap");
    const card = island!.querySelector<HTMLElement>(".hero-card");
    const sections = [
      ...island!.querySelectorAll<HTMLElement>(":scope > section"),
    ];
    if (!wrap || !card || sections.length < 3) return false;
    const inset = parseFloat(getComputedStyle(island!).paddingLeft) || 0;
    const left = wrap.offsetLeft;
    const room = left - inset;
    if (room < ROOM) return false;
    const sides = [inset + room / 2, width - inset - room / 2];

    const cardBox = within(card, island!);
    const start = {
      x: cardBox.x + card.offsetWidth - 22,
      y: cardBox.y + card.offsetHeight / 2,
    };
    // Every crossing: the middle of the space above each section after
    // the hero; the last one leads into Get Airdraft's title.
    const crossings: number[] = [];
    for (let i = 2; i < sections.length; i++) {
      const above = sections[i - 1];
      const bottom = within(above, island!).y + above.offsetHeight;
      const top = within(sections[i], island!).y;
      crossings.push((bottom + top) / 2);
    }
    const finale = sections[sections.length - 1];
    const finaleTitle =
      finale.querySelector<HTMLElement>(".section-heading") ?? finale;
    const end = {
      x: width / 2,
      y: within(finaleTitle, island!).y - 28,
    };
    crossings.pop();
    // The last section before it, where the thread leaves its margin.
    const penult = sections[sections.length - 2];
    const leaveMargin = within(penult, island!).y + penult.offsetHeight - 60;

    // Half the height over which a crossing swings across.
    const SWING = 110;
    const sideAt = (index: number) => sides[(index + 1) % 2];
    // A slow meander within the margin.
    const wander = (y: number) => Math.sin(y / 210) * Math.min(18, room / 6);
    const x = (y: number) => {
      const meander = wander(y);
      // From the ribbon's end out to the right margin.
      if (y < start.y + 260) {
        const t = smoothstep((y - start.y) / 260);
        return start.x + (sides[1] + meander - start.x) * t;
      }
      // Into the finale, from whichever side.
      const finalSide = sideAt(crossings.length) + meander;
      const into = Math.min(leaveMargin, end.y - 120);
      if (y > into) {
        const t = smoothstep((y - into) / (end.y - into));
        return finalSide + (end.x - finalSide) * t;
      }
      let index = 0;
      while (index < crossings.length && y > crossings[index] + SWING) index++;
      const from = sideAt(index);
      if (index < crossings.length && y > crossings[index] - SWING) {
        const t = smoothstep((y - crossings[index] + SWING) / (SWING * 2));
        const to = sideAt(index + 1);
        return from + (to - from) * t + meander * (1 - Math.sin(Math.PI * t));
      }
      return from + meander;
    };

    // Sample it about every 3px along its length.
    let y = start.y;
    let px = x(y);
    let py = y;
    let s = 0;
    samples.push({ x: px, y: py, nx: 0, ny: 0, s: 0 });
    while (y < end.y) {
      const slope = Math.abs(x(y + 0.5) - x(y)) * 2;
      y = Math.min(end.y, y + 3 / Math.sqrt(1 + slope * slope));
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
    const height = island!.offsetHeight;
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    svg.style.height = `${height}px`;
    return true;
  }

  // The first sample at or below height y.
  function find(y: number) {
    let low = 0;
    let high = samples.length - 1;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (samples[mid].y < y) low = mid + 1;
      else high = mid;
    }
    return low;
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
    const tipY = still ? Infinity : -rect.top + innerHeight * TIP;
    const first = find(top);
    const last = Math.min(samples.length - 1, find(Math.min(bottom, tipY)));
    const tipIndex = Math.min(samples.length - 1, find(tipY));
    const tipS = samples[tipIndex].s;
    const spin = still ? 0 : scrollY * 0.0035;

    // Each short piece of band takes one of five tones, from its face's
    // angle to a light up and to the left in front: as the band turns, a
    // face brightens toward the light and darkens away from it, and the
    // band narrows to nothing where it turns edge on.
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
      // Thin where it leaves the ribbon and where its tip is.
      const taper =
        clamp(p.s / 80) *
        (still ? 1 : clamp((tipS - p.s) / 160)) *
        clamp((samples[samples.length - 1].s - p.s) / 120);
      const half =
        WIDTH * c * Math.sqrt(taper) + 0.35 * taper * Math.sign(c || 1);
      // The visible face's normal: out of the page by |cos|, across the
      // band in the page by sin (turned to whichever face shows).
      const across = Math.sign(c || 1) * Math.sin(turn);
      const lit = clamp(
        0.5 +
          0.55 *
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

    // A few grains trailing the tip.
    let grainPath = "";
    if (!still && tipY < bottom && tipIndex > 0) {
      const t = performance.now() / 1000;
      for (let k = 0; k < 14; k++) {
        const s = tipS - 6 - k * 13;
        if (s < 0) break;
        const p = samples[findS(s)];
        const drift = Math.sin(k * 1.9 + scrollY * 0.012 + t * 0.6) * (4 + k);
        const r = Math.max(0.5, 1.5 - k * 0.07);
        const gx = p.x + p.nx * drift;
        const gy = p.y + p.ny * drift;
        grainPath += `M${point(gx - r)} ${point(gy)}a${r} ${r} 0 1 0 ${point(r * 2)} 0a${r} ${r} 0 1 0 ${point(-r * 2)} 0`;
      }
    }
    grains.setAttribute("d", grainPath);
  }

  // The sample at arc length s.
  function findS(s: number) {
    let low = 0;
    let high = samples.length - 1;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (samples[mid].s < s) low = mid + 1;
      else high = mid;
    }
    return low;
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
