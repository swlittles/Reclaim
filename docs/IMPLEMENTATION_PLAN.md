# Reclaim: macOS storage cleanup for developers

Status: implementation brief, 2026-11-10. Working product name: **Reclaim**.

Execution update: the requested Claude delegate hit its provider limit before writing code. The user then explicitly instructed the primary Codex agent to implement directly. That instruction supersedes the original handoff in section 15. See VALIDATION.md for actual implemented scope and evidence.

## 1. Product outcome

Build a native, open-source macOS menu-bar utility that explains where storage went, helps users remove ordinary clutter, and understands developer artifacts well enough to avoid losing work. Its differentiator is a cross-location inventory of Git worktrees and developer storage, including worktrees made by coding agents, arbitrary custom paths, container volumes, and virtual-machine disk images.

The app must be useful as a working local build, with real scanning and reviewed cleanup, rather than a UI prototype. Follow the owner's existing macOS apps for distribution, updates, local-first behavior, and development/release separation. Implement the scope below in ordered milestones. If a tool or platform capability cannot be safely supported, present an explicit unavailable/report-only state and document the limitation; never replace it with simulated success.

### Product principles

1. Menu-bar first, with a proper review window for decisions that need space.
2. Explain every proposed deletion: exact location, owner/tool, size, reason, last change, consequence, and recoverability.
3. Scan without modifying the filesystem or tool state. Cleanup happens only after an in-app review of exact targets.
4. Preserve source code, credentials, databases, user documents, and unknown data by default.
5. Work offline. No accounts, analytics, remote analysis, or content uploads. Optional update checks are the only built-in internet feature.
6. Show uncertainty. Inaccessible paths, offline volumes, incomplete scans, stale measurements, and unknown Git safety must remain visible.
7. Never call an item disposable solely because it is old, large, detached, ignored, untracked, or not currently attached to a container.

### Initial technical decisions

- Native Swift + SwiftUI + AppKit, macOS 13+, Apple Silicon and Intel universal releases.
- Swift Package Manager with a testable core library and native executable. No Electron/web wrapper. Avoid introducing an Xcode requirement for normal build/test commands.
- `NSStatusItem` and a SwiftUI-backed popover or menu; a reusable SwiftUI review window, Settings, and About.
- Direct Developer ID distribution outside the App Store. No App Sandbox in v1 because broad developer-path inventory is central. TCC and Unix permissions still apply.
- No root helper or privilege escalation in v1. Read and act only within the user's permissions. Do not request Accessibility permission.
- MIT license, matching the existing apps. A clean new repository at `/Users/escanor/Projects/Personal/Reclaim` with no changes to sibling repositories.
- Proposed production ID `io.github.swlittles.Reclaim`; development ID `io.github.swlittles.Reclaim.dev`. App names `Reclaim` and `Reclaim Dev`.
- Start at version `0.1.0`, build `1`. Release URLs target the proposed `swlittles/Reclaim` repository; documentation must say that publication is pending until that repository/feed actually exists.

## 2. Existing-app conventions to adopt

References inspected locally:

- `../Bustelo/README.md`, `Package.swift`, `Sources/Bustelo/Updates.swift`, `scripts/build.sh`, `scripts/release.sh`, `scripts/update-feed.sh`, `.github/workflows/release.yml`.
- `../Snippet/README.md`, `docs/DEVELOPMENT.md`, `docs/RELEASING.md`, `Sources/Snippet/Updates.swift`, `scripts/build.sh`.
- `../Cutline/docs/DEVELOPMENT.md` and release documentation for additional release/dev separation.
- Git remotes establish the owner as `swlittles`. Not every adjacent project is a macOS app; use Bustelo and Snippet as primary references.

Adopt the conventions, with product-specific identity and safeguards:

| Area | Reclaim contract |
| --- | --- |
| Experience | Small native utility, clear menu entries, keyboard support, system appearance, no login or analytics |
| Development | Separate bundle ID, preferences, Application Support, scan cache, cleanup journal, Dev icon badge and menu label |
| Unbundled binary | Defaults to development identity and never checks the release feed |
| Login item | User-controlled `SMAppService.mainApp`, handles approval/error states |
| Local build | `bash scripts/build.sh` produces ad-hoc signed `dist/Reclaim Dev.app` |
| Tests | `bash scripts/test.sh`, temporary fixtures, no cleanup of the host's real storage |
| Versions | `VERSION`, increasing `BUILD_NUMBER`, `CHANGELOG.md`, matching version tag |
| Release | Universal app, Developer ID, hardened runtime, notarization, stapling, DMG, ZIP, SHA-256 |
| Updates | Sparkle 2, signed appcast and archive, quiet scheduled reminders, user-driven install |
| CI | Read-only pull-request checks without signing secrets; release credentials only in release job |

