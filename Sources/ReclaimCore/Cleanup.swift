import Foundation

public struct CleanupPlan {
    public let id = UUID()
    public let findings: [Finding]
    public let roots: [String]
    public let created = Date()
    public var allocated: Int64 { FileSystem.nonoverlapping(findings.filter { $0.docker == nil }).reduce(0) { $0 + $1.measurement.allocated } }
    public init(findings: [Finding], exclusions: [String]) throws {
        guard !findings.isEmpty, findings.allSatisfy({ $0.selectable }) else { throw ReclaimError.refused("Choose eligible items first.") }
        let paths = findings.filter { $0.docker == nil }.map(\.path)
        guard paths.count == Set(paths).count else { throw ReclaimError.refused("The same path is selected in more than one category.") }
        for p in paths {
            guard !paths.contains(where: { $0 != p && isWithin(p, $0) }) else { throw ReclaimError.refused("Parent and child items overlap. Review only one of them.") }
            guard !exclusions.contains(where: { isWithin(p, $0) }) else { throw ReclaimError.refused("An item is excluded.") }
        }
        self.findings = findings; roots = paths
    }
}
public struct HistoryEntry: Identifiable, Codable {
    public var id = UUID()
    public var date = Date()
    public var path: String
    public var action: CleanupAction
    public var status: String
    public var detail: String
    public var trashPath: String?
    public var trashFingerprint: Fingerprint?
    public var originalAncestors: [String]?
    public init(path: String, action: CleanupAction, status: String, detail: String) { self.path = path; self.action = action; self.status = status; self.detail = detail }
}
public protocol TrashManaging {
    func trash(_ path: String) throws -> String
    func restore(_ from: String, to: String) throws
}
public final class SystemTrash: TrashManaging {
    public init() {}
    public func trash(_ path: String) throws -> String {
        var result: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &result)
        guard let result else { throw ReclaimError.refused("Moved to Trash, but macOS did not return its location. Inspect Trash manually.") }
        return result.path ?? ""
    }
    public func restore(_ from: String, to: String) throws {
        guard !FileManager.default.fileExists(atPath: to) else { throw ReclaimError.refused("Restore destination already exists; nothing was overwritten.") }
        try FileManager.default.moveItem(atPath: from, toPath: to)
    }
}
public final class CleanupExecutor {
    let store: LocalStore
    let trash: TrashManaging
    let git: GitService
    let trashService: TrashService
    private let lock = NSLock()
    public init(store: LocalStore = LocalStore(), trash: TrashManaging = SystemTrash(), git: GitService = GitService(), trashService: TrashService = TrashService()) { self.store = store; self.trash = trash; self.git = git; self.trashService = trashService }
    public func history() -> [HistoryEntry] {
        (store.read([HistoryEntry].self, from: "history.json") ?? []).map { value in
            var v = value
            if v.status == "Started" { v.status = "Interrupted — inspect before retry"; v.detail = "An operation did not record its outcome. It will never be replayed automatically." }
            return v
        }
    }
    func save(_ entry: HistoryEntry) throws {
        var entries = store.read([HistoryEntry].self, from: "history.json") ?? []
        entries.removeAll { $0.id == entry.id }; entries.insert(entry, at: 0)
        try store.write(entries, to: "history.json")
    }
    public func execute(_ plan: CleanupPlan, exclusions: () -> [String], token: CancellationToken, activity: (() -> ActivitySnapshot)? = nil, progress: (HistoryEntry) -> Void = { _ in }) -> [HistoryEntry] {
        guard lock.try() else { return [] }; defer { lock.unlock() }
        var outcomes: [HistoryEntry] = []
        for finding in plan.findings {
            if token.isCancelled { break }
            var entry = HistoryEntry(path: finding.path, action: finding.action, status: "Started", detail: finding.action.label)
            do {
                guard !exclusions().contains(where: { finding.path == $0 || isWithin(finding.path, $0) }) else { throw ReclaimError.refused("Item was excluded after review.") }
                if finding.action == .permanentlyDelete { try trashService.validateTarget(finding.path, exclusions: exclusions()) }
                if finding.docker == nil {
                    try PathGuard().validate(finding.path, allowedRoots: plan.roots, exclusions: exclusions())
                    let current = FileSystem.measure(finding.path, token: token)
                    guard current.complete, let expected = finding.measurement.fingerprint, current.fingerprint == expected else { throw ReclaimError.refused("Item or its ancestors changed after the scan; rescan before cleanup.") }
                    entry.originalAncestors = expected.ancestors
                    if let reason = (activity?() ?? ActivitySnapshot.capture()).blocker(for: finding.path) { throw ReclaimError.refused(reason) }
                }
                try save(entry) // A journal failure prevents the mutation.
                if finding.docker == nil {
                    try PathGuard().validate(finding.path, allowedRoots: plan.roots, exclusions: exclusions())
                    let final = FileSystem.measure(finding.path, token: token)
                    guard final.complete, final.fingerprint == finding.measurement.fingerprint else { throw ReclaimError.refused("Target changed immediately before execution; skipped.") }
                    if finding.action == .trash && FileManager.default.fileExists(atPath: finding.path + "/.git") { throw ReclaimError.refused("Repository roots cannot be moved as ordinary cleanup.") }
                }
                switch finding.action {
                case .trash:
                    let destination = try trash.trash(finding.path)
                    entry.trashPath = destination; entry.trashFingerprint = FileSystem.measure(destination).fingerprint
                    entry.detail = "Moved to Trash. Space is not freed until Trash is emptied."
                case .permanentlyDelete:
                    try trashService.validateTarget(finding.path, exclusions: exclusions())
                    try FileManager.default.removeItem(atPath: finding.path)
                    entry.detail = "Deleted from Trash permanently."
                case .worktree:
                    guard let w = finding.git else { throw ReclaimError.refused("Missing Git safety metadata.") }
                    let ref = try git.remove(w, activity: activity?() ?? ActivitySnapshot.capture(), token: token)
                    entry.detail = "Removed worktree; branch retained. Commit \(w.head) preserved at \(ref) in \(w.commonDirectory)."
                case .dockerVolume, .dockerContainer, .dockerImage:
                    guard let target = finding.docker else { throw ReclaimError.refused("Missing Docker identity.") }
                    try DockerService(executable: target.executable).remove(target, action: finding.action, token: token)
                    entry.detail = "Removed exact reviewed Docker object; no Undo."
                case .reportOnly: throw ReclaimError.refused("Inventory-only item cannot be removed.")
                }
                entry.status = "Completed"
            } catch { entry.status = "Skipped or failed"; entry.detail = error.localizedDescription }
            do { try save(entry) } catch { entry.status = "Journal error — inspect outcome"; entry.detail += "\n" + error.localizedDescription }
            outcomes.append(entry); progress(entry)
        }
        return outcomes
    }
    public func restore(_ entry: HistoryEntry, exclusions: [String]) throws {
        guard lock.try() else { throw ReclaimError.refused("Cleanup is already running.") }; defer { lock.unlock() }
        guard entry.status == "Completed", entry.action == .trash, let source = entry.trashPath, let signature = entry.trashFingerprint else { throw ReclaimError.refused("This item does not have a recoverable Trash record.") }
        guard !exclusions.contains(where: { isWithin(entry.path, $0) }), !FileManager.default.fileExists(atPath: entry.path), try FileSystem.ancestors(entry.path) == entry.originalAncestors else { throw ReclaimError.refused("Original parent changed, target exists, or destination is excluded.") }
        let current = FileSystem.measure(source)
        guard current.complete, current.fingerprint == signature else { throw ReclaimError.refused("Trashed item changed or has already been removed.") }
        try trash.restore(source, to: entry.path)
        var restored = entry; restored.status = "Restored"; restored.detail = "Restored without overwriting any files."; try save(restored)
    }
}
