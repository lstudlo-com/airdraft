// Home's waveform as one folded metal ribbon (loaded by src/scripts/hero3d.ts).
//
// The app's Silk recording style, in the hero card's place: the forty bars
// of the HTML waveform fused into one ribbon of brushed metal whose width
// follows their heights, folding slowly along its length. It starts as a
// thread at the oldest bar, swells through the waveform and narrows back to
// nothing where the caret stands, so text lands at its vanishing point. One
// key light from the top left and front casts its shadow down and to the
// right on the island; a neutral studio, rendered once, gives the folds their
// sheen. Every colour is read from the page's tokens (global.css), so it
// follows light and dark.
//
// The HTML card stays underneath, invisible, and remains the truth: every
// frame the scene reads where its bars stand and how tall they are, so the
// pretend dictation (dictate.ts: a live bar at the caret, the oldest folding
// away, the new bar settling) and the narrow-screen bar counts shape the
// ribbon. Pressing and holding still lands on the HTML well under it.
//
// Motion. The ribbon draws itself from the left once when it arrives. At rest
// its folds travel slowly to the right while the key light, and so the
// shadow, stays at the top left. While a dictation records, its level swells
// the ribbon at the right end and travels left along it, the way the
// recording pill's meter scrolls. The pointer touches it where it is: near
// the pointer the ribbon opens toward the visitor, widens and leans toward
// the pointer, a small light travels with it across the metal, and moving
// the pointer sends ripples along the ribbon that run out both ways and
// fade. Nothing else moves with the pointer. As the hero scrolls away the
// ribbon comes apart from left to right into fine particles that gather
// into a living sound wave of three strands; scrolling back gathers them
// into the ribbon again. With reduced motion it draws one resting frame,
// again only when something changes, and nothing follows the pointer or the
// scroll. It draws only while the card is on screen and the tab is visible.