Reuse or adapt appropriate MIT-licensed implementation and scripts with attribution. Do not copy Bustelo's lid helper, application data, signing secrets, or another app's Sparkle signing key. Its public Team ID is configuration, not a credential; keep signing configuration documented and validated.

## 3. User experience

### Menu bar

- Monochrome template symbol, distinct scanning state, and a quiet update-available indicator.
- Current startup-volume free/total space and last-scan age.
- `Scan Storage…`, `Review Cleanup…`, `Worktrees…`, `Developer Storage…`, `Open Reclaim…`.
- Active scan progress with Cancel. A stopped/incomplete scan cannot appear complete.
- Open at Login, Settings, Check for Updates/Update to Reclaim…, About, Quit.
- Closing the review window leaves the menu utility running. Quit cancels scanning; if cleanup is in progress, finish or stop safely at an item boundary and persist the journal.
- Avoid constant timers, recursive scanning on popover opening, or focus-stealing update alerts.

### First run

1. Explain scan/review/cleanup in a short local-first introduction.
2. Offer a quick scan of normal user caches and common developer roots.
3. Let users add project folders, custom worktree locations, and mounted local volumes with `NSOpenPanel`.
4. Explain Full Disk Access only when a desired location is denied; offer a System Settings link and retry. The app remains useful with partial access.
5. Make automatic scans and low-space notifications explicit settings. No automatic cleanup.

### Main window

Sidebar: Overview, Cleanup, Worktrees, Developer Storage, Large Files, Duplicates, Applications, Volumes, History.

- Overview: disk usage and scan coverage; category totals; conservative recommendations; rescan controls.
- Cleanup: sections for regenerable caches, review-needed items, and protected/unavailable findings. All selections initially empty in v1.
- Detail pane: exact path, allocated/logical sizes, age, discovery reason, risk, exclusion state, tool state, action consequence, and Finder reveal.
- Search paths/names and filter by category, repository, volume, risk, age, and size. Sorting must not change selection identity.
- Persistent bottom review bar: selected count, estimated bytes, actions. Deduplicate overlaps before displaying a total.
- Review sheet lists each exact action and whether it goes to Trash, is permanently removed by a tool, or merely changes metadata. Never hide an irreversible action inside a generic Clean button.
- Progress/outcome lists success, skipped, changed-since-scan, denied, and failed separately. Keep actionable errors per item.
- Accessibility labels, Dynamic Type where practical, VoiceOver-friendly row details, reduced motion, native dark/light mode, useful empty states.

## 4. Ordinary storage features

| Feature | Discovery | Cleanup policy |
| --- | --- | --- |
| User caches | Allowlisted cache subdirectories in `~/Library/Caches`, respecting exclusions and active owners | Reviewed move to Trash; explain that caches regenerate and trash does not immediately free disk space |
| User logs | Bounded user log locations with age/details | Reviewed Trash; never live system logs or broad `/var` cleanup |
| Trash | Inventory accessible user's Trash with contents and size | Explicit permanent-delete action, separately confirmed; never use privileged/global trash commands |
| Downloads/installers | Old downloads, `.dmg`, `.pkg`, `.zip` with type/age filters | Review only, no preselection or age-based assertion of uselessness |
| Large files | User-selected home/project roots, allocated-size ranking, Finder reveal | Review only, Trash exact selected items |
| Duplicates | Size grouping, then streaming content hash only when requested | Show full groups, preserve at least one, no same-name heuristics or automatic keeper deletion |
| Applications | `/Applications` and `~/Applications` bundle inventory, size, running state | User-selected app to Trash; associated data only individually reviewed with strong bundle-ID evidence |
| App leftovers | Exact bundle-ID-associated caches/preferences/support where confidently attributable | Distinguish evidence from guesses; never delete shared groups, Keychains, Documents, or arbitrary support folders |
| Device backups | Recognize MobileSync backups and show identifiable backup folders | High-impact review; no recommendation based solely on age |
| Browser caches | Known cache locations only, with running-browser detection | Skip while browser is running; never browser profiles, history, cookies, extensions, or passwords |

