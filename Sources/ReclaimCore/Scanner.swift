import Foundation

public struct ScanOptions {
    public var home: String
    public var roots: [String]
    public var exclusions: [String]
    public var deep: Bool
    public var includeSystemLocations: Bool
    public var largeFileThreshold: Int64
    public var toolOverrides: [String: String]
    public var applicationRoots: [String]?
    public init(home: String = FileManager.default.homeDirectoryForCurrentUser.path, roots: [String] = [], exclusions: [String] = [], deep: Bool = false, includeSystemLocations: Bool = true, largeFileThreshold: Int64 = 500_000_000, toolOverrides: [String: String] = [:], applicationRoots: [String]? = nil) {
        self.home = home; self.roots = roots; self.exclusions = exclusions; self.deep = deep
        self.includeSystemLocations = includeSystemLocations; self.largeFileThreshold = largeFileThreshold; self.toolOverrides = toolOverrides
        self.applicationRoots = applicationRoots
    }
}
public final class StorageScanner {
    public let token: CancellationToken
    public init(token: CancellationToken = CancellationToken()) { self.token = token }
    public static func defaultRoots(home: String) -> [String] {
        let projects = ["Projects", "Developer", "Development", "Code", "src"].map { home + "/" + $0 }
        return Array(Set(projects + worktreeLocations(home: home).map(\.path))).sorted().filter { FileManager.default.fileExists(atPath: $0) }
    }
    public static func worktreeLocations(home: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> [(name: String, path: String)] {
        var locations = [("T3 Code", home + "/.t3/worktrees"), ("Codex", home + "/.codex/worktrees"), ("Claude Code (home candidate)", home + "/.claude/worktrees"), ("Cursor", home + "/.cursor/worktrees")]
        for (name, variable) in [("Codex (CODEX_HOME)", "CODEX_HOME"), ("Claude Code (CLAUDE_CONFIG_DIR)", "CLAUDE_CONFIG_DIR")] {
            if let base = environment[variable], base.hasPrefix("/") { locations.append((name, FileSystem.normalized(base) + "/worktrees")) }
        }
        var seen = Set<String>()
        return locations.filter { seen.insert($0.1).inserted }
    }
    public func scan(_ options: ScanOptions, activityProgress: (ScanProgress) -> Void = { _ in }, progress: @escaping (String, [Finding]) -> Void = { _, _ in }) -> ScanResult {
        var result = ScanResult(), seen = Set<String>(), repos = Set<String>(), families = Set<String>()
        var candidates: [Finding] = []
        let fm = FileManager.default
        activityProgress(ScanProgress("Checking running processes"))
        let activity = ActivitySnapshot.capture()
        activityProgress(ScanProgress("Discovering locations"))
        let git = GitService(executable: ToolLocator.find("git", overrides: options.toolOverrides) ?? "/usr/bin/git")
        func excluded(_ p: String) -> Bool { options.exclusions.contains { isWithin(p, $0) } }
        func add(_ path: String, _ category: Category, _ detail: String, _ action: CleanupAction = .trash, blocked: String? = nil, worktree: Worktree? = nil) {
            guard !token.isCancelled, !excluded(path) else { return }
            // A generic cache row must never bypass a more specific shared-store protection.
            if !seen.insert(path).inserted {
                if let index = candidates.firstIndex(where: { $0.path == path }) {
                    if action == .reportOnly {
                        candidates[index].action = action; candidates[index].blockedReason = blocked
                        candidates[index].category = category; candidates[index].detail = detail
                    } else if category == .applications { candidates[index].detail += " " + detail }
                }
                return
            }
            let modified = (try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date
            let repositoryRoot = action == .trash && fm.fileExists(atPath: path + "/.git")
            let reason = blocked ?? (repositoryRoot ? "Repository root; remove only its individual build artifacts." : nil)
            candidates.append(Finding(path: path, category: category, detail: detail, modified: modified, action: action, blockedReason: reason, git: worktree))
        }
        func children(_ path: String, _ category: Category, _ detail: String, _ action: CleanupAction = .trash, blocked: String? = nil) {
            activityProgress(ScanProgress("Discovering locations", completed: Double(candidates.count), unit: "candidates", path: path))
            guard fm.fileExists(atPath: path), !excluded(path) else { return }
            do { for url in try fm.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil) { if token.isCancelled { break }; add(url.path, category, detail, action, blocked: blocked) } }
            catch { result.issues.append("\(path): \(error.localizedDescription)"); result.complete = false }
        }
        if options.includeSystemLocations {
            children(options.home + "/Library/Caches", .caches, "User cache. Review its owner before removal; it may be rebuilt.")
            children(options.home + "/Library/Logs", .logs, "User log files. Keep logs needed for troubleshooting.")
            children(options.home + "/Downloads", .downloads, "Personal download. Age alone does not make it disposable.")
            children(options.home + "/.Trash", .trash, "Already in Trash. Permanent deletion cannot be undone.", .permanentlyDelete)
            children(options.home + "/Library/Developer/Xcode/DerivedData", .developer, "Xcode DerivedData; regenerates on next build.")
            children(options.home + "/Library/Developer/Xcode/Archives", .developer, "Xcode archive may be needed for distribution and symbolication; review carefully.")
            children(options.home + "/Library/Developer/Xcode/iOS DeviceSupport", .developer, "Xcode device support; may need downloading again.")
            children(options.home + "/Library/Application Support/MobileSync/Backup", .backups, "Device backup. May be the only copy of device data.")
            for p in options.applicationRoots ?? ["/Applications", options.home + "/Applications"] {
                guard let apps = try? fm.contentsOfDirectory(atPath: p) else { continue }
                for app in apps where app.hasSuffix(".app") {
                    let appPath = p + "/" + app
                    add(appPath, .applications, "Application bundle. Related user data is preserved unless individually selected.")
                    if let id = Bundle(path: appPath)?.bundleIdentifier, !id.contains("/"), id.contains(".") {
                        for relative in ["Library/Caches/" + id, "Library/Preferences/" + id + ".plist", "Library/Saved Application State/" + id + ".savedState"] {
                            let dataPath = options.home + "/" + relative
                            if fm.fileExists(atPath: dataPath) { add(dataPath, .applications, "Exact bundle identifier \(id), associated with \(app). Individually reviewed app data; support folders, shared groups and Keychains are preserved.") }
                        }
                    }
                }
            }
            let shared: [(String, String)] = [(".npm", "npm cache"), (".cache/uv", "uv cache"), ("Library/Caches/pip", "pip cache"), ("Library/Caches/Homebrew", "Homebrew cache"), (".gradle/caches", "Gradle shared cache"), (".m2/repository", "Maven repository"), (".cargo/registry", "Cargo shared registry"), ("Library/Developer/CoreSimulator/Devices", "Simulator devices"), ("Library/Android/sdk", "Android SDK"), (".android/avd", "Android virtual devices"), (".local/share/pnpm/store", "pnpm shared store")]
            for (relative, label) in shared {
                let p = options.home + "/" + relative
                if fm.fileExists(atPath: p) { add(p, .developer, label + ". Shared or tool-managed; inventory only. Use the owning tool for maintenance.", .reportOnly, blocked: "Tool-managed shared storage; inventory only.") }
            }
            let vms = ["Library/Containers/com.docker.docker/Data/vms", ".colima", ".lima", "Library/Group Containers/HUAQ24HBR6.dev.orbstack"]
            for relative in vms {
                let p = options.home + "/" + relative
                if fm.fileExists(atPath: p) { add(p, .virtualDisks, "Provider-managed VM storage. Allocated size is an estimate; never remove a live disk directly.", .reportOnly, blocked: "Use the owning VM application's storage tools.") }
            }
        }
        var roots = options.roots + (options.includeSystemLocations ? Self.defaultRoots(home: options.home) : [])
        if options.deep { roots.append(options.home) }
        roots = Array(Set(roots.map { FileSystem.normalized($0) })).sorted()
        // Keep separate root searches when one is hidden under an otherwise-pruned directory.
        result.roots = roots
        var visited = Set<String>(), inspected = 0
        let deadline = Date().addingTimeInterval(options.deep ? 600 : 180)
        for root in roots {
            if token.isCancelled { break }
            guard !excluded(root) else { continue }
            guard fm.fileExists(atPath: root) else { result.issues.append("Unavailable scan root: \(root)"); result.complete = false; continue }
            var stack: [(String, Int)] = [(root, 0)]
            while let (path, depth) = stack.popLast() {
                if token.isCancelled { break }
                inspected += 1
                if inspected > 300_000 || Date() > deadline { result.complete = false; result.issues.append("Search budget reached; add targeted roots to finish coverage."); stack = []; break }
                guard !excluded(path), let s = try? FileSystem.info(path), FileSystem.directory(s), !FileSystem.symlink(s), !FileSystem.cloudOnly(s), visited.insert(FileSystem.identity(s)).inserted else { continue }
                let bareCandidate = fm.fileExists(atPath: path + "/HEAD") && fm.fileExists(atPath: path + "/objects")
                if fm.fileExists(atPath: path + "/.git") || bareCandidate { repos.insert(path) }
                if bareCandidate { continue }
                guard depth < (options.deep ? 24 : 12) else { result.complete = false; result.issues.append("Depth limit: \(path)"); continue }
                do {
                    for url in try fm.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil) {
                        if token.isCancelled { break }
                        let name = url.lastPathComponent
                        guard !excluded(url.path), let child = try? FileSystem.info(url.path), !FileSystem.symlink(child), !FileSystem.cloudOnly(child), child.st_dev == s.st_dev else { continue }
                        if !FileSystem.directory(child) {
                            if child.st_size >= options.largeFileThreshold { add(url.path, .largeFiles, "Large file discovered in a selected root. Review contents before removal.") }
                            continue
                        }
                        let artifact: String?
                        switch name {
                        case "node_modules" where fm.fileExists(atPath: path + "/package.json"): artifact = "JavaScript dependencies; reinstall using this project's lockfile."
                        case ".build" where fm.fileExists(atPath: path + "/Package.swift"): artifact = "SwiftPM build output; rebuilding can take time."
                        case "target" where fm.fileExists(atPath: path + "/Cargo.toml"): artifact = "Rust build output; recreates on next build."
                        case ".venv" where fm.fileExists(atPath: url.path + "/pyvenv.cfg"), "venv" where fm.fileExists(atPath: url.path + "/pyvenv.cfg"): artifact = "Python virtual environment. Keep any locally edited or installed-only content."
                        default: artifact = nil
                        }
                        if let artifact { add(url.path, .developer, artifact); continue }
                        if [".git", "node_modules", ".build", "target", ".Trash", ".cache", ".npm", ".cargo", ".gradle", ".m2", "Library", ".ssh", ".gnupg", ".aws", ".azure", ".kube", ".config", "Photos Library.photoslibrary"].contains(name) || name.hasSuffix(".app") || name.hasSuffix(".photoslibrary") || name.hasSuffix(".sparsebundle") { continue }
                        stack.append((url.path, depth + 1))
                    }
                } catch { result.issues.append("\(path): \(error.localizedDescription)"); result.complete = false }
                if inspected % 200 == 0 { activityProgress(ScanProgress("Discovering project folders", completed: Double(inspected), unit: "folders", path: path)) }
            }
        }
        for (index, path) in repos.sorted().enumerated() {
            if token.isCancelled { break }
            activityProgress(ScanProgress("Inspecting Git repositories", completed: Double(index), total: Double(repos.count), unit: "repositories", path: path))
            do {
                let family = try git.family(at: path, token: token)
                guard let common = family.first?.commonDirectory, families.insert(common).inserted else { continue }
                for input in family {
                    let w = git.inspect(input, activity: activity, token: token)
                    // Registered worktrees can live beyond search roots. Still surface their
                    // evidenced build artifacts, rather than requiring the entire worktree to go.
                    if !w.bare {
                        let artifacts = [("node_modules", "package.json", "JavaScript dependencies"), (".build", "Package.swift", "SwiftPM build output"), ("target", "Cargo.toml", "Rust build output"), (".venv", ".venv/pyvenv.cfg", "Python virtual environment"), ("venv", "venv/pyvenv.cfg", "Python virtual environment")]
                        for (directory, marker, label) in artifacts {
                            let p = w.path + "/" + directory
                            if fm.fileExists(atPath: p) && fm.fileExists(atPath: w.path + "/" + marker) {
                                add(p, .developer, label + " inside a registered worktree. Review local changes before removal; rebuild cost may be significant.")
                            }
                        }
                    }
                    add(w.path, .worktrees, "\(URL(fileURLWithPath: common).deletingLastPathComponent().lastPathComponent) · \(w.branch?.replacingOccurrences(of: "refs/heads/", with: "") ?? (w.bare ? "bare" : "detached HEAD")) · \(w.ownerHint). \(w.reachability)", .worktree, blocked: w.blockers.isEmpty ? nil : w.blockers.joined(separator: "\n"), worktree: w)
                }
            } catch { result.issues.append("Git \(path): \(error.localizedDescription)"); result.complete = false }
        }
        if !token.isCancelled { activityProgress(ScanProgress("Inspecting Git repositories", completed: Double(repos.count), total: Double(repos.count), unit: "repositories")) }
        // Discover first so measurement has a stable, real denominator. Stream completed items.
        for (index, candidate) in candidates.enumerated() {
            if token.isCancelled { break }
            var finding = candidate
            activityProgress(ScanProgress("Measuring storage", completed: Double(index), total: Double(candidates.count), path: finding.path))
            if token.isCancelled { break }
            finding.measurement = FileSystem.measure(finding.path, token: token, progress: { entries in
                activityProgress(ScanProgress("Measuring storage", completed: Double(index), total: Double(candidates.count), path: finding.path, filesInspected: entries))
            })
            if !fm.fileExists(atPath: finding.path) { finding.measurement.warning = "Missing or inaccessible path"; finding.measurement.complete = false }
            finding.blockedReason = finding.blockedReason ?? finding.measurement.warning ?? (finding.action == .trash ? activity.blocker(for: finding.path) : nil)
            result.findings.append(finding)
            progress(finding.path, [finding])
            if !token.isCancelled { activityProgress(ScanProgress("Measuring storage", completed: Double(index + 1), total: Double(candidates.count), path: finding.path)) }
        }
        if options.includeSystemLocations {
            activityProgress(ScanProgress("Inspecting local Docker storage"))
            let docker = DockerService(executable: ToolLocator.find("docker", overrides: options.toolOverrides))
            let inventory = docker.inventory(token: token)
            result.findings += inventory.findings; result.issues += inventory.issues
        }
        activityProgress(ScanProgress("Checking disk capacity"))
        result.volumes = Self.volumes()
        result.complete = result.complete && !token.isCancelled
        if token.isCancelled { result.issues.append("Scan cancelled. Results are partial.") }
        result.findings.sort { $0.measurement.allocated > $1.measurement.allocated }
        return result
    }
    public static func volumes() -> [VolumeInfo] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsReadOnlyKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
            return VolumeInfo(path: url.path, name: v.volumeName ?? url.lastPathComponent, total: Int64(v.volumeTotalCapacity ?? 0), free: Int64(v.volumeAvailableCapacity ?? 0), local: v.volumeIsLocal ?? false, removable: v.volumeIsRemovable ?? false, readOnly: v.volumeIsReadOnly ?? true)
        }
    }
}
