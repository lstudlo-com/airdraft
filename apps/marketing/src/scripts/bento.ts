// The homepage bento's graphics (HomePage.astro, #features) do what their
// tile says, and answer the visitor.
//
//   arrival   when a tile is mostly on screen its graphic performs once, the
//             tiles of a row one after another from the left, then rests on
//             its final frame. Nothing loops.
//   poke      hovering a tile (a mouse) or tapping it performs again; a
//             choice tile tries its next choice
//   touch     the parts that are controls in the app work: the shortcut's
//             keycaps (and the visitor's own ⌃⌥ while that tile is on
//             screen) record in the cursor tile while held and insert on
//             release; segmented choices and the subscription chips select
//
// Resting CSS is every graphic's final frame, so the bento reads the same
// without JavaScript. With reduced motion nothing performs and choices
// change in place, without movement. A tile that leaves the screen jumps to
// its resting frame, so no timer runs off screen.
import { gsap } from "gsap";

const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const hover = matchMedia("(hover: hover) and (pointer: fine)");

const all = <T extends HTMLElement = HTMLElement>(
  selector: string,
  root: ParentNode,
) => [...root.querySelectorAll<T>(selector)];
const one = <T extends HTMLElement = HTMLElement>(
  selector: string,
  root: ParentNode,
) => root.querySelector<T>(selector);

interface Performer {
  /** The tile's arrival: a short performance ending on the resting frame. */
  arrive(): void;
  /** A hover or tap. */
  poke(): void;
  /** Jump to the resting frame and stop every timer. */
  finish(): void;
}

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
  return all("span:not(.caret)", paragraph);
}

/** Swap a line of text: the old one fades up and out, the new one rises in. */
function swapText(element: HTMLElement, text: string) {
  gsap.killTweensOf(element);
  if (reduced.matches) {
    element.textContent = text;
    gsap.set(element, { clearProps: "opacity,transform" });
    return;
  }
  gsap
    .timeline()
    .to(element, { autoAlpha: 0, y: -6, duration: 0.18, ease: "power1.in" })
    .call(() => {
      element.textContent = text;
    })
    .fromTo(
      element,
      { y: 6 },
      { autoAlpha: 1, y: 0, duration: 0.36, ease: "power3.out" },
    );
}

// ---------------------------------------------------------------- cursor

interface Recorder extends Performer {
  hold(): void;
  release(): void;
  recording(): boolean;
}

/** The cursor tile: the recording pill counts while the shortcut is held,
 *  shows Refining on release, then the text is typed at the caret. The
 *  shortcut tile's keycaps sink for as long as it records. */
function cursor(art: HTMLElement, keys: () => HTMLElement | null): Recorder {
  const field = one("[data-typed]", art)!;
  const typed = words(field);
  const label = one("[data-hud-label]", art)!;
  const resting = label.textContent?.trim() ?? "";
  const refining = one("[data-hud]", art)?.dataset.refining ?? resting;
  const bars = all(".hud-bars span", art);
  const levels = bars.map((bar) => bar.style.getPropertyValue("--level"));
  let started = 0;
  let last = 0;
  let isRecording = false;
  let typing: gsap.core.Timeline | null = null;
  let autoRelease: gsap.core.Tween | null = null;

  const tick = () => {
    const now = performance.now();
    if (now - last < 80) return;
    last = now;
    const seconds = (now - started) / 1000;
    label.textContent = `0:${seconds.toFixed(1).padStart(4, "0")}`;
    for (const bar of bars) {
      bar.style.setProperty("--level", gsap.utils.random(0.2, 1).toFixed(3));
    }
  };
  const stopClock = () => {
    gsap.ticker.remove(tick);
    autoRelease?.kill();
    autoRelease = null;
    isRecording = false;
    keys()?.classList.remove("is-pressed");
  };

  const hold = () => {
    if (isRecording) return;
    typing?.kill();
    gsap.killTweensOf(typed);
    gsap.set(typed, { display: "none", autoAlpha: 1 });
    art.classList.add("is-recording");
    keys()?.classList.add("is-pressed");
    isRecording = true;
    started = performance.now();
    last = 0;
    gsap.ticker.add(tick);
    // Eight seconds stop it, as in the hero's dictation.
    autoRelease = gsap.delayedCall(8, () => release());
  };
  const release = () => {
    if (!isRecording) return;
    stopClock();
    art.classList.remove("is-recording");
    label.textContent = refining;
    for (const bar of bars) bar.style.setProperty("--level", "0.14");
    typing = gsap
      .timeline({ onComplete: () => art.classList.remove("is-typing") })
      .call(() => art.classList.add("is-typing"), [], 0.45)
      .to(typed, { display: "inline", duration: 0, stagger: 0.08 }, 0.45);
  };
  const finish = () => {
    stopClock();
    typing?.kill();
    typing = null;
    art.classList.remove("is-recording", "is-typing");
    gsap.set(typed, { display: "inline", autoAlpha: 1 });
    label.textContent = resting;
    bars.forEach((bar, index) =>
      bar.style.setProperty("--level", levels[index] || "0.14"),
    );
  };
  const busy = () => isRecording || Boolean(typing?.isActive());
  const play = () => {
    if (busy()) return;
    hold();
    autoRelease?.kill();
    autoRelease = gsap.delayedCall(1.8, () => release());
  };

  return {
    arrive: play,
    poke: play,
    finish,
    hold,
    release,
    recording: () => isRecording,
  };
}