Normal cleanup must never include OS files, RAM/swap purging, language removal from app bundles, system extensions, Photos/Mail libraries, Keychains, or automatic snapshot removal. Do not describe speculative cache bytes as guaranteed recoverable capacity.

## 5. Developer storage inventory

Implement a provider registry with explicit availability, version detection, discover, inspect, propose, and execute capabilities. A provider may be read-only until it has a safe implementation and tests.

| Provider | Initial useful targets | Rules |
| --- | --- | --- |
| Xcode | DerivedData, build products, caches, Archives, DeviceSupport, simulator state | DerivedData reviewed/regenerable; archives/manual downloads high-impact; simulator deletion only through supported tooling for selected unavailable devices |
| SwiftPM | Project `.build`, known SwiftPM caches | Protect manifests/source; skip active builds; explain rebuild cost |
| JS/TS | Project `node_modules`, known npm/yarn/pnpm caches and stores | Detect project evidence and lockfiles; shared stores use manager-supported operations or report-only; do not delete arbitrary dotfolders |
| Rust | Project `target`, Cargo cache inventory | Protect source and credentials; shared registries report-only until safe manager semantics validated |
| Python | `.venv`/`venv` with actual environment markers, pip/uv caches | Environments need explicit review; never assume a directory named `env` is disposable |
| JVM/Android | Gradle/Maven caches, Android build artifacts, SDK/AVD inventory | SDKs and virtual devices high-impact/report-only unless supported targeted removal is verified |
| Homebrew | Cache and actual `brew cleanup` dry-run output | Use validated installed executable and supported operations; do not manually delete Cellar trees or run broad uninstalls |
| Docker | Images, stopped containers, build cache, volumes, local context | Exact local context, tool-managed objects, no automatic prune-all; details below |
| Other VMs | Colima/Lima/OrbStack/Docker Desktop disk images and provider data | Identify ownership and actual allocated size; never remove or compact a live VM image directly |
| Agent tools | Known worktree parent locations and project metadata | Locations seed Git discovery; a folder name alone never authorizes deletion |

Read configurable manager paths through bounded, read-only local inspection. Launch binaries with argument arrays, not shell strings. GUI PATH differs from terminal PATH: find tools in trusted system and common installation locations and expose an override in Settings. Missing tools become clear unavailable states.

## 6. Worktree discovery: central feature

### Discovery scope and honest coverage

There is no global macOS registry of all Git repositories or worktrees. Deliver comprehensive discovery within accessible configured roots and known tool locations, and expand from Git metadata across arbitrary paths. Do not promise to discover unreadable folders or offline disks. Show roots, skipped paths, exclusions, mounted-volume scope, and the last successful sweep.

Three scan modes:

1. **Quick:** known developer roots plus user-added roots and known agent worktree parent locations.
2. **Deep:** user-requested bounded recursive search across accessible home/local selected volumes, including hidden directories relevant to worktrees; cancellable and resumable where practical.
3. **Targeted:** user-added repository, worktree, directory, or mounted volume. Once one related repository/worktree is found, resolve the complete registered family regardless of its physical parent folder.

### Discovery algorithm

