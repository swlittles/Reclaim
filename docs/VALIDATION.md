# Validation — Reclaim 0.1.0

Validated locally on 2026-11-10, Apple Silicon, macOS 27.0.1 (26A434), Apple Swift 6.3.2, Git 2.43.0. The selected developer directory was `/Library/Developer/CommandLineTools`. No Xcode/XCTest requirement was added to the test runner.

## Automated verification

| Command / check | Outcome |
| --- | --- |
| `bash scripts/test.sh` | 15 core fixture tests passed; 5 Python release tests passed |
| `RECLAIM_UNIVERSAL=1 bash scripts/build.sh` | Both arm64 and x86_64 release configurations compiled and were combined into `dist/Reclaim Dev.app` |
| `lipo "dist/Reclaim Dev.app/Contents/MacOS/Reclaim Dev" -verify_arch arm64 x86_64` | Passed |
| `codesign --verify --deep --strict "dist/Reclaim Dev.app"` | Passed (local ad-hoc signature) |
| `python3 scripts/validate-bundle.py "dist/Reclaim Dev.app" development` | Correct Dev ID/name, icon, framework, macOS minimum, no updater feed/key, valid nested signatures |
| Packaged executable `--diagnostics` | `Reclaim Dev`, development true, separate Dev data directory, feedPresent false |
| Packaged executable `--smoke-test` | Native window opened and automatic three-second clean exit succeeded |
| `python3 scripts/validate-version.py` | Version, changelog and initial monotonic build validation passed |
| `bash -n scripts/*.sh` (each script) | Passed |
| Python syntax/unittest and `git diff --check` | Passed |

Core tests cover NUL-delimited worktree paths with tabs/newlines/Unicode; family expansion outside the scan root; successful real Git removal of fixture worktrees with branch and verified safety-ref preservation; main/bare/submodule/dirty/untracked/ignored/locked/detached unique-commit protection; HEAD changes; active or unknown process state; activity in project roots protecting their build artifacts; manifest-based artifact discovery in external worktrees; hardlink accounting and nested symlink non-traversal; full metadata change detection; symlink-parent/root protection; exclusions after review; overlapping selections; fixture Trash move/restore and destination collisions; interrupted journals/private permissions; duplicate content hashing; literal subprocess arguments and timeout. Docker tests use a fake command runner to verify attachment/recreation/remote-context refusal and exact no-force removal without touching an actual daemon.

Release tests verify refusal of absent product-specific public key, invalid build variant, stable release without signing credentials, tag/version mismatch, and exact appcast enclosure version/build/minimum OS/asset URL/signature encoding/file size. They use synthetic artifacts and do not claim cryptographic release interoperability. Production appcast signatures are verified by Sparkle's own tools in the release pipeline.

## Native UI verification

Inspected the real packaged app using native computer-use accessibility and screenshots, not a browser mockup:

1. First-launch overview, menu-bar app lifecycle, startup-disk capacity and native dark appearance rendered correctly.
2. Worktree empty state, custom-root settings, opt-in automation and Dev updater explanation were visible.
3. Added only `.build/ui-fixture/`, containing a small Git main repo, one clean linked worktree, one linked worktree with untracked local work, and a manifest-evidenced node_modules folder.
4. **Scan Added Folders Only** returned 4 findings across 1 configured root, with 0 scan notes. Worktree page showed 3 registered worktrees. The main repo and dirty worktree had disabled checkboxes; the clean linked worktree was selectable.
5. Reviewed the clean fixture worktree. The sheet showed its exact path, permanent removal, branch/safety-ref semantics, and no app Undo. Apply remained disabled before the explicit permanent-action acknowledgement. The review was cancelled; nothing was removed through the UI.
6. Worktree inspector showed common directory, HEAD, branch, upstream absence, allocation split and irreversible-action message. Native Settings keyboard shortcut worked after adding standard native menus.
7. Removed the synthetic custom root and cleared synthetic results. No login item, scheduled scanning, notification permission, Full Disk Access, or Accessibility permission was enabled by verification.

Computer-use app selection could not bind a window after a background-only relaunch. Resetting only the new Dev app's first-run flag allowed another first-launch window inspection. Ordinary subsequent launches can remain in the menu bar; Open Reclaim from its menu opens the window. This was a UI automation limitation, not a failed scan.

## Delivered scope

- Real native menu utility and review UI; configurable roots/exclusions, targeted/quick/deep scans, incremental findings and cancellation; coverage notes, size/path/risk/age filters.
- Caches/logs/Downloads/Trash, large files, exact app-bundle-ID cache/preferences associations, app bundles, device backups and developer artifact inventory.
- Authoritative Git family discovery across arbitrary registered paths; clean linked-worktree removal only, with conservative blockers and safety refs. Artifacts inside externally discovered worktrees can be reviewed separately.
- Reviewed filesystem Trash cleanup with journal and collision-safe restore. Explicit permanent removal is limited to reviewed items already in the user's Trash. Actual OS Trash integration uses FileManager; mutation tests substitute fixture-only Trash.
- Local Docker image/container/volume inventory and exact-ID actions with endpoint/signature/reference/state revalidation. Docker mutation tests are mocked; no real engine, images, containers or volumes were changed.
- Duplicate SHA-256 grouping on demand with one-copy protection, placeholder/link checks, cancellation and partial-search notes.
- Mounted volume capacity, optional read-only APFS layout, provider-managed VM storage inventory; Homebrew/simulator read-only tool reports.
- Isolated Dev identity, native icon, user-controlled login/scan/notification settings, production-only Sparkle integration, universal build, signing/notarization/appcast/release scripts, CI and documentation.

## Limits and release prerequisites