/** The shortcut tile drives the cursor tile. Its keycaps record while held
 *  by the pointer; the visitor's own ⌃⌥ does the same while the tile is on
 *  screen (keys.ts already sinks the keycaps). Any third key cancels, so
 *  VoiceOver's ⌃⌥ commands never type. */
function shortcut(
  art: HTMLElement,
  recorder: Recorder | undefined,
  recorderVisible: () => boolean,
  visible: () => boolean,
): Performer {
  const keys = one(".keys", art)!;
  let flash: gsap.core.Tween | null = null;

  const pressBriefly = () => {
    flash?.kill();
    keys.classList.add("is-pressed");
    flash = gsap.delayedCall(1.2, () => keys.classList.remove("is-pressed"));
  };
  const perform = () => {
    // The cursor tile shows what the shortcut does when it can be seen;
    // otherwise the keys alone answer.
    if (recorder && recorderVisible()) recorder.arrive();
    else pressBriefly();
  };

  keys.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    event.stopPropagation();
    try {
      keys.setPointerCapture(event.pointerId);
    } catch {
      // Synthetic pointers cannot be captured; the release still arrives.
    }
    flash?.kill();
    keys.classList.add("is-pressed");
    if (!reduced.matches) recorder?.hold();
  });
  const up = () => {
    keys.classList.remove("is-pressed");
    if (recorder?.recording()) recorder.release();
  };
  keys.addEventListener("pointerup", up);
  // The press already answered; the tile's own tap must not replay it.
  keys.addEventListener("click", (event) => event.stopPropagation());
  keys.addEventListener("pointercancel", () => {
    keys.classList.remove("is-pressed");
    recorder?.finish();
  });

  const held = new Set<string>();
  const shortcutOnly = () =>
    [...held].every((key) => key === "Control" || key === "Alt");
  window.addEventListener("keydown", (event) => {
    held.add(event.key);
    if (!recorder || reduced.matches) return;
    if (recorder.recording() && !shortcutOnly()) return recorder.finish();
    if (
      event.ctrlKey &&
      event.altKey &&
      !event.metaKey &&
      !event.shiftKey &&
      shortcutOnly() &&
      visible()
    ) {
      recorder.hold();
    }
  });
  window.addEventListener("keyup", (event) => {
    held.delete(event.key);
    if (
      (event.key === "Control" || event.key === "Alt") &&
      recorder?.recording()
    ) {
      recorder.release();
    }
  });
  window.addEventListener("blur", () => {
    held.clear();
    if (recorder?.recording()) recorder.finish();
  });

  return {
    arrive: perform,
    poke: perform,
    finish: () => {
      flash?.kill();
      keys.classList.remove("is-pressed");
    },
  };
}

// --------------------------------------------------------------- choices

/** A tile whose graphic is a choice: the profile and script pickers, the
 *  history card's Refined | Original toggle and the subscription chips.
 *  Arriving tries the next choice and comes back; a poke tries the next
 *  one; clicking a choice selects it. */
function choice(
  items: HTMLElement[],
  show: (index: number) => void,
  initial = 0,
): Performer {
  let current = initial;
  let tour: gsap.core.Timeline | null = null;
  const select = (index: number) => {
    if (index === current) return;
    current = index;
    show(index);
  };
  items.forEach((item, index) =>
    item.addEventListener("click", (event) => {
      event.stopPropagation();
      tour?.kill();
      select(index);
    }),
  );
  return {
    arrive() {
      tour?.kill();
      tour = gsap
        .timeline()
        .call(() => select((current + 1) % items.length), [], 0.3)
        .call(() => select(initial), [], 2);
    },
    poke() {
      tour?.kill();
      select((current + 1) % items.length);
    },
    finish() {
      // A choice the visitor made stays; only an arrival tour is undone.
      if (tour?.isActive()) select(initial);
      tour?.kill();
    },
  };
}

