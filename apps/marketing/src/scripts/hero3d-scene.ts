// Home's waveform as one folded metal ribbon (loaded by src/scripts/hero3d.ts).
//
// The app's Silk recording style, in the hero card's place: the forty bars
// of the HTML waveform fused into one ribbon of brushed metal whose width
// follows their heights, folding slowly along its length and running into
// the caret, a graphite pill, where text lands. One key light from the top
// left and front casts its shadow down and to the right on the island; a
// neutral studio, rendered once, gives the folds their sheen. Every colour is
// read from the page's tokens (global.css), so it follows light and dark.
//
// The HTML card stays underneath, invisible, and remains the truth: every
// frame the scene reads where its bars stand and how tall they are, so the
// pretend dictation (dictate.ts: a live bar at the caret, the oldest folding
// away, the new bar settling) and the narrow-screen bar counts shape the
// ribbon. Pressing and holding still lands on the HTML well under it. The
// hover's magnification (waveform.ts) and the voice (voice.ts) are transforms
// and do not reach the ribbon.
//
// Motion. The ribbon draws itself from the left into the caret once when it
// arrives. At rest its folds travel slowly toward the caret while the key
// light, and so the shadow, stays at the top left. While a dictation records,
// its level swells the ribbon at the caret and travels left along it, the way
// the recording pill's meter scrolls. As the hero scrolls away the folds
// relax and the ribbon settles flat onto the island. Nothing follows the
// pointer. With reduced motion it draws one resting frame, and again only
// when something changes. It draws only while the card is on screen and the
// tab is visible.

import {
  BackSide,
  BoxGeometry,
  BufferAttribute,
  BufferGeometry,
  CapsuleGeometry,
  Color,
  DirectionalLight,
  DoubleSide,
  Mesh,
  MeshBasicMaterial,
  MeshStandardMaterial,
  NeutralToneMapping,
  PerspectiveCamera,
  PlaneGeometry,
  PMREMGenerator,
  Scene,
  ShadowMaterial,
  SRGBColorSpace,
  VSMShadowMap,
  WebGLRenderer,
} from "three";

// Scene units are CSS pixels of the card. A long lens (the camera this many
// canvas widths away) keeps the ribbon's plane at one pixel a unit.
const LENS = 5;
const TILT = 12; // the view's rise above the island, in degrees
const ALONG = 220; // ribbon segments along its length
const ACROSS = 10; // and across it
const BAR_MAX = 32; // the HTML bars' full height (Waveform.astro)
const CARET = 40; // and the caret's
const CARET_SCALE = 1.5; // the graphite caret stands taller than the ribbon
// Half the ribbon's width: a thread at rest, up to this much at a full bar.
const WIDTH = { thread: 3, full: 38, caret: 18 };
const LIFT = 46; // how far the ribbon floats above the island
// The canvas reaches past the card so the folds and the shadow have room.
export const BLEED = { x: 56, top: 40, bottom: 60 };

interface Bar {
  x: number;
  h: number;
}

// The studio the metal reflects: a gray room with one large softbox up and to
// the left in front, where the key light is, a strip overhead and a faint
// fill from the right. Rendered once into an environment map.
function studio() {
  const room = new Scene();
  const parts: { dispose(): void }[] = [];
  const add = (
    size: [number, number],
    level: number,
    at: [number, number, number],
  ) => {
    const geometry = new PlaneGeometry(...size);
    const material = new MeshBasicMaterial({
      color: new Color().setScalar(level),
    });
    const panel = new Mesh(geometry, material);
    panel.position.set(...at);
    panel.lookAt(0, 0, 0);
    room.add(panel);
    parts.push(geometry, material);
  };
  const boxGeometry = new BoxGeometry(60, 40, 60);
  const boxMaterial = new MeshBasicMaterial({
    color: new Color().setScalar(0.22),
    side: BackSide,
  });
  room.add(new Mesh(boxGeometry, boxMaterial));
  parts.push(boxGeometry, boxMaterial);
  // Long strips along the ribbon's length: as it folds, each sweeps across
  // it as one band of light.
  add([70, 5], 6, [-6, 12, 16]); // key strip, up and to the left in front
  add([70, 2.5], 2.2, [0, -3, 20]); // a low, thin strip in front
  add([70, 6], 1.2, [0, 20, -4]); // overhead
  add([60, 10], 0.08, [0, -16, 6]); // dark floor in front
  add([60, 14], 1.4, [0, 2, 26]); // what the face reflects, square on
  return { room, dispose: () => parts.forEach((part) => part.dispose()) };
}

