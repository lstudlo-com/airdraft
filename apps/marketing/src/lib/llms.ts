import { changelog } from "../data/changelog";
import { license, licenses, siteLinks } from "../data/site";
import { href, type Locale } from "../i18n";
import type { Rich } from "../i18n/messages";

// Plain-text product facts for /llms.txt and /llms-full.txt, from the same
// data the pages use (src/data), so prices and availability never drift.

export function productFacts(): string {
  const onSale = Boolean(siteLinks.checkout);
  const prices = licenses
    .map((plan) => `${plan.price} for ${plan.macs}`)
    .join(" or ");
  const version = changelog.find((entry) => entry.version);
  return [
    "## Facts",
    "",
    "- Platform: macOS 15 or later on Apple silicon Macs.",
    `- Source code: open source under GPL-3.0-only (${license?.url ?? siteLinks.source}). Building it from source is free, includes every feature and needs Xcode.`,
    onSale
      ? `- Official app: a one-time license for personal use, ${prices} (US dollars, before tax), with a 14-day full-feature trial. On sale now.`
      : `- Official app: will be a one-time license for personal use, ${prices} (US dollars, before tax), with a 14-day full-feature trial. Not on sale yet, so there is no trial to download.`,
    `- Latest release: ${version ? `${version.version}, ${version.date}` : "see the changelog"}.`,
    "- Speech recognition and refinement each run on the Mac or with a cloud provider the user chooses, on their own API key stored in the Keychain. With local models, audio and text stay on the Mac.",
    "- Interface languages: English, Spanish, Japanese, Simplified Chinese and Traditional Chinese.",
  ].join("\n");
}

const targets: Record<string, string> = {
  pricing: "/pricing/",
  guides: "/guides/",
  meetingGuide: "/guides/private-meeting-transcription/",
  mixedGuide: "/guides/mixed-chinese-english-dictation/",
  agentGuide: "/guides/dictate-to-claude-code-and-terminals/",
  offlineGuide: "/guides/offline-dictation-on-mac/",
  localGuide: "/guides/local-vs-cloud-dictation/",
  comparison: "/guides/compare-mac-dictation-apps/",
};

/** A translated sentence as Markdown, its links absolute. */
export function richText(parts: Rich, locale: Locale, site: URL): string {
  return parts
    .map((part) =>
      typeof part === "string"
        ? part
        : `[${part.text}](${new URL(href(targets[part.link], locale), site).href})`,
    )
    .join("");
}
