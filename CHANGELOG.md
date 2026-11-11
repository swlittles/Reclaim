# Changelog

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
