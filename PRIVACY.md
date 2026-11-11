# Privacy

Reclaim has no account, analytics, advertisements or remote analysis. It scans file metadata locally; optional duplicate detection reads candidate file contents locally for SHA-256. File contents are not persisted or uploaded. It does not parse coding-agent conversations, credentials, or session databases for worktree discovery.

Versioned settings, scan summaries and cleanup journals are JSON files under `~/Library/Application Support/Reclaim Dev/` or `~/Library/Application Support/Reclaim/`. Directories are created with mode 0700; saved files use 0600. They contain paths, sizes, Git branch/commit/reference metadata, tool identities, and operation outcomes. They are not encrypted. A user's paths and local tool output may be sensitive: review them before sharing screenshots or bug reports.

Full Disk Access is optional. Standard user permissions, TCC, offline disks, and scan exclusions govern coverage. The app does not request Accessibility, root access, or credentials. Developer tool overrides execute local programs you select.

Dev builds never initialize Sparkle. Production supports optional automatic checks and manual checks through HTTPS GitHub release feeds and downloads, verified with Sparkle signatures. These requests necessarily expose your IP address and normal HTTP request metadata to those services. System profiling is disabled and installation is user initiated. Disable automatic checks in Settings if desired.

Open at Login uses Apple's ServiceManagement API. Optional low-space notifications require notification permission; daily read-only scans are opt-in. Neither feature removes files automatically.

Settings can clear cached scan results. You can quit the app and remove its Application Support directory to remove settings/history; macOS preferences and login registration can be reset separately. Removing the app does not empty Trash or delete Git safety refs. Safety refs intentionally remain in each source repository until you deliberately remove them with Git.