1. Seed common project roots (`~/Projects`, `~/Developer`, `~/Development`, `~/Code`, `~/src`), user-defined roots, selected volumes, app-local cache, and known installed-tool roots.
2. Verify actual local conventions for tools such as Codex, Claude Code, Cursor, and T3 before encoding adapters. Candidate examples include `~/.codex/worktrees`, `~/.cursor/worktrees`, and repository `.claude/worktrees`; treat these as hints, not authoritative schemas. Do not parse chats, tokens, or session contents to find paths.
3. Walk using metadata-prefetched enumeration, cancellation, depth/item/time budgets, and exclusions. Do not descend into `.git` object databases, dependency caches, app bundles, cloud-only placeholders, Trash, backups, or unrelated VM internals. Tool adapters can opt into an exact metadata path when needed.
4. Detect `.git` directories, `.git` pointer files, and potential bare repositories. A `.git` file may represent a submodule, not a linked worktree; verify with Git.
5. Ask Git for actual repository identity and common Git directory (`rev-parse --git-common-dir`, resolve relative results from the command's working directory). Prefer support-detected absolute-path output when available.
6. For each unique common directory, run `git worktree list --porcelain -z`. Parse NUL-delimited fields/records byte-safely, including paths with spaces, Unicode, tabs, and newlines. Support older installed Git with a separately tested porcelain parser or declare capability limits clearly.
7. Record main/bare/linked, actual root, HEAD, branch/detached, locked reason, prunable reason, common directory, discovered-by, volume, reachability, and timestamp. Never infer these fields from directory names.
8. Reconcile `.git/worktrees/*` administrative backlinks in a read-only provider when useful; do not mutate internal Git files. Show broken registration and missing/offline paths distinctly.
9. Deduplicate by canonical repository identity and filesystem identity; preserve original display paths. Symlink aliases must not produce duplicate cleanup targets.
10. Expand from registered paths outside the initial roots only for bounded inspection. Report those paths in coverage and require explicit review before mutation.

### Worktree detail and safety assessment

- Branch or detached HEAD, main repo, owner/tool hint and confidence, HEAD, filesystem modification time labeled accurately (not invented last-used time).
- Working tree state using `git status --porcelain=v2 -z --untracked-files=all` or a tested fallback, including conflicts, staged/unstaged changes, and submodule state.
- Check ignored content separately. `.env`, ignored generated assets, databases, and local credentials can be valuable even in an otherwise clean worktree.
- List local branch/upstream and merge reachability to configured main branches and existing remote-tracking refs. Do not fetch or send credentials. Explain that remote-tracking refs can be stale and pushed status cannot be guaranteed offline.
- Detached commits without another durable reference are protected. Branch tip existence alone is insufficient if reflog-only or stash dependencies remain uncertain.
- Existing locks, missing/offline volumes, permissions, Git errors, in-progress operations, submodules, and evidence of running build/editor/agent activity are blockers or explicit unknowns. Activity checks are best effort, never a guarantee.
- Separate source payload size from build/dependency directories within a worktree; avoid double-counting the worktree and nested cleanup candidates.
- Plain-English reasons: clean, review needed, protected, missing registration, or unknown. Never assign a safe-to-delete score purely from inactivity.

### Worktree cleanup contract

- Main and bare repository roots are never selectable for worktree removal.
- Default removal only for an explicitly selected, freshly revalidated linked worktree; no automatic worktree cleanup and no `--force` implementation in v1.
- Dirty, conflicted, untracked, ignored-content, locked, submodule-bearing, active, unreachable, or uncertain unique-commit worktrees remain blocked. Offer Finder/Terminal reveal and explain how users can resolve the blocker manually.
- Before removal, preserve a verified durable safety ref to the exact HEAD in the common repository if needed and approved as part of the action. Record it in the journal; revalidate HEAD and status immediately before the operation. A ref preserves commits, not uncommitted files; never present it as a complete backup.
- Execute `git worktree remove -- <exact-path>` through the verified owning repository, without force. Do not recursively delete the directory or edit `.git/worktrees` yourself.
- Clearly label worktree removal as permanent filesystem removal with commit recovery information, not a reversible move to Trash. Do not promise an Undo button for it.
- Missing worktree registration pruning is a separate reviewed action with dry-run preview. Git prune may affect multiple missing entries: either present/revalidate the entire exact affected set or keep it report-only. Never prune locked/offline worktrees or mutate internal metadata to target one entry.
- Preserve branches. No branch deletion, `git clean`, resets, `git gc --prune=now`, or reflog expiration.
- After success, rerun worktree inventory and invalidate all overlapping findings. A failed Git operation must not trigger a recursive-delete fallback.

## 7. Volumes, containers, and virtual disks

Separate these object types in both the data model and UI:

1. **Mounted filesystem volumes/APFS containers:** enumerate local mounted volumes, read-only/network/removable flags, shared capacity relationships, and access. Exclude network/removable volumes from deep scans unless explicitly included. Inventory APFS/System/Data/Recovery/VM/Preboot and snapshots as informational where supported. No APFS erase, repartition, system snapshot deletion, or root operations in v1.
2. **Docker volumes:** named/anonymous volume inventory with driver, labels, mounts, container references including stopped containers, and size when supported. Unattached does not mean disposable. Database-like or unknown volumes stay high-impact; all volumes require individual review. Allow exact-ID `docker volume rm` only after fresh inspection and explicit permanent-deletion confirmation, never force or volume prune. A changed/attached object is skipped.
3. **Containers/images/cache:** show image sharing accurately. Avoid adding overlapping virtual-disk, image, and build-cache bytes. Prefer exact-ID removal for stopped objects; scoped prune operations only where a preview and execution can guarantee the reviewed scope. Otherwise report-only. Never issue `docker system prune -a --volumes`.
4. **VM disk images:** show logical and allocated bytes, owner/provider, and running state. Docker.raw/QCOW/VHD/sparsebundle capacity is not reclaimable-byte truth. Expose provider guidance or validated targeted maintenance; no direct disk deletion/truncation and no shutting down tools automatically.

Docker must be unavailable rather than silently launched if the engine is stopped. Only act on explicitly recognized local contexts. Remote TCP/SSH and unknown contexts are inventory-limited or disabled; app cleanup must not reach remote infrastructure. Bound command timeouts and output.

## 8. Filesystem correctness and cleanup transaction design

### Measurement

- Track logical bytes, allocated bytes, file count, and estimate confidence separately. Use URL resource keys/stat information without reading whole files for ordinary scans.
- Count hard links once by device/inode identity. APFS clones/snapshots/shared extents cannot generally be attributed exactly by summing files: label estimates.
- Keep volume capacity and finding totals separate. APFS volumes can share container capacity; don't sum their free space as independent disks.
- Never trigger cloud placeholder downloads to measure/hash. Mark such items skipped and explain why.
- Trash movement on the same volume generally frees no space until emptied; report moved bytes separately from measured change in free capacity.
- After cleanup, resample disk capacity and show observed change as an observation, not a guaranteed consequence of every action.

### Immutable review plan

Define `CleanupPlan` containing scan generation, selected stable IDs, exact target identities, expected fingerprints, provider actions, consequence, recovery semantics, preconditions, and estimated bytes. Build it from findings; render it before execution. A changed selection or changed scope produces a new review.

An item fingerprint includes filesystem identity, canonical ancestor chain, type, owner where relevant, modification metadata, and provider identity. For Git it also includes repository identity, HEAD/status, locks and safety refs. For Docker use object ID and local context identity.

### Execution

1. Serialize mutating operations and hold an app-level cleanup lock.
2. Revalidate exclusions, access, path type, volume identity, process activity, and all provider preconditions immediately before each action.
3. Defend against path substitution and symlink/ancestor races. Reject symlink traversal and unexpected parent identity changes; use descriptor-relative/no-follow operations where required. Do not claim validation fully eliminates races for tools that accept paths; document residual limits and fail closed when uncertain.
4. Reject `/`, home root, `/System`, `/bin`, `/sbin`, `/usr`, private system directories, volume roots, repository main roots, and any path outside the reviewed allowlist. Correct boundary checking uses path components/identity, not string prefixes.
5. Reject overlapping ancestor/descendant selections or collapse them safely before review. A child cannot remain executable after its parent was moved.
6. Use `FileManager.trashItem` for eligible filesystem objects, preserving resulting Trash URL. On failure do not fall back to permanent removal.
7. Tool-managed irreversible actions have a distinct review and execution path. No shell interpolation or broad wildcard delete commands.
8. Append owner-only local journal entries before and after each operation. Redact command output that may include secrets. Track partial results explicitly.
9. Cancellation stops between items; running atomic tool commands complete or time out into an unknown outcome that must be reconciled before retry.
10. Resume after app crash by reconciling journal entries; never replay a previously attempted destructive command automatically.

### Recovery

- History shows moved-to-Trash items with Reveal and a bounded Restore option when exact original destination is absent. Restore must never overwrite another file.
- An item emptied from Trash is no longer recoverable by Reclaim; make that state explicit.
- Git safety refs and recovery commands are shown separately from file restoration. Source branches and objects are preserved, but worktree-local uncommitted files are never assumed recoverable.
- Docker volume deletion and selected tool removals have no app Undo. Keep confirmation consequence unambiguous.
- Exclusions support exact items, folder subtrees, repositories, volumes, and categories. Persist locally with validation; excluded/protected items cannot be selected through filtering shortcuts.

## 9. Internal architecture

Suggested layout (adapt to sound implementation needs):

```text
Package.swift
Sources/ReclaimCore/
  Models/           ScanRoot, Finding, StorageCategory, Risk, ByteEstimate,
                    Repository, Worktree, Volume, CleanupPlan, CleanupResult
  Scanning/         ScanCoordinator, FileWalker, SizeCalculator, ScanCoverage
  Providers/        UserStorage, DeveloperArtifacts, GitWorktrees, Docker, Volumes
  Git/              PorcelainParser, RepositoryResolver, WorktreeSafety
  Cleanup/          PlanBuilder, PathGuard, Executor, Journal, TrashService
  Infrastructure/   ProcessRunner, ToolLocator, FileSystem, Identity, Persistence
Sources/Reclaim/
  App/              AppDelegate, StatusItemController, WindowCoordinator
  State/            MainActor AppModel, settings, selection state
  Views/            Overview, Findings, Worktrees, DeveloperStorage, Volumes,
                    LargeFiles, Duplicates, Applications, Review, History, Settings
  Updates.swift
Tests/ReclaimCoreTests/
Config/             production updater key/config, entitlements if needed
assets/             native/code-generated icon sources and rendered icons
scripts/            build, test, release, signing, appcast, validation
.github/workflows/  ci.yml, release.yml
docs/               implementation, architecture, safety, development, releases
```

Core protocols: `StorageProvider`, `CommandRunning`, `FileSystemAccess`, `TrashManaging`, `Clock`, `ToolLocating`. Prefer injected dependencies over global singletons for filesystem/tool operations. Keep AppKit/Sparkle outside the core library. Use actors/structured concurrency for scan state and process lifecycle; publish UI on MainActor. Bound concurrent enumeration and subprocess count; never spawn one subprocess per file.

Persistence in `~/Library/Application Support/Reclaim[ Dev]/`: versioned settings/roots/exclusions, scan summary cache, and cleanup journal, owner-only permissions. Preferences domains are separate. Cache minimal path metadata, not file contents. Store security-scoped bookmarks when appropriate for selected roots, with stale-bookmark handling, without promising that bookmarks bypass TCC. Provide clear-history/cache actions for Reclaim's own data.

## 10. Updates and release engineering

### Runtime updater

- Adopt Bustelo/Snippet's `SPUStandardUpdaterController` and gentle scheduled reminder pattern, with observable state for menu/settings.
- Production only: HTTPS appcast `https://github.com/swlittles/Reclaim/releases/latest/download/appcast.xml`, product-specific Ed25519 public key, signed feed requirement, verify archive before extraction, no system profiling.
- Daily automatic checks with a visible opt-out; user starts download/install. No background installation by default.
- Manual checks show genuine Sparkle errors/offline states. Scheduled finds update menu badge/title without stealing focus.
- Development and unbundled runs do not initialize the updater or contact a feed. Prefer omitting feed keys from Dev bundles entirely, plus runtime gating.
- Defer installation/relaunch while cleanup is executing. Before quit persist journal/settings and cancel scan safely. Never abandon an unknown destructive operation to relaunch.
- Do not reuse another app's update key. If no Reclaim public key is configured, build Dev normally and keep release/update validation explicitly blocked. Never ship a placeholder key with a working-looking updater.

### Build and packaging

- `scripts/build.sh`: staging directory, atomic final bundle placement, refuse overwriting running target, Dev default, validate variant/version/build, optional universal, proper icon and Info.plist.
- Embed Sparkle with preserved symlinks/modes and sign helpers/framework inside-out. Correct rpath. Ad-hoc local build vs Developer ID hardened runtime production.
- Release pipeline: validate tag/version/build/changelog, tests, universal build, architecture verification, Developer ID/team verification, app notarization/stapling, ZIP, DMG signing/notarization/stapling, Gatekeeper assessment, checksums.
- Generate and verify a signed appcast only from final stapled assets. Validate enclosure URL, product/version/build, length, signature, minimum OS. Keep private keys out of argv/logs/source.
- Publish only after every validation passes; no unsigned fallback labeled stable. Retain verified artifacts before publication. Credentials in ephemeral CI keychain, cleaned on all exits.
- Pin GitHub Actions appropriately and declare minimal permissions. Pull request CI uses no signing secrets and cannot publish.
- Document expected signing/notarization/update secrets from sibling apps; do not read/copy existing private keys or install credentials during implementation. Release secrets are a real external prerequisite, not grounds to stop the rest of the build.
- Source/docs/scripts should be ready for a public repository. Creating the GitHub repository, pushing tags, publishing a release, and a real signed update installation are separate distribution steps; do not claim they occurred without evidence.

## 11. Ordered implementation milestones

### M0 — Foundation and working native shell

- Initialize only the Reclaim repository, inspect applicable instructions, preserve this plan.
- Package/core/app/tests layout, app identity, preferences, menu bar, window routing, Settings, login item.
- Build/test scripts, native generated icon, empty/permission/error states, README and MIT license.
- Acceptance: `bash scripts/test.sh` and `bash scripts/build.sh` pass; Dev bundle launches to a functioning menu and review window; no updater network activity in Dev.

### M1 — Read-only inventory and measurement

- Cancellable bounded scanner, configurable roots/exclusions, volume inventory, size accounting, stable IDs, coverage/errors.
- Ordinary caches/logs/downloads/large files/app inventory. Show actual findings with Finder reveal and non-overlapping totals.
- Acceptance: scan chosen temporary fixture roots with correct sizes/categories; denied paths do not abort the whole scan; UI remains usable during scans and cancellation.

### M2 — Complete worktree family discovery

- Git common-directory resolver, NUL parser, repo/worktree metadata and custom roots; known tool locations as discovery seeds.
- Group by repository, location/tool/branch filters, dirty/ignored/lock/unique commit/submodule states, missing/offline registration distinction.
- Acceptance: find a linked worktree outside the seed directory through Git metadata; correctly inventory multiple repositories and bare families, Unicode/newline paths, and protected states.

### M3 — Reviewed cleanup and meaningful recovery

- Immutable cleanup plan, exclusions/path guards/revalidation, per-item journal, Trash/restore, errors, progress, crash reconciliation.
- Safe clean linked-worktree removal through Git, optional approved safety refs, no force; branch preservation and overlapping-target invalidation.
- Acceptance: real mutations only on temporary test fixtures; changed target blocks execution; dirty/ignored/locked/main worktrees cannot be removed; successful removal updates Git inventory; no recursive-delete fallback.

### M4 — Developer tools and volume detail

- Working filesystem-backed artifact providers and tool availability detection.
- Docker local read-only inventory and narrowly targeted reviewed mutations where supported; volume removal individually confirmed; provider-managed limitations visible.
- Xcode/simulator and Homebrew dry-run integration where CLI availability permits. VM/APFS inventory with report-only boundaries.
- Acceptance: mocked commands verify exact IDs/context and no wildcard/global prune; missing/stopped tools show unavailable; live host engines/storage are never modified during implementation verification.

### M5 — Expected storage-tool workflows

- On-demand duplicate hashing with at least-one-copy protection, application review/removal, precise associated-data evidence, old backups/installers, History/restore refinements.
- Low-space notifications and optional scheduled read-only scans, explicit opt-in settings.
- Acceptance: duplicate cancellation works and avoids placeholders; running apps and uncertain shared support data are blocked; no automatic deletion path.

### M6 — Updates, CI, documentation, and final verification

- Production Sparkle integration and Dev gating, release scripts/workflows, feed validation, fresh per-product key configuration path.
- Complete README, SAFETY, PRIVACY, architecture/development/releasing docs, CHANGELOG, contribution/security guidance, third-party notices.
- Run meaningful core tests, packaging checks and universal build when available; inspect packaged identity, signatures, architectures and updater keys. Perform native UI smoke checks using permitted tools if available; no browser preview for a native app.
- Produce `docs/VALIDATION.md` with exact commands, outcomes, host environment, manual checks, unavailable tools, and release prerequisites.
- Final report gives local repository and `.app` path, implemented scope, test results, and concrete limitations. No fabricated notarization, public GitHub release, oldest-OS runtime test, or cross-architecture runtime validation.

## 12. Required verification matrix

Use meaningful core tests and real temporary Git repositories for destructive flows. A test suite must never target the real user's projects, home caches, worktrees, containers, or volumes.

| Area | Required cases |
| --- | --- |
| Git parsing | NUL-delimited records, newline/tab/Unicode paths, detached/bare/main/locked/prunable, malformed/truncated output |
| Git discovery | `.git` file vs dir vs submodule, relative common-dir, custom external worktree, symlink alias, missing/offline path, multiple families |
| Git safety | staged/unstaged/conflict/untracked/ignored, ignored `.env`, unique detached commit, no upstream, stale remote refs, submodules, in-progress operation, HEAD/status changing after review |
| Git removal | clean fixture succeeds; main/locked/dirty/ignored/unknown rejected; branches preserved; safety ref verified; failure never recursively deletes; metadata prune scope does not exceed review |
| Filesystem | hard links, symlinks, sparse files, hidden files, permission errors, overlapping roots/targets, volume boundary, cloud placeholder exclusion |
| Cleanup | path-component boundary, swapped target/ancestor, changed fingerprint, exclusion added after review, Trash failure, restore collision, cancellation, partial failure, interrupted journal |
| Duplicate files | same name different bytes, same size different bytes, true matches, hard links, preserve one, cancel hashing, no cloud downloads |
| Tools | no shell interpolation, bounded output/timeout/cancellation, odd paths, absent tool, failed JSON/parser, exact context/object IDs |
| Docker | local vs remote context, stopped engine, volume attached after review, named unused database volume high-impact, shared-size accounting, no force/global prune |
| UX/state | selection stable after sorting, stale/partial scan labels, scan cancellation, review consequence, blocked selection, per-item errors, restore state |
| Packaging | Dev/production names/IDs/data isolation, Dev no feed/startup updater, monotonic build validation, missing key fails release, Sparkle embedding, architecture/signature checks |
| Release | version/tag mismatch, missing secrets fail closed, appcast matches final artifact/build/signatures/URL, no unsigned stable fallback |

Performance acceptance: work executes off the main thread; scans are bounded/cancellable and stream incremental results; inventory uses metadata first; duplicate hashing is opt-in; subprocess concurrency/output are bounded; idle menu utility performs no continuous full-disk work. Record measured fixture/host timing instead of inventing benchmark claims. Cross-volume scans may be slower and must show progress.

## 13. Explicit limitations and later extensions

- Universal discovery means all accessible configured locations plus authoritative Git family expansion, not bypassing permissions or discovering disconnected storage.
- Process activity and exact APFS freed space are inherently uncertain; conservative labels and revalidation remain necessary.
- No silent cleanup, force worktree removal, branch deletion, OS optimization claims, privileged daemon, APFS erase, snapshot pruning, or VM disk truncation in the first release.
- Advanced safe support for additional package managers, on-device treemap rendering, FSEvents-driven incremental indexing, provider-specific disk compaction, and recovery bundles for otherwise blocked worktrees can follow the initial complete build.
- A real stable distribution/update round trip requires product-specific update signing configuration, valid Developer ID/notarization credentials, a published repository/feed, and manual install testing. Build all preparatory code and documentation without inventing access to these prerequisites.

## 14. Primary references checked while planning

- Owner's menu-bar reference: https://github.com/swlittles/Bustelo (plus the local source files listed above).
- Git worktree behavior, porcelain, locks, remove and prune: https://git-scm.com/docs/git-worktree
- Docker object/volume prune semantics and data-loss implications: https://docs.docker.com/engine/manage-resources/pruning/
- Sparkle integration and signed update requirements: https://sparkle-project.org/documentation/
- Quiet menu-bar update reminders: https://sparkle-project.org/documentation/gentle-reminders/
- Apple's Trash API: https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)
- Volume capacity: https://developer.apple.com/documentation/foundation/urlresourcevalues/volumeavailablecapacityforimportantusage
- Login items: https://developer.apple.com/documentation/servicemanagement/smappservice
- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

The implementation must support the installed Git/tool versions, not assume every latest documentation feature is available. Planning host: Apple Silicon macOS, Apple Swift 6.3.2, Git 2.43.0, Command Line Tools selected at `/Library/Developer/CommandLineTools`; full Xcode is not the selected developer directory.

## 15. Execution handoff

Execute this plan with **Claude Opus 5.5, effort `high`**, as requested. Work directly in `/Users/escanor/Projects/Personal/Reclaim`. Do not spawn further agents unless the user subsequently requests that. Build and validate the app, not just scaffolding or a second plan. Use fixture-only cleanup tests; no cleanup of the host's real storage. Continue all independent implementation when unavailable credentials or tools limit a distribution/provider check. Record exact limitations and leave a working Dev bundle. Do not publish releases, send messages, or modify sibling apps as part of this implementation handoff.
