# Official-build licensing

Source builds default to `AIRDRAFT_DISTRIBUTION=community` and remain fully usable.
Self-built editions update from source; Sparkle does not replace them with a
paid official build. The official release workflow sets `official`, embeds public Polar configuration,
and verifies it in the built app. Missing official configuration blocks release
and never silently enables community access. No merchant token is used by the app.

## Merchant setup required before release

1. Create the AirDraft product in Polar and choose its price. The app does not
   promise a specific price, lifetime updates, or an automatic subscription.
2. Attach a license-key benefit. Enable device activations and customer device
   management; choose the device limit. Do not enable usage metering. Set expiry
   only if the purchased usage rights actually expire.
3. Fill `scripts/licensing-config.json`: organization UUID, license-key benefit
   UUID, the product's hosted checkout URL, organization customer portal URL, and
   trial days. Both URLs must use `https://polar.sh`. The 14-day default is a
   configurable implementation choice, not an established published policy.
4. Run `python3 scripts/licensing.py` and `python3 scripts/test-licensing.py`.
   The first command intentionally fails while IDs/URLs are empty. Public IDs
   and links may be committed; access tokens, license keys and payment data may not.
5. Before public distribution, test an actual purchase, wrong-product key, device
   limit, key rotation, portal deactivation, refund/revocation, offline restart
   and Keychain denial using dedicated test purchases and a disposable user.
   Local fixture tests are not proof of merchant setup or successful payment.

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
Debug renders `license-{new,trial,expired,licensed,offline,revoked,pending,locked,community,unconfigured}`
use isolated stores and a client that cannot contact Polar.

API contracts checked 2026-09-29 against [Polar license-key benefits](https://polar.sh/docs/features/benefits/license-keys)
and [customer-portal activation](https://polar.sh/docs/api-reference/2026-04/customer_portal/activate-license-key),
[validation](https://polar.sh/docs/api-reference/2026-04/customer_portal/validate-license-key)
and [deactivation](https://polar.sh/docs/api-reference/2026-04/customer_portal/deactivate-license-key).
Product policy and release status belong in the Obsidian vault's
`Strategy/Business Model` and `Product/Features/Licensing` notes.
