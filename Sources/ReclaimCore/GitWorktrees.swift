import Foundation

public enum WorktreeParser {
    /// Git's -z porcelain terminates attributes with NUL and records with a second NUL.
    public static func parse(_ data: Data, commonDirectory: String) throws -> [Worktree] {
        guard data.isEmpty || data.last == 0 else { throw ReclaimError.refused("Truncated Git worktree output.") }
        var results: [Worktree] = [], fields: [String] = []
        func finish() throws {
            guard !fields.isEmpty else { return }
            guard let first = fields.first, first.hasPrefix("worktree ") else { throw ReclaimError.refused("Invalid Git worktree record.") }
            let path = String(first.dropFirst(9))
            guard path.hasPrefix("/") else { throw ReclaimError.refused("Git returned a non-absolute worktree path.") }
            var w = Worktree(path: path, commonDirectory: commonDirectory, head: "", main: results.isEmpty, bare: false)
            for field in fields.dropFirst() {
                if field.hasPrefix("HEAD ") { w.head = String(field.dropFirst(5)) }
                else if field.hasPrefix("branch ") { w.branch = String(field.dropFirst(7)) }
                else if field == "bare" { w.bare = true }
                else if field == "locked" || field.hasPrefix("locked ") { w.locked = String(field.dropFirst(min(7, field.count))) }
                else if field == "prunable" || field.hasPrefix("prunable ") { w.prunable = String(field.dropFirst(min(9, field.count))) }
                else if field != "detached" { throw ReclaimError.refused("Unsupported worktree attribute: \(field)") }
            }
            guard w.bare || !w.head.isEmpty else { throw ReclaimError.refused("Missing worktree HEAD.") }
            results.append(w); fields = []
        }
        for segment in data.split(separator: 0, omittingEmptySubsequences: false) {
            guard let field = String(data: Data(segment), encoding: .utf8) else { throw ReclaimError.refused("A Git path is not valid UTF-8; inventory cannot safely act on it.") }
            if field.isEmpty { try finish() } else { fields.append(field) }
        }
        try finish(); return results
    }
}
public final class GitService {
    let runner: CommandRunning
    let executable: String
    public init(runner: CommandRunning = ProcessRunner(), executable: String = "/usr/bin/git") { self.runner = runner; self.executable = executable }
    public func command(_ args: [String], at path: String, token: CancellationToken? = nil) throws -> CommandResult {
        try runner.run(executable, ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "core.untrackedCache=false"] + args, cwd: path, timeout: 30, token: token)
    }
    func required(_ args: [String], at path: String, token: CancellationToken? = nil) throws -> String {
        let r = try command(args, at: path, token: token)
        guard r.code == 0 else { throw ReclaimError.refused("Git inspection failed (\(r.code)): \(r.error.prefix(500))") }
        return r.output.hasSuffix("\n") ? String(r.output.dropLast()) : r.output
    }
    public func family(at path: String, token: CancellationToken? = nil) throws -> [Worktree] {
        let common = try required(["rev-parse", "--path-format=absolute", "--git-common-dir"], at: path, token: token)
        guard common.hasPrefix("/") else { throw ReclaimError.refused("Git common directory could not be resolved.") }
        let result = try command(["worktree", "list", "--porcelain", "-z"], at: path, token: token)
        guard result.code == 0 else { throw ReclaimError.refused("Installed Git cannot list NUL-delimited worktrees.") }
        return try WorktreeParser.parse(result.data, commonDirectory: URL(fileURLWithPath: common).resolvingSymlinksInPath().path)
    }
    public func inspect(_ input: Worktree, activity: ActivitySnapshot, token: CancellationToken? = nil) -> Worktree {
        var w = input
        w.blockers = []
        if w.main { w.blockers.append("Main repository; worktree removal is disabled.") }
        if w.bare { w.blockers.append("Bare repository; protected."); return w }
        if w.locked != nil { w.blockers.append("Locked worktree: \(w.locked ?? "")") }
        if w.prunable != nil { w.blockers.append("Missing or stale registration; inventory only. Offline volumes must not be pruned.") }
        guard FileManager.default.fileExists(atPath: w.path) else { w.blockers.append("Worktree path is missing, inaccessible, or on an offline volume."); return w }
        let lower = w.path.lowercased()
        if lower.contains("/.codex/") { w.ownerHint = "Codex location" }
        else if lower.contains("/.cursor/") { w.ownerHint = "Cursor location" }
        else if lower.contains("/.claude/") { w.ownerHint = "Claude location" }
        else if lower.contains("/t3") { w.ownerHint = "Possible T3 location" }
        do {
            let status = try command(["status", "--porcelain=v2", "-z", "--untracked-files=all"], at: w.path, token: token)
            guard status.code == 0 else { throw ReclaimError.refused("Cannot determine working tree status.") }
            w.status = status.output
            if !status.data.isEmpty { w.blockers.append("Contains changes, untracked files, conflicts, or submodule changes.") }
            let ignored = try command(["ls-files", "--others", "--ignored", "--exclude-standard", "-z"], at: w.path, token: token)
            guard ignored.code == 0 else { throw ReclaimError.refused("Cannot inspect ignored files.") }
            if !ignored.data.isEmpty { w.blockers.append("Contains ignored files; these may include .env files, data, or credentials.") }
            if FileManager.default.fileExists(atPath: w.path + "/.gitmodules") { w.blockers.append("Contains submodules; automatic worktree removal is disabled.") }
            let gitDir = try required(["rev-parse", "--absolute-git-dir"], at: w.path, token: token)
            for marker in ["index.lock", "HEAD.lock", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG", "rebase-apply", "rebase-merge"] {
                if FileManager.default.fileExists(atPath: gitDir + "/" + marker) { w.blockers.append("Git operation or lock present: \(marker)") }
            }
            let currentHead = try required(["rev-parse", "HEAD"], at: w.path, token: token)
            guard currentHead == w.head else { throw ReclaimError.refused("HEAD changed during inventory; rescan.") }
            // Keep only durable branches/tags/remotes; another worktree's HEAD or a reflog is not a backup.
            let refs = try required(["for-each-ref", "--contains=" + w.head, "--format=%(refname)", "refs/heads", "refs/tags", "refs/remotes", "refs/reclaim"], at: w.path, token: token)
            if refs.isEmpty { w.blockers.append("HEAD has no durable branch, tag, remote-tracking, or Reclaim safety reference.") }
            let up = try command(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], at: w.path, token: token)
            if up.code == 0 { w.upstream = up.output.trimmingCharacters(in: .newlines) }
            if let reason = activity.blocker(for: w.path) { w.blockers.append(reason) }
        } catch { w.blockers.append(error.localizedDescription) }
        return w
    }
    public func remove(_ expected: Worktree, activity: ActivitySnapshot, token: CancellationToken? = nil) throws -> String {
        let family = try family(at: expected.path, token: token)
        guard let current = family.first(where: { $0.path == expected.path }), current.commonDirectory == expected.commonDirectory, current.head == expected.head, current.branch == expected.branch else { throw ReclaimError.refused("Worktree registration or HEAD changed; rescan.") }
        let checked = inspect(current, activity: activity, token: token)
        guard checked.canRemove else { throw ReclaimError.refused(checked.blockers.joined(separator: "\n")) }
        let ref = "refs/reclaim/" + UUID().uuidString.lowercased()
        _ = try required(["update-ref", ref, checked.head, String(repeating: "0", count: checked.head.count)], at: checked.path, token: token)
        guard try required(["rev-parse", ref], at: checked.path, token: token) == checked.head else { throw ReclaimError.refused("Safety ref verification failed.") }
        let last = inspect(checked, activity: activity, token: token)
        guard last.canRemove else { throw ReclaimError.refused("Worktree changed before removal. Safety ref: \(ref)") }
        let result = try command(["--git-dir=" + checked.commonDirectory, "worktree", "remove", "--", checked.path], at: checked.commonDirectory, token: token)
        guard result.code == 0 else { throw ReclaimError.refused("Git refused removal: \(result.error.prefix(500)). Preserved safety ref: \(ref)") }
        return ref
    }
}
public struct ActivitySnapshot {
    public var paths: [String]
    public var known: Bool
    public init(paths: [String], known: Bool = true) { self.paths = paths; self.known = known }
    public static func capture(runner: CommandRunning = ProcessRunner()) -> ActivitySnapshot {
        do {
            let result = try runner.run("/usr/sbin/lsof", ["-n", "-P", "-a", "-u", NSUserName(), "-d", "cwd", "-F", "n"], cwd: "/", timeout: 15, token: nil)
            guard result.code == 0 else { return ActivitySnapshot(paths: [], known: false) }
            return ActivitySnapshot(paths: result.output.split(separator: "\n").filter { $0.hasPrefix("n/") }.map { String($0.dropFirst()) })
        } catch { return ActivitySnapshot(paths: [], known: false) }
    }
    public func blocker(for path: String) -> String? {
        if !known { return "Running-process activity could not be checked." }
        let artifact = [".build", "node_modules", "target", ".venv", "venv"].contains(URL(fileURLWithPath: path).lastPathComponent)
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if paths.contains(where: { isWithin($0, path) || (artifact && $0 == parent) }) { return "A running process has its working directory inside this item or its project root." }
        return nil
    }
}
