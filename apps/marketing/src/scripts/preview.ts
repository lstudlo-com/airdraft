type Profile = "clean" | "concise" | "summary";

const examples: Record<Profile, string> = {
  clean:
    "Hi Maya, I’ll send the draft tomorrow morning. Could we move our check-in to two?",
  concise:
    "Maya, I’ll send the draft tomorrow morning. Can we move our check-in to two?",
  summary:
    "Send Maya the draft tomorrow morning. Ask to move the check-in to two.",
};

const preview = document.querySelector<HTMLElement>("[data-preview]");
if (preview) setup(preview);

function setup(preview: HTMLElement) {
  const find = <T extends Element>(selector: string) =>
    preview.querySelector<T>(selector)!;
  const play = find<HTMLButtonElement>("[data-play]");
  const playLabel = find<HTMLElement>("[data-play-label]");
  const picker = find<HTMLElement>("[data-profile-picker]");
  const spoken = find<HTMLElement>("[data-spoken]");
  const result = find<HTMLElement>("[data-result]");
  const status = find<HTMLElement>("[data-status]");
  const hudLabel = find<HTMLElement>("[data-hud-label]");
  const bars = [...preview.querySelectorAll<HTMLElement>(".hud-bars span")];
  const profiles = [
    ...picker.querySelectorAll<HTMLButtonElement>("[data-profile]"),
  ];
  const fillers = [...spoken.querySelectorAll<HTMLElement>(".filler")];
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");

  // Wrap each spoken word so it can light up as it is "said". Filler phrases
  // stay one unit so their strike-through reads as a single correction.
  const words: HTMLElement[] = [];
  for (const node of [...spoken.childNodes]) {
    if (node instanceof HTMLElement) {
      node.classList.add("word");
      words.push(node);
      continue;
    }
    const parts = (node.textContent ?? "").split(/(\s+)/);
    const fragment = document.createDocumentFragment();
    for (const part of parts) {
      if (!part.trim()) {
        if (part) fragment.append(" ");
        continue;
      }
      const word = document.createElement("span");
      word.className = "word";
      word.textContent = part;
      fragment.append(word);
      words.push(word);
    }
    node.replaceWith(fragment);
  }

  let selected: Profile = "clean";
  let timers: number[] = [];
  let meter = 0;
  let level = 0.14;
  let running = false;
  let hasRun = false;
  let recorded = "0:04.6";
  let observer: IntersectionObserver | undefined;

  const at = (ms: number, action: () => void) => {
    timers.push(window.setTimeout(action, ms));
  };
  const stopTimers = () => {
    timers.forEach(clearTimeout);
    timers = [];
    window.clearInterval(meter);
  };
  const setLevels = (value: number) => {
    bars.forEach((bar, index) => {
      const shape =
        0.5 + 0.5 * Math.sin((Math.PI * (index + 0.5)) / bars.length);
      const jitter = value > 0.2 ? 0.55 + Math.random() * 0.45 : 1;
      bar.style.setProperty(
        "--level",
        Math.max(0.14, value * shape * jitter).toFixed(3),
      );
    });
  };
  const setRunning = (value: boolean) => {
    running = value;
    playLabel.textContent = value
      ? "Stop"
      : hasRun
        ? "Run again"
        : "Run sample";
  };
  const renderResult = (text: string) => {
    const paragraph = document.createElement("p");
    paragraph.textContent = text;
    const caret = document.createElement("span");
    caret.className = "caret";
    caret.setAttribute("aria-hidden", "true");
    paragraph.append(caret);
    result.replaceChildren(paragraph);
    return paragraph;
  };
  const renderPlaceholder = () => {
    const paragraph = document.createElement("p");
    paragraph.className = "placeholder";
    paragraph.textContent = "The text appears here when you let go.";
    result.replaceChildren(paragraph);
  };

  const finish = () => {
    stopTimers();
    words.forEach((word) => word.classList.add("said"));
    fillers.forEach((filler) => filler.classList.add("struck"));
    renderResult(examples[selected]);
    result.removeAttribute("aria-busy");
    setLevels(0.14);
    hudLabel.textContent = recorded;
    preview.dataset.state = "done";
    status.textContent = "";
    setRunning(false);
  };

  // Refine the finished transcript, then type the result at the "cursor".
  const refineAndType = (startAt: number) => {
    at(startAt, () => {
      preview.dataset.state = "refining";
      hudLabel.textContent = "Refining";
      status.textContent = "Refining…";
      fillers.forEach((filler, index) =>
        at(120 + index * 220, () => filler.classList.add("struck")),
      );
    });
    at(startAt + 760, () => {
      preview.dataset.state = "typing";
      result.setAttribute("aria-busy", "true");
      const paragraph = renderResult("");
      const caret = paragraph.lastChild!;
      const tokens = examples[selected].split(" ");
      tokens.forEach((token, index) =>
        at(index * 48, () =>
          paragraph.insertBefore(
            document.createTextNode(index ? ` ${token}` : token),
            caret,
          ),
        ),
      );
      at(tokens.length * 48 + 120, finish);
    });
  };

  const run = () => {
    stopTimers();
    observer?.disconnect();
    hasRun = true;
    setRunning(true);
    words.forEach((word) => word.classList.remove("said"));
    fillers.forEach((filler) => filler.classList.remove("struck"));
    renderPlaceholder();
    preview.dataset.state = "listening";
    status.textContent = "Listening…";

    const started = performance.now();
    level = 0.14;
    meter = window.setInterval(() => {
      const seconds = (performance.now() - started) / 1000;
      recorded = `0:${seconds.toFixed(1).padStart(4, "0")}`;
      hudLabel.textContent = recorded;
      setLevels(level);
    }, 70);

    let time = 280;
    for (const word of words) {
      const text = word.textContent ?? "";
      const isFiller = word.classList.contains("filler");
      at(time, () => {
        word.classList.add("said");
        level = isFiller ? 0.42 : 1;
      });
      time += isFiller ? 320 : 70 + text.length * 12;
      if (/[.,”]$/.test(text)) {
        at(time, () => (level = 0.14));
        time += 140;
      }
    }

    at(time, () => {
      window.clearInterval(meter);
      setLevels(0.14);
      preview.dataset.state = "decoding";
      hudLabel.textContent = "Decoding";
      status.textContent = "Transcribing…";
    });
    refineAndType(time + 520);
  };

  play.addEventListener("click", () => {
    if (running) {
      finish();
      return;
    }
    if (reducedMotion.matches) {
      hasRun = true;
      finish();
      return;
    }
    run();
  });

  profiles.forEach((button) => {
    button.addEventListener("click", () => {
      selected = button.dataset.profile as Profile;
      profiles.forEach((profile) =>
        profile.setAttribute("aria-pressed", String(profile === button)),
      );
      if (reducedMotion.matches) return finish();
      if (!hasRun) return run();
      stopTimers();
      setRunning(true);
      words.forEach((word) => word.classList.add("said"));
      refineAndType(0);
    });
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden && running) finish();
  });

  play.hidden = false;
  picker.hidden = false;

  // Play once, the first time most of the sample is on screen.
  if (reducedMotion.matches || !("IntersectionObserver" in window)) {
    finish();
    return;
  }
  preview.dataset.state = "idle";
  renderPlaceholder();
  setLevels(0.14);
  // A tall sample on a phone can never be 55% visible, so also accept it
  // filling most of the viewport.
  observer = new IntersectionObserver(
    (entries) => {
      const seen = entries.some(
        (entry) =>
          entry.intersectionRatio >= 0.55 ||
          entry.intersectionRect.height >= window.innerHeight * 0.5,
      );
      if (seen) run();
    },
    { threshold: Array.from({ length: 11 }, (_, index) => index / 10) },
  );
  observer.observe(preview);
}
