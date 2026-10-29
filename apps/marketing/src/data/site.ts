const repository = "https://github.com/lstudlo-com/airdraft";

export const siteLinks = {
  source: repository,
  build: `${repository}#build`,
  issues: `${repository}/issues`,
  // GitHub's Watch menu (Custom ▸ Releases) notifies on each release.
  releases: `${repository}/releases`,
  // The production Polar checkout link (scripts/licensing-config.json
  // `checkout_url`). Leave empty while the merchant account is in test mode:
  // until it is set, license actions read "Not on sale yet" and are disabled.
  checkout: "",
};

// Link to the repository's GPL-3.0-only license.
export const license: { name: string; url: string } | null = {
  name: "License",
  url: `${repository}/blob/main/LICENSE`,
};

// The official app's licenses (vault: Strategy/Business Model). Both are
// one-time purchases for personal use with the same features; only the number
// of Macs that can be active at once differs. Prices are in US dollars before
// applicable tax. Change them only when the owner changes the Polar products.
export interface License {
  id: "one-mac" | "three-macs";
  /** The homepage's segmented choice. */
  name: string;
  /** The pricing page's plan title. */
  title: string;
  price: string;
  macs: string;
}

export const licenses: License[] = [
  {
    id: "one-mac",
    name: "1 Mac",
    title: "One Mac",
    price: "$29",
    macs: "one Mac",
  },
  {
    id: "three-macs",
    name: "3 Macs",
    title: "Three Macs",
    price: "$49",
    macs: "up to three Macs",
  },
];

// Each language's license names and the lists of what every license and
// the source build include are copy, in src/i18n/messages (`license.plans`,
// `pricing.licenseIncludes`, `pricing.sourceIncludes`). Both editions ship
// the same app, so dictation and Transcribe head both lists; the official
// app adds a 14-day full-feature trial, updates to the purchased version
// and moving between Macs, with no Xcode needed.
