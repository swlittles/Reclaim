# Architecture

`ReclaimCore` contains models, filesystem measurement, bounded command runner, scanner, Git safety/discovery, Docker local context validation, immutable cleanup plans, journal/Trash recovery, and duplicate hashing. It has no AppKit or Sparkle dependency. Dependencies are injectable at destructive boundaries: `CommandRunning`, `TrashManaging`, `LocalStore`, `GitService`, process activity and exclusions.

`Reclaim` owns AppKit lifecycle, NSStatusItem, NSWindow hosting SwiftUI, MainActor observable state, notifications/login items, running-application protection and Sparkle. Scanning, hashing, subprocesses and cleanup run off the main actor and publish progress/results. The app holds one active scan/cleanup task at a time and disables conflicting UI actions.

`StorageScanner` inventories known user/developer locations and walks accessible configured roots with skip lists, cancellation and budgets. Evidenced artifact detection requires a manifest/environment marker. Git roots are fed into `GitService`: absolute common directory resolution, NUL-delimited family parsing and authoritative inspection. Registered family paths expand beyond search roots, with their exact paths shown in review. No global worktree registry is assumed.

Git uses status porcelain v2, separate ignored-file listing, operation markers and durable references. Reads disable fsmonitor/hooks/optional locks and never fetch. Actual removal creates/verifies a safety ref and calls Git without force. Docker validates known unix-socket endpoints, uses exact context/object IDs, signs a stable inspection fingerprint, rechecks references/state, and avoids shared-size arithmetic.

`CleanupPlan` freezes targets and refuses overlaps. `CleanupExecutor` checks owner/type/ancestors, exclusions, bounded metadata fingerprint and process activity; journals before mutation; then revalidates again. Failure never chooses a more destructive fallback. History reconciles a Started record as interrupted/unknown, rather than replaying. Restore requires original parent identity and an absent target.

Measurements count file allocation using `st_blocks`, deduplicate hardlinks within a tree and include a metadata digest of entry identity, size and timestamps. Nested symlinks are recorded without traversal. Placeholder/nested-volume/permission/limit cases are incomplete, so cannot become cleanup targets. APFS shared storage and separate findings' hardlink overlap remain estimated.

Persistence is local, versioned by the Codable model schema as the initial format; future incompatible schema migrations must preserve journal recovery data. Files use atomic replacement and owner-only permissions. Release and development locations are distinct. See SAFETY.md for residual path races and activity-detection limits.


`TrashService` discovers only conventional current-user Trash roots (home and mounted local disks), measures top-level items with progress, and reports per-location coverage. `TrashInventory` creates either a selected-item or complete-inventory immutable cleanup plan; search is a UI concern and never changes empty-all scope. Production uses the real home/mounted-volume provider, while fixture tests inject their own home and volume paths. `CleanupExecutor` validates permanent-removal scope again against the live provider before acting. The Trash view keeps its own selection, does not run a full home scan, and refreshes after reviewed deletion. It does not persist the dedicated Trash snapshot across launches.
