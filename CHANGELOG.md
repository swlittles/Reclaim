# Changelog

## 0.1.3

- Add a dedicated Trash sidebar screen and menu-bar shortcut, with Trash-only refresh, allocation totals, search, item inspection, separate selection and deletion history.
- Add Empty Trash and Delete Selected review flows with an explicit permanent-deletion acknowledgment. Empty Trash reviews the complete scanned inventory even when search hides rows; items added afterward remain untouched.
- Inventory the current user's home Trash and Trash on mounted local disks. Show missing, excluded, inaccessible, partial and cancelled states without claiming an incomplete scan is empty.
- Require complete coverage and no protected/excluded items for Empty Trash. Eligible individual items can still be reviewed separately; show Finder and Full Disk Access shortcuts for access problems.
- Restrict permanent deletion to reviewed direct children of live current-user Trash roots; revalidate fingerprints, ancestry, active processes and exclusions before deletion. Offline-volume, changed, linked or excluded targets are skipped.

## 0.1.2

- Add scan phase progress bars with real repository/item percentages after discovery, entry counts during large measurements, and byte progress during duplicate hashing. Unknown discovery/provider totals remain indeterminate rather than showing invented percentages.
- Add a configurable low-storage menu-bar warning: yellow percent free when startup-disk available space reaches a percent or decimal-GB threshold. Default is 10% free; refreshes every minute and on menu open. Existing settings are preserved.
- Replace stacked filter rows with one fixed-height toolbar: search, Filters with active count and Reset, sort, Select menu, and item count. Move worktree discovery/protection details into an info popover.
- Preserve partial-scan/cancellation behavior and surface duplicate candidates that cannot be hashed as coverage notes.

## 0.1.1

- Show linked worktrees by default, separate main repositories, explain protection, and show ignored-file examples without weakening removal checks.
- Add Select All Shown and Clear Selection; bulk selection respects filters, exclusions, overlapping paths, and retention of one known duplicate copy.
- Classify expected cleanup impact and filter by cache, diagnostics, rebuild/reinstall, app functionality/settings, personal data, repository, tool-managed, or unknown impact. Explain evidence and consequences in the inspector and final review.
- Add 7-day, 14-day (two-week), and custom age filters. Worktree age uses the newest observed content/Git modification; incomplete or unknown ages are excluded.
- Show worktree discovery locations, identify repository-local Claude Code paths and T3 Code paths accurately, and honor inherited CODEX_HOME/CLAUDE_CONFIG_DIR worktree candidates.
- Coalesce the same path across inventory categories so generic cache rows cannot bypass shared-store protections.
- Read the About version from the installed bundle.

## 0.1.0

- Native menu-bar storage inventory and reviewed cleanup.
- Git worktree families across arbitrary locations with conservative removal checks.
- Developer artifacts, local Docker objects, filesystem volumes and VM inventory.
- Content duplicates, Trash recovery, local action history, isolated Dev builds.
- Signed Sparkle update integration and universal notarized release pipeline.

Initial release. Universal Developer ID distribution and a signed Sparkle feed are produced by the release workflow.
