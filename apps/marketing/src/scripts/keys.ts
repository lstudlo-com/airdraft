// Keycaps follow the visitor's own keyboard: pressing Control or Option sinks
// every ⌃ or ⌥ keycap on the page (kbd[data-key]) until it is released, the
// way the app's shortcut recorder answers a held key. Decorative only.

const caps = [...document.querySelectorAll<HTMLElement>("kbd[data-key]")];

if (caps.length) {
  const press = (key: string, down: boolean) => {
    for (const cap of caps) {
      if (cap.dataset.key === key) cap.classList.toggle("is-down", down);
    }
  };
  window.addEventListener("keydown", (event) => press(event.key, true));
  window.addEventListener("keyup", (event) => press(event.key, false));
  window.addEventListener("blur", () => {
    for (const cap of caps) cap.classList.remove("is-down");
  });
}

export {};