The initial validation above preceded public distribution. On 2026-11-10, the public repository and a fresh product-specific Sparkle key were configured, and the existing Apple signing/notarization credentials were provisioned from Bustelo through an encrypted one-time transfer. Stable notarization/publication evidence is recorded below. A real signed update installation has not been claimed.

Actual runtime checks were on arm64 macOS 27.0.1. The x86_64 slice was cross-compiled and statically verified; Intel runtime and macOS 13 runtime were not tested. The installed SDK/compiler validates deployment availability, but that is not a substitute for those runtime tests.

Shared package stores, simulator/Android device deletion, broad Homebrew cleanup execution, Docker build-cache pruning, APFS erase/snapshot deletion, and VM compaction remain report-only or unsupported maintenance actions. App data associations are limited to exact bundle-ID caches/preferences/saved-state evidence; ambiguous/shared Application Support data is not proposed for deletion. Missing worktree metadata pruning is report-only; there is no force-removal path.

Discovery is comprehensive within accessible configured roots, known tool worktree locations and Git family expansion, rather than a claim to bypass TCC or find disconnected volumes. No complete live scan or cleanup of the user's real home storage was used for verification. Budgets, cloud placeholders, permission limits, shared APFS extents, cross-finding hardlinks and best-effort activity detection limit coverage and exact reclaimed-space predictions. See SAFETY.md for residual path races.

## Public distribution follow-up — completed 2026-11-10

- Public repository: https://github.com/swlittles/Reclaim
- Stable release: https://github.com/swlittles/Reclaim/releases/tag/v0.1.0
- Release commit/tag target: `ea648c6e3d6f518afa5108bcd656623ffeb33f4d`, `v0.1.0`, build `1`.
- Successful CI: https://github.com/swlittles/Reclaim/actions/runs/42952829222 (15 core tests, 5 release checks, universal Dev and production packaging checks).
- Successful signed release workflow: https://github.com/swlittles/Reclaim/actions/runs/42953211284 (4m31s). Apple credentials imported successfully; universal app and DMG signed, notarized, stapled; Gatekeeper and appcast checks passed before publication.
- An initial CI job using the inherited macos-14 label was rejected by GitHub's runner service. Workflows now use supported `macos-latest`. Production packaging also exposed macOS Bash's empty-array behavior under `set -u`; the icon-generation invocation was corrected and production packaging added to CI.
- Downloaded actual published DMG, ZIP, SHA256SUMS and appcast. Both SHA-256 checks passed. DMG integrity and stapled ticket validated. The apps inside both ZIP and mounted DMG passed deep/strict code-signature checks, stapled-ticket validation, and Gatekeeper assessment: **accepted; source=Notarized Developer ID**.
- Verified certificate: **Developer ID Application: Stephen Little (KQFYGC7SWB)**, hardened runtime, secure timestamp, stapled notarization ticket, production bundle ID `io.github.swlittles.Reclaim`. Main executable contains both arm64 and x86_64.
- Independently verified the published appcast and DMG Ed25519 signatures using CryptoKit and only the committed Reclaim public key. Same-length modified feed and modified archive copies were rejected cryptographically. The reproducible helper is `scripts/verify-update.swift`.
- Copied the verified signed release into local `dist/Reclaim.app` and launched it. Production settings showed live update controls and automatic checks enabled. **Check for Updates** successfully displayed **You're up to date! Reclaim 0.1.0 is currently the newest version available.** This verifies live signed-feed ingestion; it does not claim a two-version installation test.
- No real storage cleanup was performed. The signed release remains ready on Overview. Login items, scheduled cleanup scans, notification permission, Full Disk Access and Accessibility were not enabled.
- Reclaim uses its own new Sparkle key. Only the existing Apple signing/notarization credentials were reused. The encrypted bootstrap workflow run/artifact, temporary Bustelo branch, one-time transfer key, and local credential transfer files were removed; Bustelo's default branch/release setup was unchanged.

The remaining runtime matrix limits above still apply: Intel execution, oldest supported macOS execution, and installation of a future update from an older production version have not been tested. Public distribution and signing configuration are complete.


## 0.1.1 follow-up — impact, selection, and worktrees

- 20 core fixture tests and 5 release checks passed. New cases cover app bundles/settings/databases versus caches and unknown files; protected-classification independence; bulk filtering/exclusions/same-path and parent/child overlaps; one-known-duplicate retention; nested-file and Git activity overriding old directory timestamps; unknown/incomplete age exclusion; local Claude discovery and custom environment candidates; shared-cache protection precedence and legacy scan compatibility.
- Both universal release configurations built successfully as isolated Reclaim Dev; bundle validation, nested signature checks, architecture inspection, and Dev updater isolation passed.
- Native fixture-only targeted scan returned six findings: one main repository, four linked worktrees, and one evidenced dependency artifact. Linked-worktree default showed four rows, with two eligible and two protected; the main repository was not mixed into that list.
- The two-week age filter showed only the old clean fixture. Select All Shown selected only that row. Its review included Repository content classification, consequences, safety-ref semantics, and disabled permanent action until acknowledgment. Cancelled without mutation.
- With any age, bulk selection selected the two clean fixtures and skipped the dirty and ignored-file fixtures (2 added, 2 skipped). Clear Selection emptied the global selection. Filtering developer storage by App functionality & settings hid the rebuildable dependency fixture, correctly yielding no matches.
- Native dark-mode screenshot confirmed the filter/selection rows and worktree explanation fit the standard 1180×760 window. No user-storage cleanup was performed. Temporary Dev custom roots and scan cache were cleared, and the Dev build was quit.
- Classification is a deterministic consequence estimate, not proof that third-party software cannot be affected. Worktree activity uses filesystem/Git modifications, not provider session or last-opened guarantees. Existing force-removal, data-loss, APFS, platform-matrix and process-detection limits remain as documented above.
