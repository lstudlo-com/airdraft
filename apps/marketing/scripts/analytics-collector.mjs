// Local browser fixture only. Receives the real SDK's requests without sending
// test traffic to PostHog. Run alongside PUBLIC_POSTHOG_LOCAL_TEST=true pnpm dev.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { gunzipSync } from "node:zlib";

const events = [];
const requests = [];
createServer(async (req, res) => {
  if (/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(req.headers.origin || ""))
    res.setHeader("Access-Control-Allow-Origin", req.headers.origin);
  res.setHeader("Access-Control-Allow-Headers", "*");
  const url = new URL(req.url, "http://127.0.0.1:4329");
  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }
  if (url.pathname === "/results") {
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ requests, events }));
    return;
  }
  requests.push({ method: req.method, path: url.pathname });
  if (url.pathname.endsWith("/web-vitals.js")) {
    res.setHeader("Content-Type", "text/javascript");
    res.end(
      await readFile(
        new URL(
          "../node_modules/posthog-js/dist/web-vitals.js",
          import.meta.url,
        ),
      ),
    );
    return;
  }
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (req.method === "POST") {
    try {
      let body = Buffer.concat(chunks);
      if (body[0] === 0x1f && body[1] === 0x8b) body = gunzipSync(body);
      else if (url.searchParams.get("compression") === "base64")
        body = Buffer.from(
          new URLSearchParams(body.toString()).get("data"),
          "base64",
        );
      const data = JSON.parse(body.toString());
      events.push(...(data.batch || (Array.isArray(data) ? data : [data])));
      console.log(
        JSON.stringify({
          received: events.length,
          names: events.map((event) => event.event),
        }),
      );
    } catch (error) {
      console.error("Cannot decode fixture request:", error.message);
      res.writeHead(400);
      res.end();
      return;
    }
  }
  res.setHeader("Content-Type", "application/json");
  res.end("{}");
}).listen(4329, "127.0.0.1", () =>
  console.log("Local analytics collector: http://127.0.0.1:4329/results"),
);