const clamp = (t: number) => Math.min(1, Math.max(0, t));
const ease = (t: number) => 1 - Math.pow(1 - clamp(t), 3);
const smooth = (t: number) => clamp(t) * clamp(t) * (3 - 2 * clamp(t));

export function mount(
  card: HTMLElement,
  canvas: HTMLCanvasElement,
  gl: WebGL2RenderingContext,
) {
  const wave = card.querySelector<HTMLElement>(".wave")!;
  const caretEl = wave.querySelector<HTMLElement>(".wave-caret")!;
  const stage = card.closest<HTMLElement>(".hero-stage") ?? card;
  const still = matchMedia("(prefers-reduced-motion: reduce)");
  const dark = matchMedia("(prefers-color-scheme: dark)");
  const small = matchMedia("(max-width: 700px), (pointer: coarse)");

  const renderer = new WebGLRenderer({ canvas, context: gl, alpha: true });
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.toneMapping = NeutralToneMapping;
  renderer.setClearColor(0x000000, 0);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = VSMShadowMap;

  const scene = new Scene();
  const pmrem = new PMREMGenerator(renderer);
  const room = studio();
  const environment = pmrem.fromScene(room.room, 0.02).texture;
  room.dispose();
  scene.environment = environment;

  const camera = new PerspectiveCamera(10, 2, 50, 20000);

  // Light from the top left and in front, as on every surface of the site.
  const key = new DirectionalLight(0xffffff, 2);
  key.position.set(-0.62, 0.8, 1).normalize().multiplyScalar(1500);
  key.castShadow = true;
  key.shadow.mapSize.set(2048, 512);
  key.shadow.radius = 14;
  key.shadow.blurSamples = 16;
  key.shadow.bias = -0.001;
  scene.add(key, key.target);

  const ribbonMaterial = new MeshStandardMaterial({
    side: DoubleSide,
    metalness: 1,
    roughness: 0.26,
  });
  const caretMaterial = new MeshStandardMaterial({
    metalness: 0.5,
    roughness: 0.35,
  });
  const groundMaterial = new ShadowMaterial({ opacity: 0.2 });

  // The ribbon: a grid whose vertices are placed every frame.
  const columns = ALONG + 1;
  const rows = ACROSS + 1;
  const positions = new Float32Array(columns * rows * 3);
  const index: number[] = [];
  for (let i = 0; i < ALONG; i++) {
    for (let j = 0; j < ACROSS; j++) {
      const a = i * rows + j;
      const b = a + rows;
      index.push(a, b, a + 1, b, b + 1, a + 1);
    }
  }
  const ribbonGeometry = new BufferGeometry();
  ribbonGeometry.setAttribute("position", new BufferAttribute(positions, 3));
  ribbonGeometry.setIndex(index);
  const ribbon = new Mesh(ribbonGeometry, ribbonMaterial);
  ribbon.castShadow = true;
  ribbon.frustumCulled = false;

  // The caret: a pill as wide and as tall as the HTML caret.
  const caretGeometry = new CapsuleGeometry(5, CARET * CARET_SCALE - 10, 8, 24);
  const caret = new Mesh(caretGeometry, caretMaterial);
  caret.castShadow = true;

  const ground = new Mesh(new PlaneGeometry(1, 1), groundMaterial);
  ground.position.z = -LIFT;
  ground.receiveShadow = true;
  scene.add(ribbon, caret, ground);

  function readColours() {
    const style = getComputedStyle(document.documentElement);
    const token = (name: string) =>
      new Color(style.getPropertyValue(name).trim());
    const night = dark.matches;
    // Light: the bars' silver; dark: the caret's lighter graphite, which
    // the dark island needs to read as metal.
    ribbonMaterial.color.copy(
      night ? token("--caret-top") : token("--bar-top"),
    );
    caretMaterial.color.copy(
      token("--caret-top").lerp(token("--caret-bottom"), 0.5),
    );
    groundMaterial.opacity = night ? 0.5 : 0.16;
    key.intensity = night ? 1.6 : 2;
    scene.environmentIntensity = night ? 0.7 : 1.35;
  }

  // Sizes, in CSS pixels.
  const size = { card: { w: 0, h: 0 }, canvas: { w: 0, h: 0 } };
  function layout() {
    const cw = card.offsetWidth;
    const ch = card.offsetHeight;
    if (!cw || !wave.offsetWidth) return false;
    // On phones the island clips what reaches past its edge.
    const w = cw + BLEED.x * 2;
    const h = ch + BLEED.top + BLEED.bottom;
    if (cw !== size.card.w || ch !== size.card.h) {
      size.card = { w: cw, h: ch };
      ground.scale.set(cw * 3, ch * 10, 1);
      const shadow = key.shadow.camera;
      shadow.left = -cw * 0.7;
      shadow.right = cw * 0.7;
      shadow.top = ch + 120;
      shadow.bottom = -ch - 120;
      shadow.near = 1000;
      shadow.far = 2000;
      shadow.updateProjectionMatrix();
    }
    if (w !== size.canvas.w || h !== size.canvas.h) {
      size.canvas = { w, h };
      renderer.setPixelRatio(
        Math.min(devicePixelRatio, small.matches ? 1.5 : 2),
      );
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
    }
    return true;
  }

  // Where the HTML bars are and how tall they stand, from their layout
  // boxes: the hover's magnification and the voice's stretch are transforms,
  // which the layout ignores, so the ribbon never follows the pointer. The
  // live bar's height is its level; a bar folding away (or arriving) counts by
  // its share of a full width. The caret's flare is the one transform read.
  const bars: Bar[] = [];
  const caretBox = { x: 0, h: CARET };
  function read() {
    bars.length = 0;
    const origin = wave.offsetLeft + wave.offsetWidth / 2;
    for (const element of wave.children as HTMLCollectionOf<HTMLElement>) {
      const x = element.offsetLeft + element.offsetWidth / 2 - origin;
      if (element === caretEl) {
        const scale =
          wave.getBoundingClientRect().width / (wave.offsetWidth || 1) || 1;
        caretBox.x = x;
        caretBox.h =
          element.getBoundingClientRect().height / scale ||
          element.offsetHeight;
        continue;
      }
      const width = element.offsetWidth;
      if (width < 0.05) continue;
      const live = element.classList.contains("is-live")
        ? Number(element.style.getPropertyValue("--live")) || 0.15
        : 1;
      bars.push({ x, h: element.offsetHeight * live * Math.min(1, width / 7) });
    }
  }

  // The bars' heights, smoothed along the ribbon: 0 … about 1.
  function envelope(x: number) {
    let sum = 0;
    let weight = 0;
    for (const bar of bars) {
      const d = (x - bar.x) / 40;
      if (d > 3 || d < -3) continue;
      const k = Math.exp(-d * d);
      sum += bar.h * k;
      weight += k;
    }
    return weight > 0.05 ? sum / weight / BAR_MAX : 0;
  }

  // The newest dictation level, kept for the swell that travels left from
  // the caret (newest on the right, like the pill's meter).
  const history = new Float32Array(300);
  let head = 0;
  let level = 0;
  function listen() {
    const live = wave.querySelector<HTMLElement>(".wave-bar.is-live");
    const target = live
      ? Number(live.style.getPropertyValue("--live")) || 0
      : 0;
    level += (target - level) * 0.3;
    head = (head + 1) % history.length;
    history[head] = level;
  }
  const echo = (framesAgo: number) =>
    history[
      (head - Math.min(history.length - 1, framesAgo) + history.length) %
        history.length
    ];

  let born = 0;
  function arrival(now: number) {
    if (still.matches) return 1;
    return ease((now - born - 150) / 1800);
  }

  // Lay the ribbon out from the oldest bar to the caret, folding about its
  // own length.
  function shape(now: number, out: number, settle: number) {
    const moving = !still.matches;
    // Reduced motion rests on one chosen moment of the folds.
    const t = moving ? now / 1000 : 4;
    const left = (bars[0]?.x ?? -size.card.w / 2) - 10;
    const right = caretBox.x - 6;
    const length = Math.max(1, right - left);
    const fold = 1 - settle;
    // A phone's shorter ribbon folds a little fewer times rather than
    // tighter, and is a little narrower.
    const reach = Math.min(1, Math.max(0.72, length / 680));
    const girth = Math.min(1, Math.max(0.62, length / 680));
    for (let i = 0; i < columns; i++) {
      const u = i / ALONG;
      const x = left + u * length;
      // Drawn from the left as it arrives.
      const drawn = smooth((out * 1.25 - u) / 0.25);
      const distance = right - x;
      const swell = moving ? echo(Math.round(distance / 5)) : 0;
      const env =
        envelope(x) * (1 + swell * 0.6 * Math.exp(-distance / 260)) * fold;
      // Thin at the oldest end; it narrows into the caret.
      const taper = smooth(u / 0.08);
      const into = smooth(distance / 90);
      const half =
        (WIDTH.thread + (WIDTH.full - WIDTH.thread) * env * girth) *
          taper *
          drawn *
          into +
        WIDTH.caret * (1 - into) * drawn;
      // The fold: a slow half-turn travelling toward the caret, a second,
      // shorter one against it, and the voice adding to both. Square to the
      // visitor where it meets the caret.
      const turn =
        (1.15 * Math.sin(u * reach * 6.5 - t * 0.32) +
          0.35 * Math.sin(u * reach * 13 + t * 0.21 + 1.3) +
          swell *
            0.9 *
            Math.exp(-distance / 220) *
            Math.sin(u * reach * 12 - t * 3)) *
        fold *
        smooth(distance / 70);
      const cos = Math.cos(turn);
      const sin = Math.sin(turn);
      // A gentle rise and fall of the ribbon's centre line.
      const y = 5 * Math.sin(u * reach * 4.1 + t * 0.25) * fold;
      for (let j = 0; j < rows; j++) {
        const v = (j / ACROSS) * 2 - 1;
        const k = (i * rows + j) * 3;
        positions[k] = x;
        positions[k + 1] = y + v * half * cos;
        positions[k + 2] = v * half * sin - (LIFT - 2) * settle;
      }
    }
    ribbonGeometry.attributes.position.needsUpdate = true;
    ribbonGeometry.computeVertexNormals();

    caret.position.set(caretBox.x, 0, -(LIFT - 4) * settle);
    caret.scale.set(1, (caretBox.h / CARET) * (0.3 + 0.7 * out), 1);
  }

  function aim(settle: number) {
    const { w, h } = size.canvas;
    const distance = Math.max(w, h) * LENS;
    camera.fov = (2 * Math.atan(h / 2 / distance) * 180) / Math.PI;
    const tilt = (TILT * (1 - settle) * Math.PI) / 180;
    camera.setViewOffset(w, h, 0, -(BLEED.top - BLEED.bottom) / 2, w, h);
    camera.position.set(
      0,
      distance * Math.sin(tilt),
      distance * Math.cos(tilt),
    );
    camera.near = distance - 800;
    camera.far = distance + 800;
    camera.lookAt(0, 0, 0);
    camera.updateProjectionMatrix();
  }

  // How far the hero has scrolled away: 0 at rest … 1 mostly gone.
  function away() {
    if (still.matches) return 0;
    const rect = stage.getBoundingClientRect();
    return clamp(-rect.top / (rect.height * 0.7));
  }

  let frame = 0;
  let visible = false;
  let drawn = false;

  function draw(now: number) {
    frame = 0;
    if (!visible || document.hidden) return;
    if (!layout()) return;
    read();
    listen();
    const settle = smooth(away());
    shape(now, arrival(now), settle);
    aim(settle);
    renderer.render(scene, camera);
    if (!drawn) {
      drawn = true;
      card.classList.add("is-3d");
    }
    // With reduced motion one frame per change; otherwise every frame
    // while on screen.
    if (!still.matches) schedule();
  }
  function schedule() {
    if (!frame) frame = requestAnimationFrame(draw);
  }
  // With reduced motion, draw again when the card changes (a held
  // dictation, a new bar) or resizes.
  const watch = new MutationObserver(() => schedule());
  watch.observe(card, {
    attributes: true,
    attributeFilter: ["class", "style"],
    childList: true,
    subtree: true,
  });
  const resize = new ResizeObserver(() => schedule());
  resize.observe(card);
  const onScreen = new IntersectionObserver(
    ([entry]) => {
      visible = entry.isIntersecting;
      if (visible) schedule();
    },
    { rootMargin: `${BLEED.top}px 0px ${BLEED.bottom}px 0px` },
  );
  onScreen.observe(card);
  const onVisibility = () => {
    if (!document.hidden) schedule();
  };
  document.addEventListener("visibilitychange", onVisibility);
  const onChange = () => {
    readColours();
    schedule();
  };
  dark.addEventListener("change", onChange);
  still.addEventListener("change", onChange);
  small.addEventListener("change", onChange);
  const onLost = (event: Event) => {
    event.preventDefault();
    dispose();
  };
  canvas.addEventListener("webglcontextlost", onLost);

  readColours();
  card.prepend(canvas);
  born = performance.now();
  schedule();

  function dispose() {
    cancelAnimationFrame(frame);
    watch.disconnect();
    resize.disconnect();
    onScreen.disconnect();
    document.removeEventListener("visibilitychange", onVisibility);
    dark.removeEventListener("change", onChange);
    still.removeEventListener("change", onChange);
    small.removeEventListener("change", onChange);
    canvas.removeEventListener("webglcontextlost", onLost);
    card.classList.remove("is-3d");
    ribbonGeometry.dispose();
    caretGeometry.dispose();
    ground.geometry.dispose();
    for (const material of [ribbonMaterial, caretMaterial, groundMaterial])
      material.dispose();
    environment.dispose();
    pmrem.dispose();
    renderer.dispose();
    canvas.remove();
  }
  return dispose;
}
