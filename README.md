<p align="center"><img src="assets/logo-512.png" width="112" alt="Reclaim app icon"></p>
<h1 align="center">Reclaim</h1>
<p align="center">Room for your next build.</p>
<p align="center">macOS 13+ · SwiftUI + AppKit · MIT</p>

Reclaim is a native menu-bar storage utility for developers. Review everyday clutter, find build artifacts, and see Git worktrees across project folders, agent worktree locations, custom paths, and mounted disks. Cleanup is always a reviewed choice.

### Review by impact, age, and eligibility

Every finding has an **impact classification**, independent from whether it is currently **Protected**: cache (lower risk), logs/diagnostics, rebuild/reinstall needed, app functionality/settings, personal data, repository content, tool-managed storage, or unknown impact. Open **Filters → Impact** and select a row for the rule evidence and expected consequence. Rules cannot prove that a third-party app does not reference a file. Cache cleanup can remove offline data; app settings/databases are never labeled disposable just because they are old or large.

**Select → Select All Shown** selects eligible items under the current filters and preserves existing selections elsewhere. It skips excluded/protected items, overlapping paths, and the last known copy of each content-verified duplicate group. **Select → Clear Selection** clears all selected items across pages. The final review still shows each path, consequence, and irreversible action.

**Worktrees** defaults to linked worktrees. Use **Filters → Type** to inspect main repositories separately. Quick Scan checks existing `~/.t3/worktrees`, `~/.codex/worktrees`, `~/.cursor/worktrees`, and home Claude candidates, plus project roots; repository-local `.claude/worktrees` folders are found within those roots. Git registrations reveal other linked paths even outside the search roots. Inherited absolute `CODEX_HOME` and `CLAUDE_CONFIG_DIR` add `/worktrees` candidates; Finder launches may not inherit shell variables, so use **Add Folder** for custom locations. The worktree info popover reports candidates and missing folders; it does not claim every tool uses every candidate.

Choose **Filters → Age → 14+ days (2 weeks)** or **Custom days** to narrow old worktrees. Worktree age is the newest observed modification anywhere in its measured contents or Git HEAD/index/HEAD log, not a commit date or last-opened guarantee. Old cached scans without this evidence need a rescan; incomplete or unknown worktree ages do not match age filters. Age never overrides dirty/ignored/locked/active/missing-path protection.

The list keeps search, **Filters** (active count + **Reset**), sort, **Select**, and item count in a single fixed-height toolbar. Detailed controls live in the filter popover; worktree protections and discovery live behind the info button. All filters still apply to bulk selection.

Scans display a named phase and progress bar in the footer. Discovery and provider calls remain indeterminate while their totals are unknown. Repository checks and storage measurement use actual completed/total counts; duplicate hashing uses candidate byte counts, including explicitly skipped candidates. Percentages apply to the named phase, not a guessed whole-disk duration or coverage percentage. Hover the meter for counts and current-item enumeration. Cancellation and partial coverage remain visible in the final status.

Under **Settings → Menu bar storage warning**, choose a threshold in **% free** or decimal **GB free**, or disable the warning. At or below that threshold the menu bar adds yellow percent-free text, such as **6% left**. It returns to an icon above the threshold. The default is 10% free; capacity refreshes every minute and when the menu opens. This is independent of optional notifications and never performs cleanup.