function segmentedChoice(art: HTMLElement, holder: HTMLElement, key: string) {
  const outputs: string[] = JSON.parse(holder.dataset[key] ?? "[]");
  const items = all(".segmented > li:not(.segmented-thumb)", art);
  const output = one("[data-output], [data-history]", art)!;
  return choice(items, (index) => {
    items.forEach((item, position) =>
      item.classList.toggle("is-selected", position === index),
    );
    swapText(output, outputs[index] ?? "");
  });
}

function plan(art: HTMLElement): Performer {
  const chips = all("li", art);
  // The chosen refiner is raised with its status dot; the other sinks.
  return choice(chips, (index) =>
    chips.forEach((chip, position) => {
      const chosen = position === index;
      chip.classList.toggle("chip-strong", chosen);
      chip.classList.toggle("chip-muted", !chosen);
      const dot = one(".status-dot", chip);
      if (!dot) return;
      if (chosen) delete dot.dataset.tone;
      else dot.dataset.tone = "inactive";
    }),
  );
}

// ------------------------------------------------------------ one-shots

/** A tile whose graphic replays one short sequence from its start. */
function sequence(build: () => gsap.core.Timeline): Performer {
  let timeline: gsap.core.Timeline | null = null;
  const play = () => {
    if (timeline?.isActive()) return;
    timeline?.kill();
    timeline = build();
  };
  return {
    arrive: play,
    poke: play,
    finish: () => {
      // Run the remaining callbacks, so status lines land on their last state.
      timeline?.progress(1, false).kill();
      timeline = null;
    },
  };
}

function vocabulary(art: HTMLElement) {
  const wrong = one("[data-wrong]", art)!;
  const right = one("[data-right]", art)!;
  return sequence(() =>
    gsap
      .timeline()
      .set(wrong, { "--strike": 0 })
      .call(() => right.setAttribute("data-sunk", ""))
      .to(wrong, { "--strike": 1, duration: 0.5, ease: "power2.inOut" }, 0.5)
      // The dictionary's spelling rises from the surface (CSS transition).
      .call(() => right.removeAttribute("data-sunk"), [], ">+0.05")
      .to({}, { duration: 0.5 }),
  );
}

function fallback(art: HTMLElement) {
  // The app's status lines in the page's language (HomePage.astro).
  const status = one("[data-status]", art)!;
  const { busy = "Refining…", failed = "Refinement failed" } = status.dataset;
  const dot = one(".status-dot", art)!;
  const chip = status.parentElement!;
  const typed = words(one("[data-typed]", art)!);
  return sequence(() =>
    gsap
      .timeline({
        onComplete: () => art.classList.remove("is-typing"),
      })
      .set(typed, { display: "none" })
      .call(() => {
        status.textContent = busy;
        dot.dataset.tone = "busy";
      })
      .to({}, { duration: 1.2 })
      .call(() => {
        status.textContent = failed;
        dot.dataset.tone = "attention";
        art.classList.add("is-typing");
      })
      .to(chip, { x: -3, duration: 0.05, repeat: 5, yoyo: true })
      .set(chip, { x: 0 })
      .to(typed, { display: "inline", duration: 0, stagger: 0.07 }, "+=0.15"),
  );
}

function privacy(art: HTMLElement) {
  // A signal travels from the microphone to the caret; each stop it reaches
  // rises from its socket as it passes, and the cloud branch stays dark.
  const nodes = all(".art-node", art);
  const dots = all("[data-dot]", art);
  const hop = 0.55;
  return sequence(() => {
    const timeline = gsap.timeline({
      onComplete: () =>
        nodes.forEach((node) => node.classList.remove("is-lit")),
    });
    const light = (node: HTMLElement, at: number) =>
      timeline
        .call(() => node.classList.add("is-lit"), [], at)
        .call(() => node.classList.remove("is-lit"), [], at + 0.5);
    light(nodes[0], 0);
    dots.forEach((dot, index) => {
      const start = index * hop + 0.15;
      timeline
        .fromTo(
          dot,
          { x: 0, autoAlpha: 0 },
          {
            x: () => dot.parentElement?.offsetWidth ?? 0,
            duration: hop,
            ease: "none",
          },
          start,
        )
        .to(dot, { autoAlpha: 1, duration: 0.1 }, start)
        .to(dot, { autoAlpha: 0, duration: 0.1 }, start + hop - 0.1);
      if (nodes[index + 1]) light(nodes[index + 1], start + hop);
    });
    return timeline.to({}, { duration: 0.4 });
  });
}

