# App updates

Airdraft embeds Sparkle 2.10.0. The menu bar, application menu, and Configuration
page expose **Check for Updates…**. Automatic checks default to once a day while
the app runs. Automatic downloading is opt-in under Configuration → Updates;
downloaded updates install when the app quits. Sparkle persists these preferences.

Checks are skipped during active dictation; requested restarts wait for it to
finish. Quitting still
goes through `AppDelegate.applicationShouldTerminate` and `ModelLifecycle.shutdown`.
Renders and self-tests do not start the production updater.

## Feed and signing

`project.yml` is the source of truth for `SUFeedURL`, `SUPublicEDKey`, and Sparkle's
defaults. The configured feed is the `appcast.xml` asset of the latest stable
GitHub release:

https://github.com/lstudlo-com/airdraft/releases/latest/download/appcast.xml

This address becomes live only after the first release with that asset is
published. It must be accessible without a browser login. The local push hook prepares its assets; the GitHub push workflow publishes them.
The standalone packaging script only prepares files.

Both the feed and update archive require Sparkle Ed25519 signatures. The private
key is in the macOS Keychain under Sparkle's account
`com.lstudlo.app.airdraft.sparkle`. Only the public key is in the repository.
Use Sparkle's `generate_keys --account com.lstudlo.app.airdraft.sparkle -p` to
check the public key. Keep a secure backup using Sparkle's documented key-export
procedure. Never commit or log the private key, and never generate a replacement
key to resolve a missing-key error for an already distributed app.

Sparkle signing is separate from Apple Developer ID signing. An app without
notarization still requires the user's Gatekeeper approval on initial download.
Ad-hoc signatures can also invalidate Accessibility grants after an update.
Developer ID signing and notarization remain the recommended public release path.
Debug builds use Apple Development signing with a separate
`com.lstudlo.app.airdraft.debug` identity and the name **Airdraft Debug**. They do
not install public Sparkle releases. See [Accessibility access](accessibility.md)
for migration and recovery steps when System Settings shows an enabled switch
but the running app is untrusted.

## Automatic releases from this Mac

Run once after cloning on the release Mac:

```sh
moon run airdraft:prepare
moon run airdraft:release-setup
```

The second command migrates the existing Sparkle Keychain account in place and
installs `.git/hooks/pre-push`. It refuses to overwrite an unrelated hook. It does
not change global Git configuration. Requirements: macOS, Xcode, Python 3.12+,
`gh auth login`, and the existing Sparkle signing key. XcodeGen 2.46.0 downloads
locally with a pinned SHA-256 if it is missing from PATH.

Then commit and push normally:

```sh
git add <the files to release>
git commit -m "feat: describe the change"
git push origin main
```

Every push to `origin/main` performs these steps:

1. Export the exact pushed commit to ignored `dist/release-source`. Uncommitted
   app and website changes cannot enter the DMG.
2. Run core tests and build an optimized Apple Silicon app locally. Xcode keeps
   one reusable DerivedData tree for that snapshot; no build tree is placed in Git.
3. Use the complete Git commit count as the increasing `CFBundleVersion`.
   The display version comes from `project.yml`. For example, version `0.1.1`,
   build `3` produces tag `v0.1.1-build.3`. Each push gets a distinct build without
   a generated version commit. Bump the display version when appropriate.
4. Create and sign the DMG and `appcast.xml`, attach a SHA-256 manifest identifying
   the source commit, and upload all three to a GitHub draft release. Download and
   verify them before allowing the push to continue.
5. After Git accepts the push, `.github/workflows/release.yml` verifies the draft
   against the pushed SHA, binds its tag to that SHA, and publishes it as latest.
   The signing key stays in this Mac's Keychain; GitHub performs no macOS build.

The current public build uses ad-hoc signing because there is no Developer ID
certificate. The DMG contains Airdraft and an Applications shortcut. It requires
Apple Silicon and macOS 15 or later. Local models remain separate downloads.
Build logs and artifacts are under `dist/releases/<tag>/`.

A failed push leaves a draft, never a public release. Retrying reuses verified
assets. A failed build blocks the push. The publisher refuses to publish a stale
commit after main moves. Feature branch and tag pushes do not build releases.
The hook applies to this clone; install it on each release Mac. Web merges and
pushes from a machine without the hook fail publication with a missing-draft
message, because no local Mac has built their DMG.

To recover after a push or workflow failure:

```sh
moon run airdraft:release-prepare  # prepare HEAD's draft if needed
moon run airdraft:release-publish  # only publishes if HEAD is current remote main
```

This workflow uploads a complete feed for the current Apple Silicon release.
Never edit the XML after signing. Other architectures or separate release
channels will need separate compatible feed entries before they are supported.

## App identity migration

The bundle identifier is `com.lstudlo.app.airdraft`. On first launch, existing
`com.lightiichen.transcribar` preferences are imported once without overwriting
values already stored under the new identifier. API credentials are copied into
the new Keychain service when first used. Explicitly deleting a credential removes
both copies. The existing Application Support directory remains in place, so
models, profiles, dictionaries and history stay available.

macOS treats the new identifier as a different app for Microphone and
Accessibility permission. Grant those permissions again when requested. Older
unreleased apps using the previous identifier should be replaced manually with
the first DMG; subsequent Sparkle releases keep the new identifier stable.

## Verify the integration

```sh
python3 scripts/verify-updater.py --sparkle /path/to/Sparkle-2.10.0
```

This compiles the production updater into a disposable app with its own settings
domain. It verifies preference persistence, dictation guards, deferred restart
and cancellation, acceptance of signed feeds, and rejection of altered feeds and
downloads. It then installs an ad-hoc-signed update on quit using Sparkle's real
helper and launches the updated app. A local HTTP server supplies test fixtures;
the production feed requires HTTPS. Airdraft's settings, history, models, and
installed app are not modified by this test.

Debug and Release builds, the core test suite, dark/light window renders, and
the local updater verification passed during integration. The generated DMG and
its signed appcast are local artifacts. A public feed and an installation on a
second Mac remain release checks, not results of this local verification.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[publishing updates](https://sparkle-project.org/documentation/publishing/),
[update preferences](https://sparkle-project.org/documentation/customization/).
