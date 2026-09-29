# Official-build licensing

Source builds default to `AIRDRAFT_DISTRIBUTION=community` and remain fully usable.
Self-built editions update from source; Sparkle does not replace them with a
paid official build. The official release workflow sets `official`, embeds public Polar configuration,
and verifies it in the built app. Debug is restricted to Polar Sandbox; Release
is restricted to production. Missing official configuration blocks release
and never silently enables community access. No merchant token is used by the app.

## Merchant setup required before release

1. Create the AirDraft product in Polar and choose its price. The app does not
   promise a specific price, lifetime updates, or an automatic subscription.
2. Attach a license-key benefit. Enable device activations and customer device
   management; choose the device limit. Do not enable usage metering. Set expiry
   only if the purchased usage rights actually expire.
3. Fill `scripts/licensing-config.json`: `environment: production`, organization UUID, a nonempty
   `benefit_ids` array of distinct license-key benefit UUIDs, the shared hosted
   checkout URL, organization customer portal URL, and
   trial days. Checkout links accept HTTPS on `polar.sh` or `buy.polar.sh`;
   customer portals accept only HTTPS on `polar.sh`. User info, explicit ports,
   empty paths and build-setting substitutions are rejected.
4. Run `python3 scripts/licensing.py` and `python3 scripts/test-licensing.py`.
   The first command intentionally fails while IDs/URLs are empty. Public IDs
   and links may be committed; access tokens, license keys and payment data may not.
5. Before public distribution, exercise a completed Sandbox test-card purchase,
   wrong-product key, device
   limit, key rotation, portal deactivation, refund/revocation, offline restart
   and Keychain denial using dedicated test purchases and a disposable user.
   Local fixture tests are not proof of merchant setup or successful payment.
   Record Sandbox evidence separately from production configuration and payment processing.

Merchant configuration was supplied on 2026-09-29. The live product, attached
benefit and persistent checkout link were read back from Polar; the checked-in
public settings identify the allowed plan benefits. Current pricing and
policy are recorded in the Obsidian vault's `Strategy/Business Model` and
`Records/Decisions/2026-09-29 Polar Merchant Setup`. This verifies configuration,
not a completed purchase or production activation. The sandbox integration below
uses a separate account, organization, products, benefits and checkout.

## Polar Sandbox