// ------------------------------------------------------------- the grid

const bento = document.querySelector<HTMLElement>(".bento");
if (bento) setup(bento);

function setup(bento: HTMLElement) {
  const tiles = all(".tile", bento);
  const visible = new WeakMap<HTMLElement, boolean>();
  const tileOf = (art: string) =>
    tiles.find((tile) => one(`[data-art="${art}"]`, tile));
  const artOf = (tile: HTMLElement) => one("[data-art]", tile)!;

  const shortcutTile = tileOf("shortcut");
  const cursorTile = tileOf("cursor");
  const recorder = cursorTile
    ? cursor(artOf(cursorTile), () =>
        shortcutTile ? one(".keys", shortcutTile) : null,
      )
    : undefined;

  const performers = new Map<HTMLElement, Performer>();
  for (const tile of tiles) {
    const art = artOf(tile);
    let performer: Performer | undefined;
    switch (art.dataset.art) {
      case "cursor":
        performer = recorder;
        break;
      case "shortcut":
        performer = shortcut(
          art,
          recorder,
          () => Boolean(cursorTile && visible.get(cursorTile)),
          () => Boolean(visible.get(tile)),
        );
        break;
      case "profiles":
      case "script":
        performer = segmentedChoice(art, one(".art-profiles", art)!, "outputs");
        break;
      case "history":
        performer = segmentedChoice(art, one(".art-deck", art)!, "texts");
        break;
      case "plan":
        performer = plan(art);
        break;
      case "vocabulary":
        performer = vocabulary(art);
        break;
      case "fallback":
        performer = fallback(art);
        break;
      case "privacy":
        performer = privacy(art);
        break;
    }
    if (performer) performers.set(tile, performer);
  }

  bento.classList.add("is-live");

  // Pokes: a mouse entering a tile, or a tap on it. A poke within a second
  // of the last one is ignored, so sweeping across the grid stays calm.
  let lastPoke = new WeakMap<HTMLElement, number>();
  const poke = (tile: HTMLElement) => {
    if (reduced.matches) return;
    const now = performance.now();
    if (now - (lastPoke.get(tile) ?? -Infinity) < 1000) return;
    lastPoke.set(tile, now);
    performers.get(tile)?.poke();
  };
  for (const tile of performers.keys()) {
    tile.addEventListener("pointerenter", (event) => {
      if (event.pointerType === "mouse" && hover.matches) poke(tile);
    });
    tile.addEventListener("click", () => {
      if (!hover.matches) poke(tile);
    });
  }

  // Arrivals: once per tile, the tiles of a row one after another from the
  // left. A tile leaving the screen jumps to its resting frame.
  const arrived = new WeakSet<HTMLElement>();
  const column = (tile: HTMLElement) =>
    tiles
      .filter((other) => Math.abs(other.offsetTop - tile.offsetTop) < 4)
      .sort((a, b) => a.offsetLeft - b.offsetLeft)
      .indexOf(tile);
  const pending = new WeakMap<HTMLElement, gsap.core.Tween>();
  const watcher = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        const tile = entry.target as HTMLElement;
        const performer = performers.get(tile);
        visible.set(tile, entry.isIntersecting);
        tile.classList.toggle("is-onscreen", entry.isIntersecting);
        if (!entry.isIntersecting) {
          pending.get(tile)?.kill();
          performer?.finish();
          continue;
        }
        if (
          reduced.matches ||
          arrived.has(tile) ||
          entry.intersectionRatio < 0.55
        )
          continue;
        arrived.add(tile);
        lastPoke.set(tile, performance.now());
        pending.set(
          tile,
          gsap.delayedCall(0.25 + column(tile) * 0.22, () =>
            performer?.arrive(),
          ),
        );
      }
    },
    { threshold: [0, 0.55] },
  );
  for (const tile of tiles) watcher.observe(tile);

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) return;
    for (const performer of performers.values()) performer.finish();
  });
  reduced.addEventListener("change", () => {
    if (!reduced.matches) return;
    for (const performer of performers.values()) performer.finish();
    lastPoke = new WeakMap();
  });
}

export {};
