import type { APIRoute } from "astro";
import { changelogFeed } from "../../lib/changelog-feed";

export const GET: APIRoute = ({ site }) => {
  if (!site) throw new Error("The changelog feed requires Astro.site.");
  return changelogFeed("es", site);
};