import {
  AdditiveBlending,
  BackSide,
  BoxGeometry,
  BufferAttribute,
  BufferGeometry,
  Color,
  DirectionalLight,
  DoubleSide,
  Mesh,
  MeshBasicMaterial,
  MeshPhysicalMaterial,
  NeutralToneMapping,
  NormalBlending,
  PerspectiveCamera,
  PlaneGeometry,
  PMREMGenerator,
  PointLight,
  Points,
  Scene,
  ShaderMaterial,
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
// Half the ribbon's width: nothing at its ends, a thread at rest, up to this
// much at a full bar.
const WIDTH = { thread: 3, full: 40 };
const LIFT = 46; // how far the ribbon floats above the island
// The canvas reaches past the card so the folds, the particles and the
// shadow have room.
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
const gauss = (d: number) => Math.exp(-d * d);

// A small deterministic random sequence, so every visit scatters the same way.
function random(seed: number) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// The particles: round, soft-edged points whose size and opacity each carry.
const dotVertex = /* glsl */ `
  attribute float size;
  attribute float alpha;
  attribute float tone;
  uniform float pixelRatio;
  varying float vAlpha;
  varying float vTone;
  void main() {
    vAlpha = alpha;
    vTone = tone;
    gl_PointSize = size * pixelRatio;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;
const dotFragment = /* glsl */ `
  uniform vec3 shade;
  uniform vec3 shine;
  varying float vAlpha;
  varying float vTone;
  void main() {
    vec2 p = gl_PointCoord - 0.5;
    float d = length(p);
    float edge = smoothstep(0.5, 0.28, d);
    if (edge * vAlpha < 0.01) discard;
    // Each grain somewhere between graphite and a bright glint, lit from
    // the top left like everything on the island.
    float lit = clamp(vTone + 0.22 * clamp(-(p.x + p.y) * 1.6, -1.0, 1.0), 0.0, 1.0);
    gl_FragColor = vec4(mix(shade, shine, lit), edge * vAlpha);
  }
`;

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
  key.shadow.mapSize.set(4096, 1024);
  key.shadow.radius = 14;
  key.shadow.blurSamples = 16;
  key.shadow.bias = -0.001;
  scene.add(key, key.target);

  // The small light the pointer carries across the metal.
  const glint = new PointLight(0xffffff, 0, 0, 0);
  scene.add(glint);

  // Brushed along its length under a thin clear coat.
  const ribbonMaterial = new MeshPhysicalMaterial({
    side: DoubleSide,
    metalness: 1,
    roughness: 0.28,
    anisotropy: 0.55,
    clearcoat: 0.45,
    clearcoatRoughness: 0.12,
  });
  const groundMaterial = new ShadowMaterial({ opacity: 0.2 });

  // The ribbon: a grid whose vertices are placed every frame.
  const columns = ALONG + 1;
  const rows = ACROSS + 1;
  const positions = new Float32Array(columns * rows * 3);
  const uvs = new Float32Array(columns * rows * 2);
  // The brushing runs along the ribbon. A fixed tangent keeps it even where
  // the ribbon narrows to a point (one derived from the texture
  // coordinates breaks into facets there).
  const tangents = new Float32Array(columns * rows * 4);
  const index: number[] = [];
  for (let i = 0; i < columns; i++) {
    for (let j = 0; j < rows; j++) {
      const k = i * rows + j;
      uvs[k * 2] = i / ALONG;
      uvs[k * 2 + 1] = j / ACROSS;
      tangents[k * 4] = 1;
      tangents[k * 4 + 3] = 1;
    }
  }
  for (let i = 0; i < ALONG; i++) {
    for (let j = 0; j < ACROSS; j++) {
      const a = i * rows + j;
      const b = a + rows;
      index.push(a, b, a + 1, b, b + 1, a + 1);
    }
  }
  const ribbonGeometry = new BufferGeometry();
  ribbonGeometry.setAttribute("position", new BufferAttribute(positions, 3));
  ribbonGeometry.setAttribute("uv", new BufferAttribute(uvs, 2));
  ribbonGeometry.setAttribute("tangent", new BufferAttribute(tangents, 4));
  ribbonGeometry.setIndex(index);
  const ribbon = new Mesh(ribbonGeometry, ribbonMaterial);
  ribbon.castShadow = true;
  ribbon.frustumCulled = false;

  const ground = new Mesh(new PlaneGeometry(1, 1), groundMaterial);
  ground.position.z = -LIFT;
  ground.receiveShadow = true;

  // The particles the ribbon comes apart into. Each has a home on the
  // ribbon (u along it, v across it), a strand of the sound wave it joins,
  // and its own scatter for the flight between them.
  const count = small.matches ? 1400 : 2600;
  const dotPositions = new Float32Array(count * 3);
  const dotAlpha = new Float32Array(count);
  const dotSize = new Float32Array(count);
  const dotTone = new Float32Array(count);
  const dots = {
    u: new Float32Array(count),
    v: new Float32Array(count),
    strand: new Uint8Array(count),
    late: new Float32Array(count),
    sx: new Float32Array(count),
    sy: new Float32Array(count),
    sz: new Float32Array(count),
    depth: new Float32Array(count),
    phase: new Float32Array(count),
  };
  {
    const next = random(0x41d7);
    for (let n = 0; n < count; n++) {
      dots.u[n] = (n + next()) / count;
      dots.v[n] = next() * 2 - 1;
      dots.strand[n] = n % 3;
      dots.late[n] = next();
      const angle = next() * Math.PI * 2;
      const reach = 8 + next() * 26;
      dots.sx[n] = Math.cos(angle) * reach;
      dots.sy[n] = Math.sin(angle) * reach * 0.8;
      dots.sz[n] = 30 + next() * 60;
      dots.depth[n] = (next() * 2 - 1) * 14;
      dots.phase[n] = next() * Math.PI * 2;
      dotSize[n] = 1.5 + next() * next() * 2.4;
      // Mostly graphite, some silver, a few glints.
      dotTone[n] = Math.pow(next(), 1.8);
    }
  }
  const dotGeometry = new BufferGeometry();
  dotGeometry.setAttribute("position", new BufferAttribute(dotPositions, 3));
  dotGeometry.setAttribute("alpha", new BufferAttribute(dotAlpha, 1));
  dotGeometry.setAttribute("size", new BufferAttribute(dotSize, 1));
  dotGeometry.setAttribute("tone", new BufferAttribute(dotTone, 1));
  const dotMaterial = new ShaderMaterial({
    uniforms: {
      shade: { value: new Color() },
      shine: { value: new Color() },
      pixelRatio: { value: 1 },
    },
    vertexShader: dotVertex,
    fragmentShader: dotFragment,
    transparent: true,
    depthWrite: false,
  });
  const particles = new Points(dotGeometry, dotMaterial);
  particles.frustumCulled = false;
  particles.visible = false;

  scene.add(ribbon, ground, particles);

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
    groundMaterial.opacity = night ? 0.5 : 0.16;
    key.intensity = night ? 1.6 : 2;
    scene.environmentIntensity = night ? 0.7 : 1.35;
    // The particles: from the ink, softened toward the island, to white,
    // so they read on it in both appearances without a hue or a glow.
    dotMaterial.uniforms.shade.value.copy(
      night
        ? token("--island").lerp(token("--ink"), 0.55)
        : token("--ink").lerp(token("--island"), 0.3),
    );
    dotMaterial.uniforms.shine.value.copy(
      night
        ? new Color(0xffffff)
        : token("--bar-top").lerp(new Color(0xffffff), 0.6),
    );
    dotMaterial.blending = night ? AdditiveBlending : NormalBlending;
    dotMaterial.needsUpdate = true;
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
      // Wider than the canvas, so the frustum's edges never cross the
      // island where it shows.
      shadow.left = -cw * 1.2;
      shadow.right = cw * 1.2;
      shadow.top = ch + 220;
      shadow.bottom = -ch - 220;
      shadow.near = 1000;
      shadow.far = 2000;
      shadow.updateProjectionMatrix();
    }
    if (w !== size.canvas.w || h !== size.canvas.h) {
      size.canvas = { w, h };
      const ratio = Math.min(devicePixelRatio, small.matches ? 1.5 : 2);
      renderer.setPixelRatio(ratio);
      renderer.setSize(w, h, false);
      dotMaterial.uniforms.pixelRatio.value = ratio;
      camera.aspect = w / h;
    }
    return true;
  }

  // Where the HTML bars are and how tall they stand, from their layout
  // boxes: the hover's magnification and the voice's stretch are transforms,
  // which the layout ignores. The live bar's height is its level; a bar
  // folding away (or arriving) counts by its share of a full width.
  const bars: Bar[] = [];
  const caretBox = { x: 0 };
  function read() {
    bars.length = 0;
    const origin = wave.offsetLeft + wave.offsetWidth / 2;
    for (const element of wave.children as HTMLCollectionOf<HTMLElement>) {
      const x = element.offsetLeft + element.offsetWidth / 2 - origin;
      if (element === caretEl) {
        caretBox.x = x;
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
  // the right end (newest on the right, like the pill's meter).
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

  // The pointer. Where it is over the hero (in scene units, from the card's
  // centre), how near the ribbon it hovers (0 … 1, eased in and out), and a
  // ripple field along the ribbon that its movement excites: a damped wave,
  // one value per ribbon column, that runs out both ways and fades.
  const pointer = { x: 0, y: 0, seen: false, moved: 0, near: 0, lastX: 0 };
  const field = new Float32Array(columns);
  const fieldSpeed = new Float32Array(columns);
  function onPointer(event: PointerEvent) {
    if (!visible || still.matches) return;
    if (event.pointerType === "touch" && event.buttons === 0) return;
    const rect = card.getBoundingClientRect();
    const scale = rect.width / (card.offsetWidth || 1) || 1;
    const x = (event.clientX - rect.left - rect.width / 2) / scale;
    const y = (rect.top + rect.height / 2 - event.clientY) / scale;
    if (pointer.seen) {
      pointer.moved += Math.hypot(x - pointer.x, y - pointer.y);
    }
    pointer.x = x;
    pointer.y = y;
    pointer.seen = true;
    schedule();
  }
  function onLeave() {
    pointer.seen = false;
  }

  // The ribbon's span, in scene units, measured each frame.
  const span = { left: 0, right: 0, length: 1 };

  // Advance the ripples by one fixed step (about 8 ms).
  function ripple() {
    const n = columns;
    for (let i = 0; i < n; i++) {
      const left = field[i > 0 ? i - 1 : 0];
      const right = field[i < n - 1 ? i + 1 : n - 1];
      const pull = 0.42 * (left + right - 2 * field[i]) - 0.004 * field[i];
      fieldSpeed[i] = (fieldSpeed[i] + pull) * 0.986;
    }
    for (let i = 0; i < n; i++) field[i] += fieldSpeed[i];
  }
  let fieldClock = 0;
  function excite(dt: number) {
    // Hover: how close to the ribbon's band the pointer is.
    const over =
      pointer.seen && pointer.x > span.left - 40 && pointer.x < span.right + 40;
    const target = over ? gauss(pointer.y / 120) : 0;
    pointer.near += (target - pointer.near) * Math.min(1, dt / 160);
    // Movement pushes the ribbon where the pointer crosses it, a little
    // more the faster it moves.
    const push = Math.min(28, pointer.moved) * pointer.near;
    pointer.moved = 0;
    if (push > 0.2) {
      const column = ((pointer.x - span.left) / span.length) * ALONG;
      const direction = Math.sign(pointer.x - pointer.lastX) || 1;
      for (let i = 0; i < columns; i++) {
        const d = (i - column) / 7;
        if (d > 3 || d < -3) continue;
        fieldSpeed[i] += push * 0.0045 * direction * gauss(d);
      }
    }
    pointer.lastX = pointer.x;
    // Run the field at a fixed step whatever the frame rate.
    fieldClock = Math.min(fieldClock + dt, 64);
    while (fieldClock >= 8) {
      ripple();
      fieldClock -= 8;
    }
  }

  let born = 0;
  function arrival(now: number) {
    if (still.matches) return 1;
    return ease((now - born - 150) / 1800);
  }

  // Per column, kept for the particles' homes: centre line, the two halves
  // of the ribbon's half-width vector, and its depth.
  const spine = {
    x: new Float32Array(columns),
    y: new Float32Array(columns),
    hy: new Float32Array(columns),
    hz: new Float32Array(columns),
  };

  // How far the ribbon has come apart: 0 whole … 1 all particles. The
  // break runs from the left end to the right over this share of the
  // ribbon's length.
  const BREAK = 0.42;
  const broken = (apart: number, u: number) =>
    smooth((apart * (1 + BREAK) - u) / BREAK);

  // Lay the ribbon out from the oldest bar to the caret, folding about its
  // own length.
  function shape(now: number, out: number, apart: number) {
    const moving = !still.matches;
    // Reduced motion rests on one chosen moment of the folds.
    const t = moving ? now / 1000 : 4;
    const left = (bars[0]?.x ?? -size.card.w / 2) - 10;
    const right = caretBox.x + 4;
    const length = Math.max(1, right - left);
    span.left = left;
    span.right = right;
    span.length = length;
    // A phone's shorter ribbon folds a little fewer times rather than
    // tighter, and is a little narrower.
    const reach = Math.min(1, Math.max(0.72, length / 680));
    const girth = Math.min(1, Math.max(0.62, length / 680));
    const hover = moving ? pointer.near : 0;
    for (let i = 0; i < columns; i++) {
      const u = i / ALONG;
      const x = left + u * length;
      // Drawn from the left as it arrives.
      const drawn = smooth((out * 1.25 - u) / 0.25);
      const distance = right - x;
      const swell = moving ? echo(Math.round(distance / 5)) : 0;
      const ripple = moving ? field[i] : 0;
      // Near the pointer the ribbon opens toward the visitor and widens.
      const lens = hover * gauss((x - pointer.x) / 95);
      const env = envelope(x) * (1 + swell * 0.6 * Math.exp(-distance / 260));
      // From a point at the oldest end, through the waveform, back to a
      // point where the caret stands.
      const taper = smooth(u / 0.1) * smooth((1 - u) / 0.17);
      const half =
        (WIDTH.thread + (WIDTH.full - WIDTH.thread) * env * girth) *
        taper *
        drawn *
        (1 + 0.42 * lens + 0.5 * Math.min(1, Math.abs(ripple)));
      // The fold: a slow half-turn travelling to the right, a second,
      // shorter one against it, the voice and the ripples adding to both.
      const turn =
        (1.15 * Math.sin(u * reach * 6.5 - t * 0.32) +
          0.35 * Math.sin(u * reach * 13 + t * 0.21 + 1.3) +
          swell *
            0.9 *
            Math.exp(-distance / 220) *
            Math.sin(u * reach * 12 - t * 3)) *
          (1 - 0.72 * lens) +
        ripple * 2.2;
      const cos = Math.cos(turn);
      const sin = Math.sin(turn);
      // A gentle rise and fall of the centre line, drawn a little toward
      // the pointer where it hovers.
      const y =
        5 * Math.sin(u * reach * 4.1 + t * 0.25) +
        lens * Math.max(-34, Math.min(34, pointer.y)) * 0.32 +
        ripple * 9;
      const z = lens * 16 + ripple * 26;
      spine.x[i] = x;
      spine.y[i] = y;
      spine.hy[i] = half * cos;
      spine.hz[i] = half * sin;
      // Coming apart, it narrows to nothing behind the break.
      const whole = 1 - broken(apart, u);
      for (let j = 0; j < rows; j++) {
        const v = (j / ACROSS) * 2 - 1;
        const k = (i * rows + j) * 3;
        positions[k] = x;
        positions[k + 1] = y + v * half * cos * whole;
        positions[k + 2] = z + v * half * sin * whole;
      }
    }
    ribbonGeometry.attributes.position.needsUpdate = true;
    ribbonGeometry.computeVertexNormals();
    ribbon.visible = apart < 0.999;
    ground.visible = ribbon.visible;
  }

  // The particles: each leaves the ribbon as the break passes its home,
  // flies out a little and settles on its strand of the sound wave.
  function scatter(now: number, apart: number) {
    particles.visible = apart > 0.001;
    if (!particles.visible) return;
    const t = now / 1000;
    const { left, length } = span;
    const wide = size.card.w / 2 + 12;
    for (let n = 0; n < count; n++) {
      const u = dots.u[n];
      // The break reaches each particle a little early or late.
      const flight = smooth(
        (apart * (1 + BREAK + 0.25) - u - dots.late[n] * 0.25) / BREAK,
      );
      const k = n * 3;
      if (flight <= 0) {
        dotAlpha[n] = 0;
        continue;
      }
      // Home: where it sat on the ribbon.
      const column = u * ALONG;
      const i0 = Math.min(ALONG - 1, Math.floor(column));
      const f = column - i0;
      const lerp = (array: Float32Array) =>
        array[i0] + (array[i0 + 1] - array[i0]) * f;
      const v = dots.v[n];
      const hx = lerp(spine.x);
      const hy = lerp(spine.y) + v * lerp(spine.hy);
      const hz = lerp(spine.hz) * v;
      // Its place on the wave: three strands of different lengths
      // travelling at different speeds, as tall as the waveform there,
      // closing at both ends.
      const x = -wide + u * wide * 2;
      const ribbonU = (x - left) / length;
      const swell = 0.6 + 1.4 * envelope(x);
      const window = Math.pow(Math.sin(Math.PI * clamp(u)), 0.8);
      const strand = dots.strand[n];
      const wavelength = [250, 168, 330][strand];
      const speed = [1.25, -1.7, 0.85][strand];
      const height = [24, 15, 10][strand];
      const ripple =
        field[Math.max(0, Math.min(ALONG, Math.round(ribbonU * ALONG)))] * 24;
      const ty =
        (height *
          swell *
          Math.sin((x / wavelength) * Math.PI * 2 - t * speed + strand * 2.1) +
          v * 2.2 +
          ripple) *
        window;
      const tz =
        dots.depth[n] * window +
        8 * Math.sin((x / 190) * Math.PI * 2 + t * 0.7 + dots.phase[n]);
      // On the way: an arc out of the ribbon toward the visitor, with a
      // little drift of its own.
      const e = flight * flight * (3 - 2 * flight);
      const arc = Math.sin(Math.PI * e);
      const wobble = arc * 6 * Math.sin(t * 1.3 + dots.phase[n]);
      dotPositions[k] = hx + (x - hx) * e + dots.sx[n] * arc + wobble;
      dotPositions[k + 1] = hy + (ty - hy) * e + dots.sy[n] * arc;
      dotPositions[k + 2] = hz + (tz - hz) * e + dots.sz[n] * arc;
      dotAlpha[n] = smooth(flight * 5) * (0.55 + 0.45 * window);
    }
    dotGeometry.attributes.position.needsUpdate = true;
    dotGeometry.attributes.alpha.needsUpdate = true;
  }

  function aim(apart: number) {
    const { w, h } = size.canvas;
    const distance = Math.max(w, h) * LENS;
    camera.fov = (2 * Math.atan(h / 2 / distance) * 180) / Math.PI;
    // The view rises a little as the wave forms, so its depth shows.
    const tilt = ((TILT + 10 * smooth((apart - 0.4) / 0.6)) * Math.PI) / 180;
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

  // The pointer's light: where the pointer is, in front of the ribbon,
  // brightest while it hovers near.
  function shine(apart: number) {
    const near = still.matches ? 0 : pointer.near * (1 - apart);
    glint.intensity = (dark.matches ? 1.4 : 2.2) * near;
    glint.position.set(pointer.x, pointer.y, 140);
  }

  let frame = 0;
  let visible = false;
  let drawn = false;
  let last = 0;

  function draw(now: number) {
    frame = 0;
    if (!visible || document.hidden) return;
    if (!layout()) return;
    const dt = last ? Math.min(64, now - last) : 16;
    last = now;
    read();
    listen();
    const apart = smooth((away() - 0.05) / 0.5);
    if (!still.matches) excite(dt);
    shape(now, arrival(now), apart);
    scatter(now, apart);
    shine(apart);
    aim(apart);
    renderer.render(scene, camera);
    if (!drawn) {
      drawn = true;
      card.classList.add("is-3d");
    }
    // With reduced motion one frame per change; otherwise every frame
    // while on screen.
    if (!still.matches) schedule();
    else last = 0;
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
  addEventListener("pointermove", onPointer, { passive: true });
  addEventListener("pointerdown", onPointer, { passive: true });
  document.documentElement.addEventListener("pointerleave", onLeave);

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
    removeEventListener("pointermove", onPointer);
    removeEventListener("pointerdown", onPointer);
    document.documentElement.removeEventListener("pointerleave", onLeave);
    card.classList.remove("is-3d");
    ribbonGeometry.dispose();
    dotGeometry.dispose();
    ground.geometry.dispose();
    for (const material of [ribbonMaterial, groundMaterial, dotMaterial])
      material.dispose();
    environment.dispose();
    pmrem.dispose();
    renderer.dispose();
    canvas.remove();
  }
  return dispose;
}
