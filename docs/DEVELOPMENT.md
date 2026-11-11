# Development

Use `bash scripts/test.sh` and `bash scripts/build.sh`; then open `dist/Reclaim Dev.app`. The tests are a standalone Swift executable, so Command Line Tools are sufficient. `swift run ReclaimCoreTests` runs core fixtures; Python's standard-library unittest runs release gating checks. SwiftPM debug runs are development identity too.

| | Production | Development |
| --- | --- | --- |
| Name | Reclaim | Reclaim Dev |
| Bundle ID | io.github.swlittles.Reclaim | io.github.swlittles.Reclaim.dev |
| Application Support | Reclaim/ | Reclaim Dev/ |
| Updates | Signed Sparkle feed | Never initialized, no feed keys |
| Signing | Developer ID release | Ad-hoc by default |

No data is copied between profiles. A production identity build requires a genuine per-product public update key; prefer Dev for everyday work. Local packaging refuses to overwrite its running target. `RECLAIM_OUTPUT_DIR` changes destination; `RECLAIM_UNIVERSAL=1` builds both architectures. `RECLAIM_SIGNING_IDENTITY` selects a signing identity.

The scan menu also supports **Scan Added Folders Only**, which omits built-in user locations and default project roots for targeted scans.

The packaged executable's `--diagnostics` prints identity/data directory/feed presence without initializing UI or scanning. `--show-window` opens the native window. `--smoke-test` opens the app/window and exits after three seconds without scanning or cleanup.

Do not run real cleanup to test the implementation. Use temporary fixtures. Do not add tests pointed at actual projects, caches, containers, or volumes. Tool paths in Settings are absolute overrides; leave blank for system/Homebrew discovery.
