import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

// The key is a public domain-verification file, not an account credential.
// A normal invocation prints a payload without making any network request.
const dist = new URL("../dist/", import.meta.url);
const args = process.argv.slice(2);
if (args.some((argument) => argument !== "--submit")) {
  throw new Error("Usage: pnpm search:submit [--submit]");
}
const read = (path) => readFile(new URL(path, dist), "utf8");
const locations = (xml) =>
  [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) =>
    match[1].replaceAll("&amp;", "&"),
  );
const sitemapFiles = locations(await read("sitemap-index.xml"));
const canonicalOrigin = new URL(sitemapFiles[0]).origin;
const urlList = [];
for (const sitemap of sitemapFiles) {
  const url = new URL(sitemap);
  if (
    url.origin !== canonicalOrigin ||
    !/^\/sitemap[^/]*\.xml$/.test(url.pathname)
  ) {
    throw new Error(`Unexpected sitemap URL: ${sitemap}`);
  }
  urlList.push(...locations(await read(url.pathname.slice(1))));
}
if (!urlList.length || urlList.length > 10_000) {
  throw new Error("IndexNow requires between 1 and 10,000 URLs.");
}
for (const url of urlList) {
  const parsed = new URL(url);
  if (
    parsed.protocol !== "https:" ||
    parsed.origin !== canonicalOrigin ||
    parsed.search ||
    parsed.hash ||
    !parsed.pathname.endsWith("/")
  ) {
    throw new Error(`Unexpected canonical URL: ${url}`);
  }
}
const key = (await read("indexnow-key.txt")).trim();
if (!/^[A-Za-z0-9-]{8,128}$/.test(key))
  throw new Error("Invalid IndexNow key.");
const payload = {
  host: new URL(canonicalOrigin).host,
  key,
  keyLocation: `${canonicalOrigin}/indexnow-key.txt`,
  urlList: [...new Set(urlList)],
};
if (!args.includes("--submit")) {
  console.log(
    "Dry run: no network requests. After deployment, use --submit to notify participating search engines.",
  );
  console.log(JSON.stringify(payload, null, 2));
} else {
  const get = async (url) => {
    const response = await fetch(url, {
      redirect: "manual",
      signal: AbortSignal.timeout(15_000),
    });
    if (response.status !== 200) {
      throw new Error(
        `Public verification failed: ${url} returned ${response.status}. Nothing submitted.`,
      );
    }
    return response.text();
  };
  if ((await get(payload.keyLocation)).trim() !== key) {
    throw new Error(
      "Published IndexNow key differs from this build. Nothing submitted.",
    );
  }
  // Prevent notifying crawlers about a build that has not actually been published.
  for (const url of payload.urlList) {
    const path = new URL(url).pathname.slice(1) + "index.html";
    if ((await get(url)) !== (await read(path))) {
      throw new Error(
        `Published HTML differs from ${fileURLToPath(new URL(path, dist))}. Rebuild from the deployed sources before submission.`,
      );
    }
  }
  const response = await fetch("https://api.indexnow.org/indexnow", {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify(payload),
    redirect: "error",
    signal: AbortSignal.timeout(15_000),
  });
  if (response.status !== 200 && response.status !== 202) {
    throw new Error(
      `IndexNow returned ${response.status}: ${await response.text()}`,
    );
  }
  console.log(
    `IndexNow received ${payload.urlList.length} URLs (HTTP ${response.status}${response.status === 202 ? ", key validation pending" : ""}). This does not confirm crawling or indexing.`,
  );
}
