import type { GuideSlug } from "../data/guides";

/**
 * The copy of every page outside the homepage and pricing (those live in
 * src/i18n/messages), one file per language in src/locales/<code>/pages.ts.
 * Long page bodies (guides, Support, Privacy) are Astro files beside it, and
 * the changelog's release notes are in changelog.ts. Every language has the
 * whole site: there are no English-only pages.
 */
export interface PageCopy {
  /** Shared by the guides and the guide hub. */
  chrome: {
    breadcrumb: string;
    home: string;
    guides: string;
    related: string;
  };
  notFound: { title: string; heading: string; action: string };
  hub: {
    title: string;
    description: string;
    heading: string;
    /** "Already set up and something is wrong?" + the link to Support. */
    help: [string, string];
    pricing: string;
    changes: string;
  };
  support: { title: string; description: string; heading: string };
  privacy: { title: string; description: string; heading: string };
  changelog: {
    title: string;
    description: string;
    heading: string;
    nav: string;
    latest: string;
    /** The first entry has no version. */
    source: string;
    releaseNotes: string;
    initialSource: string;
    /** The source link's accessible name, e.g. "Release notes for 0.14.0". */
    sourceFor: (label: string, version: string) => string;
    firstBuild: string;
    /** Before and after the link to Support. */
    availability: [string, string, string];
  };
  /** Each guide's title, search description and one-line hub summary. */
  guides: Record<
    GuideSlug,
    { title: string; description: string; summary: string }
  >;
}
