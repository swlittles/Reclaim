import Foundation
import Darwin

public struct TrashLocation: Identifiable {
    public var id: String { path }
    public let path: String
    public var status: String
}
public struct TrashInventory {
    public var date = Date()
    public var locations: [TrashLocation] = []
    public var findings: [Finding] = []
    public var issues: [String] = []
    public var complete = true
    public init() {}
    public var allocated: Int64 { findings.reduce(0) { $0 + $1.measurement.allocated } }
    public var isEmpty: Bool { complete && findings.isEmpty }
    public func plan(selected: Set<String> = [], emptyAll: Bool = false, exclusions: [String]) throws -> CleanupPlan {
        if emptyAll {
            guard complete, !findings.isEmpty, findings.allSatisfy({ finding in finding.selectable && !exclusions.contains(where: { isWithin(finding.path, $0) || isWithin($0, finding.path) }) }) else {
                throw ReclaimError.refused("Refresh Trash and resolve protected, excluded, or inaccessible items before emptying all of it.")
            }
        }
        let targets = emptyAll ? findings : findings.filter { selected.contains($0.id) }
        guard !targets.contains(where: { finding in exclusions.contains { isWithin(finding.path, $0) || isWithin($0, finding.path) } }) else { throw ReclaimError.refused("A selected Trash item or its descendant is excluded.") }
        guard targets.allSatisfy({ $0.category == .trash && $0.action == .permanentlyDelete }) else { throw ReclaimError.refused("Trash review contains an unsupported action.") }
        return try CleanupPlan(findings: targets, exclusions: exclusions)
    }
}

/// Uses only this user's conventional Trash roots. Custom scan folders never grant deletion scope.
public final class TrashService {
    public let home: String
    private let volumes: () -> [String]
    public init(home: String = FileManager.default.homeDirectoryForCurrentUser.path, volumes: @escaping () -> [String] = { StorageScanner.volumes().filter { $0.local && $0.path != "/" }.map(\.path) }) {
        self.home = FileSystem.normalized(home); self.volumes = volumes
    }
    public var roots: [String] {
        Array(Set([home + "/.Trash"] + volumes().filter { $0.hasPrefix("/") && $0 != "/" }.map { FileSystem.normalized($0) + "/.Trashes/\(getuid())" })).sorted()
    }
    public func validateTarget(_ path: String, exclusions: [String] = []) throws {
        let target = FileSystem.normalized(path)
        guard roots.contains(URL(fileURLWithPath: target).deletingLastPathComponent().path) else {
            throw ReclaimError.refused("Permanent removal is limited to reviewed top-level items in your current home or mounted-volume Trash.")
        }
        guard !exclusions.contains(where: { isWithin(target, $0) || isWithin($0, target) }) else { throw ReclaimError.refused("A Trash item or its descendant is excluded.") }
    }
    public func scan(exclusions: [String], token: CancellationToken, activity: ActivitySnapshot? = nil, progress: (ScanProgress) -> Void = { _ in }) -> TrashInventory {
        var result = TrashInventory(), paths: [String] = []
        let fm = FileManager.default, deadline = Date().addingTimeInterval(180)
        progress(ScanProgress("Finding Trash locations"))
        for root in roots {
            if token.isCancelled { break }
            if exclusions.contains(where: { isWithin(root, $0) }) {
                result.locations.append(TrashLocation(path: root, status: "Excluded")); result.issues.append("Excluded Trash location: " + root); result.complete = false; continue
            }
            // ENOENT only means "no Trash" when its home or mounted volume still exists.
            let base = root == home + "/.Trash" ? home : URL(fileURLWithPath: root).deletingLastPathComponent().deletingLastPathComponent().path
            guard let baseInfo = try? FileSystem.info(base), FileSystem.directory(baseInfo), !FileSystem.symlink(baseInfo), !FileSystem.cloudOnly(baseInfo), (base == home || volumes().map(FileSystem.normalized).contains(base)) else {
                result.locations.append(TrashLocation(path: root, status: "Home or volume unavailable")); result.issues.append("Trash home or volume is unavailable: " + base); result.complete = false; continue
            }
            var info = stat()
            if lstat(root, &info) != 0 {
                if errno == ENOENT { result.locations.append(TrashLocation(path: root, status: "Not present")) }
                else { result.locations.append(TrashLocation(path: root, status: "Access unavailable")); result.issues.append("Cannot inspect \(root): \(String(cString: strerror(errno)))"); result.complete = false }
                continue
            }
            do {
                guard FileSystem.directory(info), !FileSystem.symlink(info), !FileSystem.cloudOnly(info), info.st_uid == getuid() else { throw ReclaimError.refused("Trash root is linked, unavailable, or owned by another user.") }
                _ = try FileSystem.ancestors(root + "/.reclaim-root-check")
                let children = try fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
                let remaining = max(0, 20_000 - paths.count)
                paths += children.prefix(remaining).map(\.path)
                if children.count > remaining { result.issues.append("Trash item limit reached at " + root); result.complete = false }
                result.locations.append(TrashLocation(path: root, status: "\(children.count) items"))
            } catch { result.locations.append(TrashLocation(path: root, status: "Access unavailable")); result.issues.append("\(root): \(error.localizedDescription)"); result.complete = false }
        }
        progress(ScanProgress("Checking running processes"))
        let activity = activity ?? (paths.isEmpty || token.isCancelled ? ActivitySnapshot(paths: []) : ActivitySnapshot.capture())
        for (index, path) in paths.enumerated() {
            if token.isCancelled { break }
            if Date() > deadline { result.issues.append("Trash scan time limit reached. Results are partial; refresh to retry."); result.complete = false; break }
            progress(ScanProgress("Measuring Trash", completed: Double(index), total: Double(paths.count), path: path))
            if token.isCancelled { break }
            let measurement = FileSystem.measure(path, token: token, progress: { count in
                progress(ScanProgress("Measuring Trash", completed: Double(index), total: Double(paths.count), path: path, filesInspected: count))
            })
            let excluded = exclusions.contains { isWithin(path, $0) || isWithin($0, path) }
            var reason = excluded ? "Excluded item or descendant. Update exclusions in Settings before deleting it." : measurement.warning ?? activity.blocker(for: path)
            do { try PathGuard(home: home).validate(path, allowedRoots: [path], exclusions: exclusions) } catch { reason = reason ?? error.localizedDescription }
            let date = (try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date
            result.findings.append(Finding(path: path, category: .trash, detail: "Already in Trash. Permanent deletion cannot be undone by Reclaim. Space recovered can differ from the allocation estimate.", measurement: measurement, modified: date, action: .permanentlyDelete, blockedReason: reason))
            if !measurement.complete { result.complete = false }
            if !token.isCancelled { progress(ScanProgress("Measuring Trash", completed: Double(index + 1), total: Double(paths.count), path: path)) }
        }
        if token.isCancelled { result.complete = false; result.issues.append("Trash scan cancelled. Results are partial.") }
        result.findings.sort { $0.measurement.allocated > $1.measurement.allocated }
        return result
    }
}
