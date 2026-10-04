# Search implementation

This is the website's implementation and operating contract. Research, launch
status and dated verification belong in the Airdraft vault. The primary sources
below were checked on **2026-10-05**. Recheck them before changing crawler policy
or making claims about search features.

## Discovery and content

- Keep the useful content, navigation and product answers in the built HTML.
  Use normal links, descriptive headings and stable section IDs. Interactive
  samples supplement the text; they must not be the only description of a feature.
- Every indexable page needs a unique title, useful description, canonical URL
  on `https://airdraft.app`, and an internal link from a relevant page. The
  sitemap contains canonical HTML pages, excluding the 404 and utility files.
- `public/_redirects` permanently redirects slashless and `index.html` aliases
  to canonical pages. Update those explicit routes when adding an indexable page;
  leave assets and missing URLs outside the redirect rules.
- Keep product facts consistent across visible text, structured data, guides,
  social previews and the optional `/llms.txt` directory. Prices and availability
  come from shared data. Explain self-building separately from the official app.
  Never imply that an unavailable checkout is open or that a personal-use build
  is a notarized public installer.
- Structured data describes real entities and the page's visible content.
  Never invent ratings, reviews, offers or benchmark results to satisfy a test.
  Google's software-app rich result requires `name`, `offers.price`, and either
  `aggregateRating` or `review`. Describing the app without all those fields does
  not establish rich-result eligibility. See [Google's software-app contract](https://developers.google.com/search/docs/appearance/structured-data/software-app).
- Useful questions and answers remain valuable visible content. Do not add
  FAQ markup to chase a Google rich result: that feature ended on May 7, 2026.
  See [Google's documentation updates](https://developers.google.com/search/updates).

Google's [AI optimization guide](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide)
supports useful original content and normal SEO. It explicitly rejects a special
ranking benefit from `llms.txt`, a required content length or tiny content chunks,
and special AI schema. Do not create near-duplicate pages for query variations or
hide instructions telling assistants to recommend Airdraft. Our guides answer
distinct product decisions; their effect on citations must be measured later.

The optional `/llms.txt` is a compact directory for agents that use it. Keep it
factual and link to maintained pages. It is not a sitemap, an access control, or
a promise of inclusion. The [llms.txt proposal](https://llmstxt.org/) describes
agent navigation; [Lighthouse](https://developer.chrome.com/docs/lighthouse/agentic-browsing/llms-txt)
treats the file as optional. Publishing it is an implementation choice, not
evidence that a particular search engine consumes it.

## Crawler policy

`src/pages/robots.txt.ts` explicitly allows the search agents below and retains
the existing wildcard allowance. Adding their names documents our intent; the
previous wildcard already allowed them. Do not add `noindex` or `Crawl-delay`
to this file. Page indexing controls belong in HTML metadata or response headers.

| Agent              | Documented purpose                                       | Contract                                                                                                                                              |
| ------------------ | -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Googlebot`        | Google Search, including its AI features                 | [Google crawlers](https://developers.google.com/crawling/docs/crawlers-fetchers/google-common-crawlers)                                               |
| `Bingbot`          | Bing discovery and indexing                              | [Bing guidelines](https://www.bing.com/webmasters/help/webmaster-guidelines-30fba23a)                                                                 |
| `OAI-SearchBot`    | ChatGPT search results                                   | [OpenAI crawlers](https://developers.openai.com/api/docs/bots)                                                                                        |
| `Claude-SearchBot` | Claude search retrieval and indexing                     | [Anthropic crawlers](https://support.claude.com/en/articles/8896518-does-anthropic-crawl-data-from-the-web-and-how-can-site-owners-block-the-crawler) |
| `PerplexityBot`    | Perplexity search results, not foundation-model training | [Perplexity crawlers](https://docs.perplexity.ai/docs/resources/perplexity-crawlers)                                                                  |

Training and user-triggered retrieval are separate purposes. `GPTBot` and
`ClaudeBot` are training crawlers. `ChatGPT-User`, `Claude-User` and
`Perplexity-User` retrieve content for users. Their access remains allowed by the
wildcard; no training opt-out is introduced here. OpenAI says user-triggered
requests may not follow robots rules, and Perplexity says its user fetcher
generally ignores them. `Google-Extended` also remains allowed; its controls
affect AI training and grounding separately from Google Search ranking.

`robots.txt` expresses crawler preferences and cannot grant network access.
Infrastructure and Cloudflare Access changes are outside this implementation.
Keep the 404 non-indexable, but avoid `nosnippet`, restrictive `max-snippet`, or
`data-nosnippet` on public product answers. Google requires snippet eligibility
for AI supporting links. See [Google's AI features contract](https://developers.google.com/search/docs/appearance/ai-features).

## Build and local verification

Run from the repository root:

```sh
pnpm check:marketing
pnpm build:marketing
pnpm preview:marketing
```

The build runs `python3 scripts/check-search.py` from this marketing directory
against generated output. To check a running preview, use its actual reported
port:

```sh
python3 apps/marketing/scripts/check-search.py --base-url http://127.0.0.1:PORT
```

Inspect desktop and mobile pages with JavaScript enabled and disabled. Check
that useful text and links remain available, canonical URLs agree with the
sitemap, robots rules allow the listed agents, JSON-LD parses and matches the
page, social images resolve, and missing paths return 404. These checks prove
the delivered implementation, not actual crawling, indexing or AI citations.

## Verification and launch operations

`GOOGLE_SITE_VERIFICATION` and `BING_SITE_VERIFICATION` are optional build-time
environment variables. Set the exact ownership token supplied by the relevant
console to emit its verification meta tag, then rebuild. They do not create
accounts, verify ownership automatically, submit a sitemap or change indexing.
Keep unset values absent from the HTML. Domain-level DNS verification is also
available through the respective console.

When the public site is available, the owner can verify it in Google Search
Console and Bing Webmaster Tools, submit `/sitemap-index.xml`, inspect important
URLs, and record the date and deployed source commit in the vault. Check that
Search Console's [generative AI control](https://support.google.com/webmasters/answer/16908024)
includes the site. Inclusion is the default and can inherit from a parent
property; repository code cannot verify that account setting.

The changelog feed at `/changelog.xml` uses existing release data. Source dates
record calendar days in Asia/Taipei; RSS represents each day as midnight in that
timezone, not an observed publication timestamp. Keep source links and stable
entry IDs. `/indexnow-key.txt` provides the public IndexNow ownership key.
Preview a submission with:

```sh
pnpm --filter @airdraft/marketing search:submit
```

The command validates the built files and defaults to a dry run with no network
requests. It prepares the current sitemap's canonical pages for first
publication or refresh; it does not notify deleted URLs or maintain a change
history. Rebuild before using it. For an authorized public submission, use:

```sh
pnpm --filter @airdraft/marketing search:submit --submit
```

Submission first verifies the live key and compares every page's HTML with this
build. Redirects, unavailable pages and mismatches stop the submission. Exact
HTML comparison can conservatively reject harmless CDN transformations; resolve
the difference before retrying. A successful IndexNow notification is not an
indexing or ranking guarantee. Setting up these commands does not mean a
submission or launch has occurred.

Measure search clicks, impressions and landing pages alongside referrals and
real acquisition outcomes. Use Search Console's [generative AI performance
report](https://support.google.com/webmasters/answer/16984139) for AI impressions
and [Bing AI Performance](https://blogs.bing.com/webmaster/2026/2/Introducing-AI-Performance-in-Bing-Webmaster-Tools-Public-Preview/)
for citations, cited pages and grounding queries. Google's report is documented
as rolled out worldwide on August 31, 2026, but low-impression sites may not see
it. Bing also documents preview [intent, topic, citation-share and comparison
views](https://blogs.bing.com/search/2026/6/New-AI-Visibility-Insights-in-Bing-Webmaster-Tools-Intents-Topics-Citation-Share-Compare/).
Citations are not visits, conversions or rankings. Compare equivalent periods
and retain page versions; changes in demand or models prevent attributing every
movement to a code change.
