// Fails when a colour with a hue appears in the website's source. The site
// uses the app window's neutral grays only; the three status dots
// (--status-ok, --status-attention, --status-busy) are the one exception, as
// in the app. Run from apps/marketing: node scripts/check-neutral.mjs
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const root = new URL("../src/", import.meta.url).pathname;
// Channels may differ by this much (0–255) and still count as gray.
const tolerance = 2;
const named =
  /\b(red|blue|green|purple|violet|indigo|cyan|teal|magenta|orange|yellow|pink|navy|aqua|lime|olive|maroon|fuchsia)\b/;

function* files(directory) {
  for (const name of readdirSync(directory)) {
    const path = join(directory, name);
    if (statSync(path).isDirectory()) yield* files(path);
    else if (/\.(css|astro|ts)$/.test(name)) yield path;
  }
}

const hexChannels = (hex) => {
  const digits =
    hex.length <= 4
      ? [...hex.slice(0, 3)].map((d) => d + d)
      : [hex.slice(0, 2), hex.slice(2, 4), hex.slice(4, 6)];
  return digits.map((pair) => parseInt(pair, 16));
};
const isGray = ([r, g, b]) =>
  Math.max(r, g, b) - Math.min(r, g, b) <= tolerance;

const problems = [];
for (const path of files(root)) {
  const lines = readFileSync(path, "utf8").split("\n");
  lines.forEach((line, index) => {
    if (/--status-(ok|attention|busy)\s*:/.test(line)) return;
    const where = `${relative(root, path)}:${index + 1}`;
    for (const match of line.matchAll(
      /(?<=[\s:(,"'])#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})(?=[\s;,)"'])/g,
    )) {
      if (!isGray(hexChannels(match[1]))) problems.push(`${where} ${match[0]}`);
    }
    for (const match of line.matchAll(
      /rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)/g,
    )) {
      if (!isGray(match.slice(1, 4).map(Number)))
        problems.push(`${where} ${match[0]})`);
    }
    for (const match of line.matchAll(
      /\b(hsla?|oklch|oklab|lch|lab)\([^)]*\)/g,
    )) {
      problems.push(`${where} ${match[0]}`);
    }
    if (
      path.endsWith(".css") &&
      /^\s*[\w-]+\s*:/.test(line) &&
      named.test(line)
    ) {
      problems.push(`${where} ${line.trim()}`);
    }
  });
}

if (problems.length) {
  console.error(
    `Colours with a hue (the site is neutral gray, status dots excepted):\n  ${problems.join("\n  ")}`,
  );
  process.exit(1);
}
console.log("check-neutral: no hued colours.");