**[Download Reclaim for macOS](https://github.com/swlittles/Reclaim/releases/latest)** · [All releases](https://github.com/swlittles/Reclaim/releases) · [Source](https://github.com/swlittles/Reclaim)

Stable downloads are universal (Apple Silicon and Intel), signed with Developer ID, notarized by Apple, and include verified Sparkle updates. Open the DMG, drag **Reclaim** into **Applications**, then launch it from Applications. No Accessibility permission is required. Full Disk Access is optional for broader scan coverage.

## Use it

```sh
bash scripts/test.sh
bash scripts/build.sh
open "dist/Reclaim Dev.app"
```

Requires macOS 13+ and Swift 5.9 or newer with Apple's Command Line Tools. Build scripts resolve the pinned Sparkle package. The standalone core test runner does not require XCTest or full Xcode.

Click the drive in the menu bar to scan, review storage, or open Settings. The first launch opens the overview. Closing the window keeps the utility in the menu bar.

- **Quick Scan** inventories user caches/logs, Downloads, Trash, applications and exact bundle-ID cache/preferences data, device backups, Xcode artifacts, common developer roots and installed-tool worktree locations.
- **Add Folder** includes custom repository/worktree parents and mounted volumes. **Deep Home Scan** searches more accessible home folders with explicit traversal budgets. **Scan Added Folders Only** restricts the sweep to custom roots.
- **Worktrees** expands each discovered Git repository's registered family, even when linked paths live outside your scan roots. It shows main/bare/detached/locked/missing states and conservative removal blockers.
- **Developer Storage** finds evidenced SwiftPM, JavaScript, Rust and Python project artifacts, shared package stores, simulator/SDK inventory, local Docker objects, and VM storage.
- **Large Files** ranks large files and downloads. **Duplicates** groups candidates by size, verifies SHA-256 content, and requires keeping a copy.
- **Volumes** shows mounted capacity plus an optional read-only APFS layout report. Shared APFS free space is not additive.
- **History** records individual outcomes, Trash locations, non-overwriting restore, and Git safety refs.

Choose items, click **Review Actions…**, check exact paths and consequences, and apply the reviewed actions. Selection starts empty. Permanent actions need an extra acknowledgement. Each target is checked again before mutation. After cleanup a fresh scan is required.

## Protecting your work

Reclaim never force-removes a worktree. Main/bare roots, dirty/staged/untracked/ignored content, submodules, locks, in-progress Git operations, inaccessible state, detected active working directories, and commits without durable references block removal. A successful clean linked-worktree removal uses Git itself, keeps branches, and creates a safety ref for HEAD. This removes the folder permanently; a ref is not a file backup.

Docker volume removal is permanent and individual. Volumes referenced by stopped containers are protected too. Remote and unknown Docker endpoints are disabled. Shared cache pruning, simulator deletion, APFS erase/snapshots, and VM disk compaction are intentionally inventory-only in this version.

Moving to Trash generally frees no disk space until Trash is emptied. Allocated sizes are estimates: APFS clones, snapshots, hardlinks between separate findings, shared Docker layers, and concurrent writes limit exact attribution. Running-process checks are best effort. See [Safety](SAFETY.md) for boundaries and residual filesystem races.

## Local by default

No account or analytics. Optional release update checks connect to GitHub through Sparkle. Metadata and cleanup history stay under `~/Library/Application Support/Reclaim Dev/` (or `Reclaim/` for production), with owner-only permissions. Full Disk Access is optional and cannot overcome Unix permission limits or disconnected storage. See [Privacy](PRIVACY.md).

## Development and releases

Local builds are **Reclaim Dev**, with a separate bundle ID, preferences, local data, DEV icon and no updater initialization/feed. Universal build:

```sh
RECLAIM_UNIVERSAL=1 bash scripts/build.sh
```

The release pipeline follows [Bustelo](https://github.com/swlittles/Bustelo) and [Snippet](https://github.com/swlittles/Snippet): universal app, Developer ID, hardened runtime, notarization/stapling, DMG, ZIP, checksums, signed Sparkle feed/archive, and gentle menu reminders. Reclaim has its own update-signing key. Apple signing and notarization use the same developer identity as the owner’s other Mac apps. Stable builds fail if required signing, notarization, or update configuration is missing.

- [Development](docs/DEVELOPMENT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Release engineering](docs/RELEASING.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Validation and current limitations](docs/VALIDATION.md)
- [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), [Changelog](CHANGELOG.md)

MIT. Includes Sparkle (MIT); see [third-party notices](docs/THIRD_PARTY_NOTICES.txt).
