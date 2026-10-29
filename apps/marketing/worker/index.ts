// The site is static assets (wrangler.jsonc). A matching asset is served
// without this Worker, with the headers from public/_headers; the Worker
// runs only for subresource requests that match no asset. Those get the
// static 404 page with `Cache-Control: no-store`: under /_astro/ the
// _headers rule would otherwise mark the 404 immutable for a year, so a
// browser that asked for a new hashed file a moment before a deploy reached
// it kept the 404 and lost that script until the next build.
interface Env {
  ASSETS: { fetch(request: Request): Promise<Response> };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const missing = await env.ASSETS.fetch(request);
    const response = new Response(missing.body, missing);
    response.headers.set("Cache-Control", "no-store");
    response.headers.set("X-Content-Type-Options", "nosniff");
    response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
    response.headers.set(
      "Permissions-Policy",
      "microphone=(), camera=(), geolocation=()",
    );
    response.headers.set("X-Frame-Options", "DENY");
    return response;
  },
};