[Polar's Sandbox guide](https://polar.sh/docs/integrate/sandbox) specifies
`https://sandbox.polar.sh` for the dashboard and `https://sandbox-api.polar.sh`
for the API. Production users, organization IDs, products, benefits, keys and
merchant tokens do not transfer. Use Stripe's `4242 4242 4242 4242` test card,
a future expiry and a test CVC. Never enter a real card for this verification.
Sandbox customer emails only reach organization members, including their
sub-addressing aliases.

1. Sign in to Sandbox and create its own organization. Mirror the US$29 two-Mac
   and US$49 five-Mac one-time products, with separate license-key benefits,
   activation limits of 2 and 5, customer device management, no usage limit
   and no expiration. Create a shared persistent Checkout Link.
2. Fill `scripts/licensing-sandbox.json` with `environment: sandbox` and the
   sandbox-only public IDs and URLs. Empty values deliberately block the test
   build. Never borrow production settings to make it build.
3. Run `moon run airdraft:build-sandbox`, or `python3 scripts/build-sandbox.py`
   when Moon is unavailable. It validates the config, enables the official
   license flow in a Debug build, and verifies the resulting Info.plist and
   separate `.debug` bundle identity. Open the returned app path explicitly.
   Normal source builds remain community editions without a paid gate or
   Polar requests; changing the API environment does not change that business model.
4. In its **Sandbox** license sheet, open **Test Purchase**, complete checkout,
   enter the sandbox key and verify activation, restart, device limits and
   deactivation. Test wrong-product keys, rotation and refund/revocation with
   dedicated sandbox orders. Mocks and previews remain distinct from these checks.

The app selects its environment with `#if DEBUG`, checks that embedded settings
match, and rejects checkout/portal URLs from the other environment. Sandbox
links currently accept only `sandbox.polar.sh`; production checkout additionally
accepts `buy.polar.sh`. Network errors never fall back across environments.
Sandbox Keychain receipt accounts include `.sandbox`; production keeps its
existing account with no migration or reset. This separates trials, device IDs,
pending requests and cached grants. Provider credentials retain their existing scope.
The release script accepts only production configuration and verifies its
embedded environment. No merchant token is required by the desktop client.

The two-Mac and five-Mac plans have separate products and license-key benefits.
The shared Checkout Link lets the buyer choose one product. Embed both allowed
benefits as `AirdraftPolarBenefits` through `AIRDRAFT_POLAR_BENEFITS`. The public
validate request omits the optional single-benefit filter; the client checks the
returned organization and benefit against its allowlist before allocating a
device. Never accept every license in the organization. Persist the actual
returned benefit so either plan stays valid after an offline restart. Device
limits are enforced by Polar, not inferred from the key prefix or price.

A perpetual license must not expire just to limit updates. Separate paid major
upgrades would require a separate product/benefit or update-entitlement design;
the current app has no update-expiry policy.

## Runtime contract

- Trial starts only after an explicit action, independently of onboarding and
  downloads. Store its fixed expiry, installation UUID and clock checkpoint in
  Keychain. Failed storage must not start a trial. Inaccessible credentials must
  not become a fresh installation. A backwards jump over five minutes blocks
  trial access until the clock is corrected. This is not tamper-proof DRM.
- Use Polar's public `/v1/customer-portal/license-keys/validate`, `/activate` and
  `/deactivate` endpoints. Validate the organization and benefit before reserving
  a seat; enforce `granted`, expiry and the expected activation ID. Bind the
  activation to a random installation UUID, not a hardware ID or hostname. The portal and app
  show the same short installation label so the correct Mac can be identified.
- Key rotation revalidates the replacement key against the saved activation ID;
  it never allocates another seat. A 404 from an old key does not prove that a
  device was removed. Keep its activation until a successful deactivation or
  explicit confirmation of removal in the customer portal.
- Activation is not idempotent. Persist a pending marker before allocating a
  seat; never retry automatically. After a lost response or storage failure,
  direct the user to remove the pending activation in the customer portal and
  explicitly acknowledge cleanup before another attempt. A failed receipt save
  also attempts to release the just-created activation.
- Store license keys and receipts in Keychain, separated by bundle ID. Passive
  reads and writes never prompt. Only the License view's Allow Access action
  authorizes reading. Preview and test stores never touch real credentials.
- Validate on startup and, if last verification is at least a day old, when the
  main app becomes active. The customer can also check manually. Transient network
  failures preserve the last verified grant until its stated expiry; a grant with
  no expiry remains usable offline without a fixed lease. Revocations therefore
  take effect only after contact with Polar. Explicit invalidation is persisted.
- Gate new microphone recordings, automation starts, sample processing and saved
  audio retranscription. Already-started work and recovery continue. History,
  copying, settings and model downloads remain available after expiry. The app
  does not relay audio to Polar and does not meter model use.

## Verification

Core tests cover state transitions and an intercepted HTTP transport; no actual
purchase or production key is used. `PipelineAutomationTests` exercise access
denial before capture and preservation of an active recording after expiry.
`scripts/test-licensing.py` checks configuration and final Info.plist identity.
Debug renders `license-{new,sandbox,trial,expired,licensed,offline,revoked,pending,locked,community,unconfigured}`
use isolated stores and a client that cannot contact Polar.

API contracts checked 2026-09-29 against [Polar license-key benefits](https://polar.sh/docs/features/benefits/license-keys)
and [customer-portal activation](https://polar.sh/docs/api-reference/customer-portal/license-keys/activate),
[validation](https://polar.sh/docs/api-reference/customer-portal/license-keys/validate)
and [deactivation](https://polar.sh/docs/api-reference/customer-portal/license-keys/deactivate).
Product policy and release status belong in the Obsidian vault's
`Strategy/Business Model` and `Product/Features/Licensing` notes.
