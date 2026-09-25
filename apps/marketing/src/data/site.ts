const repository = "https://github.com/lstudlo-com/airdraft";

export const siteLinks = {
  source: repository,
  build: `${repository}#build`,
  issues: `${repository}/issues`,
  // Add the owner's confirmed profile URL before showing a donation action.
  buyMeACoffee: "",
};

// Shown only when a LICENSE file exists in the repository. Never guess a name.
export const license: { name: string; url: string } | null = null;

// The paid offering appears on the pricing page only once it is real. Every
// field comes from the owner; do not invent a price, feature or date.
export const paidPlan: {
  name: string;
  price: string;
  period?: string;
  description: string;
  features: string[];
  url: string;
  action: string;
} | null = null;
