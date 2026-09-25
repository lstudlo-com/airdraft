// The app icon's geometry, in icon points, mirrored from
// scripts/render-app-icon.swift (the "Edged, larger" design). The hero object
// and the header logo rebuild the icon in CSS 3D from these numbers; change
// them together with the Swift script.
export const icon = {
  side: 824,
  corner: 185,
  pill: { width: 744, height: 364 },
  ring: 47,
  levels: [0.36, 0.66, 1.0, 0.72, 0.48],
  bar: { width: 38, gap: 30, length: 190 },
  caret: { length: 208, gap: 20 },
};

const neutral = [174, 185, 204];
const violet = [107, 122, 255];
const cyan = [59, 195, 244];

const mix = (a: number[], b: number[], t: number) =>
  `rgb(${a.map((value, index) => Math.round(value + (b[index] - value) * t)).join(" ")})`;

export interface Mark {
  /** Left edge, relative to the pill's left edge, in px. */
  x: number;
  length: number;
  /** 0–1 loudness; the caret is 1. */
  level: number;
  top: string;
  bottom: string;
  caret: boolean;
}

/** The capsule's parts at `scale` px per icon point. */
export function capsule(scale: number) {
  const px = (value: number) => Number((value * scale).toFixed(2));
  const width = px(icon.pill.width);
  const height = px(icon.pill.height);
  const barWidth = px(icon.bar.width);
  const gap = px(icon.bar.gap);
  const caretGap = px(icon.caret.gap);
  const row = icon.levels.length * (barWidth + gap) + caretGap + barWidth;
  let x = (width - row) / 2;
  const marks: Mark[] = icon.levels.map((level, index) => {
    const t = ((index + 1) / (icon.levels.length + 1)) * 0.85;
    const mark = {
      x,
      length: px(icon.bar.length) * level,
      level,
      top: mix(neutral, violet, t),
      bottom: mix(neutral, cyan, t),
      caret: false,
    };
    x += barWidth + gap;
    return mark;
  });
  marks.push({
    x: x + caretGap,
    length: px(icon.caret.length),
    level: 1,
    top: "#6B7AFF",
    bottom: "#3BC3F4",
    caret: true,
  });
  return { width, height, ring: px(icon.ring), barWidth, marks };
}
