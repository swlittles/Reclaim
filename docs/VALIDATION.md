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

### Published 0.1.1 and production update verification

- Release tag/source: `v0.1.1`, `99d227df769a9d1aafb1a3a684eb4abc365cc663`, build 2. Main CI https://github.com/swlittles/Reclaim/actions/runs/42958798373 and tag CI https://github.com/swlittles/Reclaim/actions/runs/42959247921 passed. Signed release https://github.com/swlittles/Reclaim/actions/runs/42959247878 passed in 6m9s; public release https://github.com/swlittles/Reclaim/releases/tag/v0.1.1.
- Downloaded the actual public DMG, ZIP, SHA256SUMS and appcast into `.build/published-v0.1.1`. Both archive checksums passed. Independently verified feed and DMG Ed25519 signatures with the committed public key, plus appcast version/build/minimum OS/URL/length checks. DMG integrity and stapled ticket validated.
- ZIP app passed deep/strict code signature verification, Gatekeeper (`accepted`, `Notarized Developer ID`), stapled ticket validation, and arm64/x86_64 architecture checks.
- The running production 0.1.0 app in `/Applications` discovered 0.1.1 through the live signed feed and displayed the matching release notes. Install Update downloaded the archive; Install and Relaunch completed the production upgrade. The relaunched process ran from `/Applications/Reclaim.app`, whose Info.plist reported 0.1.1/build 2. Deep/strict signature, Gatekeeper, stapled ticket, universal architecture, production bundle and updater configuration checks all passed after installation.
- The updated installed native UI showed Impact, Select All Shown, Clear Selection, expanded age choices, linked-worktree default and the six existing linked registrations. Existing user scan data remained intact. No user storage was cleaned and no full rescan was automatically triggered. Older saved worktree scans need a rescan for new activity timestamps and ignored-file examples.

The earlier first-release limitation about an untested two-version update is now resolved on the tested Apple Silicon/macOS combination. Intel runtime, macOS 13 runtime, and the other platform/storage limits remain untested or unchanged.


## 0.1.2 follow-up — progress, menu bar, compact filters

- 22 core tests and 5 release tests passed. Added percent/decimal-GB warning boundaries, disabled/invalid-capacity cases, under-one-percent labeling, legacy settings migration/persistence, unknown/zero/invalid progress totals, cancellation without false measurement completion, stable measurement denominators and byte-hashing completion assertions.
- Universal Dev build, nested signing and bundle validation passed. Native fixture scans returned three findings for sparse files/dependencies and nine findings when combined with the existing disposable Git family; ordinary safety checks remained in place.
- Native filter popover retained Type/Show/Age/Size/Impact. Choosing 14+ days updated Filters (1), and Reset returned the controls to defaults. Screenshot verified one 46-point toolbar with search, Filters, sort, Select, count and worktree info; the stacked rows and persistent worktree explanation are gone.
- Native Settings showed the current startup disk's 6% free and the default 10% warning. Switched to GB, edited 20 GB, verified persistence, and restored 10% mode. The indicator code uses a variable-width status item and yellow attributed percent-free title only below the configured threshold; normal and busy icons remain available.
- A fixture-only Git wrapper added 0.3 seconds per command so native automation could observe the otherwise brief phase. Native accessibility showed Inspecting Git repositories · 0%, its linear progress indicator, real 0/5 count, current fixture path, and Cancel. The scan completed; the later attempted Cancel found a stale element because completion had already replaced it. Cancellation behavior was exercised by the core fixture test, not claimed as a successful native cancellation.
- Removed temporary Dev roots, cleared scan cache, restored the normal Git locator and 10% warning, and quit Dev. No cleanup actions or user-home scans were performed. The two sparse QA files use negligible allocated space and remain inside ignored .build test output.


### Published 0.1.2 and production update verification

- `v0.1.2`, build 3, source `cd66f7683e5005be87a9489f2fe0a103a09fd990`. Main CI https://github.com/swlittles/Reclaim/actions/runs/42962302624 and tag CI https://github.com/swlittles/Reclaim/actions/runs/42962668703 passed. Signed release https://github.com/swlittles/Reclaim/actions/runs/42962668687 passed in 4m54s; public release https://github.com/swlittles/Reclaim/releases/tag/v0.1.2.
+- Downloaded actual public assets into `.build/published-v0.1.2`: DMG/ZIP SHA-256 checks passed; appcast and DMG Ed25519 verified with the committed public key; version/build/URL/length/minimum OS checks passed. ZIP app passed nested code signature, Gatekeeper, stapled ticket and universal architecture checks. DMG integrity and stapled ticket validated.
+- The installed 0.1.1 production app discovered 0.1.2 via the live signed feed, downloaded it, and completed Install and Relaunch. The relaunched process ran from `/Applications/Reclaim.app`; Info.plist reported 0.1.2/build 3. Post-install code signature, Gatekeeper (`Notarized Developer ID`), stapled ticket, architecture, production bundle and updater configuration checks passed.
+- Updated production UI showed the compact single-row toolbar with the existing six linked worktrees. Settings showed the warning enabled at 10% free, both threshold units available, and current 6% free. Existing scan data was retained; no automatic scan or cleanup was triggered, and optional login/notification/scheduled-scan settings stayed off.


## 0.1.3 follow-up — dedicated Trash screen

- 27 core fixture tests and 5 release checks passed. New tests cover current-user home/mounted-volume Trash discovery, other-user/outside/root/nested-target refusal, fixed empty-all review scope, preservation of newly arrived items, permanent fixture deletion with journals and no restore, changed/excluded/offline targets, missing versus unavailable homes, linked roots, exclusions, cancellation, partial inventory and selected-only review.
- Universal Dev build and bundle validation passed. A first universal build was invalidated by a source edit during compilation; the final frozen sources rebuilt successfully. The last UI-only change labels partial item totals as incomplete rather than presenting a full allocation total; the application debug build compiled afterward.
- Native Dev UI showed Trash in the storage sidebar without dropping Volumes or other pages, plus Open Trash in Finder, Refresh Trash, Empty Trash, search, Select, Delete Selected, Locations and History. The page performed a Trash-only refresh on entry.
- macOS denied the Dev build access to the actual home .Trash. The screen showed incomplete access and the exact location note, disabled Empty Trash/Delete Selected, and provided Full Disk Access settings. It did not claim the inaccessible Trash was empty. Screenshot checked layout. Native eligible-item review/deletion was not exercised against user data; reviewed scope and permanent deletion were tested only in disposable fixture homes/disks.
- No actual Trash was emptied and no privacy permissions or login/notification/scheduled-scan settings were changed. The Dev app was closed after verification. Production can require the user to grant Full Disk Access before Trash contents are readable; the app does not grant that permission itself.
