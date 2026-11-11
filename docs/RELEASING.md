# Release engineering

Repository: [swlittles/Reclaim](https://github.com/swlittles/Reclaim). Release and updater configuration was provisioned on 2026-11-10 using the owner's existing Apple Developer ID and notarization credentials from Bustelo, plus a fresh Reclaim Sparkle key. Private values are stored in GitHub Actions secrets, not this repository. The first stable release, [v0.1.0](https://github.com/swlittles/Reclaim/releases/tag/v0.1.0), was published successfully. Both the stable downloads and signed appcast are live.

The product-specific public key is committed in `Config/SparklePublicKey.txt`. Its private counterpart is stored in the local login Keychain under the Sparkle account `io.github.swlittles.Reclaim` and in the repository's `SPARKLE_ED_PRIVATE_KEY` secret. Do not replace this key for ordinary releases. The Apple credentials were transferred through a one-time encrypted artifact; the temporary source branch/workflow run/artifact and local transfer files were removed. Bustelo's default branch and its release configuration were not changed.

The build and release pipeline adapts the owner's Bustelo/Snippet conventions: universal arm64/x86_64 app, macOS 13 minimum, Developer ID Application, hardened runtime, secure timestamp, notarized/stapled app and DMG, ZIP, SHA-256 checksums and signed Sparkle appcast/archive. Ad-hoc builds must never be labeled stable.

## One-time configuration (already completed for this repository)

1. Create the GitHub repository when ready, add the remote, and review source/workflows before publishing.
2. Generate a **new Reclaim** Sparkle Ed25519 signing key using the pinned Sparkle `generate_keys` tool. Keep its private key in a secure store, outside source/logs/chat. Export only the public 32-byte Base64 key to `Config/SparklePublicKey.txt`. An absent/invalid public key intentionally blocks production builds. Never reuse a sibling app's key. `RECLAIM_SPARKLE_PUBLIC_KEY_FILE` can select a local public-key file for packaging checks.
3. Configure a valid Developer ID Application identity and Apple's notarization credentials. The default public team identifier follows the sibling apps; `APPLE_TEAM_ID` can override it. No certificate/private key was copied from another app during development.
4. Configure repository Actions secrets: `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `SPARKLE_ED_PRIVATE_KEY`, and either `NOTARY_API_KEY_P8` + `NOTARY_KEY_ID` + `NOTARY_ISSUER_ID`, or `NOTARY_APPLE_ID` + `NOTARY_APP_PASSWORD`.
5. Review repository/release permissions. PR CI is read-only and gets no signing credentials. Release signing imports credentials into an ephemeral runner keychain and removes it on all exits.

## Release

- Bump `VERSION`, monotonic `BUILD_NUMBER`, and the matching changelog section.
- Run `bash scripts/test.sh`, universal build, and native fixture/manual checks. Commit reviewed source and wait for CI.
- Create/push an annotated `vX.Y.Z` tag matching VERSION when publication is authorized. Release workflow validates identity, tag and build progression, tests, imports ephemeral signing credentials, builds both architectures, notarizes/staples, packages, generates/verifies signed appcast, retains artifacts, then publishes.
- Locally the signed pipeline is `RECLAIM_SIGNING_IDENTITY='<Developer ID identity>' NOTARY_PROFILE='<existing notarytool profile>' bash scripts/release.sh signed`; it fails if required configuration is missing.
- `release.sh preview` is explicitly unsigned preview packaging and still needs a real public key because it has production identity. It must not be published as a stable release.
- Appcast generation runs against final stapled assets, verifies signature/version/build/enclosure URL/length, and takes the private key through stdin rather than command arguments/logs. Publish script refuses replacing an already published release.
- Test the actual downloaded/stapled artifacts with Gatekeeper, both CPU architectures and the oldest supported OS. Exercise a real signed update to a subsequent build before claiming update interoperability.

Sparkle runs only in a production bundle with feed+public key. Daily checks are optional, profiling is disabled, scheduled updates appear quietly in the menu, and installation is user-driven. Cleanup postpones updater relaunch until the journal is settled. Dev and unbundled binaries never start the updater.

DMG layout is a standard application + Applications shortcut, created with hdiutil. Source scripts do not install third-party Python packaging dependencies. Stable validation never silently falls back to unsigned distribution.

## Published-download verification

After publishing, download the actual GitHub release assets, run the SHA-256 checks, and verify the feed and DMG with the committed public key (no private credentials needed):

```sh
swift scripts/verify-update.swift Config/SparklePublicKey.txt release-assets/appcast.xml release-assets/Reclaim-0.1.0-macos-universal.dmg
```

The release feed script also runs this public-key check before publication, so a mismatched signing secret cannot produce a seemingly valid but unusable updater feed.

Also verify the app's nested code signatures, `xcrun stapler validate`, `spctl --assess --type execute --verbose=2`, and universal architectures. Reclaim 0.1.0's downloaded DMG and ZIP passed these checks, and the running signed app successfully reported **You're up to date** from the live signed feed. An installation from an older version has not yet been exercised because this is the first release.
