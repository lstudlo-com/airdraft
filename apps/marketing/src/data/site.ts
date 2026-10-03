const repository = "https://github.com/lstudlo-com/airdraft";

export const siteLinks = {
  source: repository,
  build: `${repository}#build`,
  issues: `${repository}/issues`,
  // Add the owner's confirmed profile URL before showing a donation action.
  buyMeACoffee: "",
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
  id: string;
  name: string;
  price: string;
  macs: string;
}

export const licenses: License[] = [
  { id: "one-mac", name: "1 Mac", price: "$29", macs: "one Mac" },
  { id: "three-macs", name: "3 Macs", price: "$49", macs: "up to three Macs" },
];

// What every license includes, in the order the pricing page lists it.
export const licenseIncludes = [
  "Every feature, ready to run",
  "No Xcode or build step",
  "14-day full-feature trial in the app",
  "Updates to the version you buy",
  "Deactivate a Mac yourself to move it",
];
