import Foundation

public enum Category: String, Codable, CaseIterable, Identifiable {
    case caches = "Caches", logs = "Logs", downloads = "Downloads", trash = "Trash"
    case developer = "Developer", worktrees = "Worktrees", applications = "Applications"
    case backups = "Device backups", largeFiles = "Large files", containers = "Containers", virtualDisks = "Virtual disks"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .caches: return "archivebox"; case .logs: return "doc.text"; case .downloads: return "arrow.down.circle"
        case .trash: return "trash"; case .developer: return "hammer"; case .worktrees: return "point.3.connected.trianglepath.dotted"
        case .applications: return "app.dashed"; case .backups: return "iphone"; case .largeFiles: return "doc.zipper"
        case .containers: return "shippingbox"; case .virtualDisks: return "externaldrive"
        }
    }
}
public enum CleanupAction: String, Codable {
    case trash, worktree, dockerVolume, dockerContainer, dockerImage, permanentlyDelete, reportOnly
    public var label: String {
        switch self {
        case .trash: return "Move to Trash"; case .worktree: return "Remove worktree permanently; preserve branch and safety ref"
        case .dockerVolume: return "Delete Docker volume permanently"; case .dockerContainer: return "Remove stopped container permanently"
        case .dockerImage: return "Remove Docker image"; case .permanentlyDelete: return "Delete from Trash permanently"
        case .reportOnly: return "Inventory only"
        }
    }
    public var irreversible: Bool { self != .trash && self != .reportOnly }
}
public struct Fingerprint: Codable, Equatable {
    public var identity: String
    public var digest: String
    public var ancestors: [String]
}
public struct Measurement: Codable, Equatable {
    public var logical: Int64 = 0
    public var allocated: Int64 = 0
    public var files: Int = 0
    public var complete: Bool = true
    public var fingerprint: Fingerprint?
    public var warning: String?
    public var latestModified: Date?
    public init() {}
}
public struct Finding: Identifiable, Codable, Hashable {
    public var id: String { category.rawValue + ":" + path }
    public var path: String
    public var name: String
    public var category: Category
    public var detail: String
    public var measurement: Measurement
    public var modified: Date?
    public var action: CleanupAction
    public var blockedReason: String?
    public var git: Worktree?
    public var docker: DockerTarget?
    public var selectable: Bool { blockedReason == nil && action != .reportOnly && measurement.complete }
    public var impact: ImpactAssessment { ImpactAssessment.classify(self) }
    /// Worktree age is based on observed content and Git activity, never commit author dates.
    public var ageReference: Date? {
        guard category == .worktrees else { return modified }
        guard measurement.complete, let latest = measurement.latestModified else { return nil }
        return max(latest, git?.metadataModified ?? latest)
    }
    public func olderThan(days: Int, now: Date = Date()) -> Bool {
        days == 0 || (ageReference.map { now.timeIntervalSince($0) >= Double(days) * 86_400 } ?? false)
    }
    /// Normalize older cached scans too: the strongest same-path protection wins.
    public static func coalesced(_ findings: [Finding]) -> [Finding] {
        var result: [Finding] = [], indices: [String: Int] = [:]
        for f in findings {
            if let index = indices[f.path] {
                let prior = result[index]
                if prior.action != .reportOnly && (f.action == .reportOnly || (prior.selectable && !f.selectable)) { result[index] = f }
            } else { indices[f.path] = result.count; result.append(f) }
        }
        return result
    }
    public init(path: String, name: String? = nil, category: Category, detail: String, measurement: Measurement = Measurement(), modified: Date? = nil, action: CleanupAction = .trash, blockedReason: String? = nil, git: Worktree? = nil, docker: DockerTarget? = nil) {
        self.path = path; self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.category = category; self.detail = detail; self.measurement = measurement; self.modified = modified
        self.action = action; self.blockedReason = blockedReason; self.git = git; self.docker = docker
    }
    public static func == (lhs: Finding, rhs: Finding) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
public struct Worktree: Codable {
    public var path: String
    public var commonDirectory: String
    public var head: String
    public var branch: String?
    public var main: Bool
    public var bare: Bool
    public var locked: String?
    public var prunable: String?
    public var blockers: [String] = []
    public var status: String = ""
    public var ownerHint: String = "Git"
    public var upstream: String?
    public var reachability: String = "Local references only; remote-tracking refs may be stale."
    public var metadataModified: Date?
    public var ignoredExamples: [String]?
    public var canRemove: Bool { blockers.isEmpty && !main && !bare }
}
public struct DockerTarget: Codable, Equatable {
    public var executable: String
    public var context: String
    public var endpoint: String
    public var objectID: String
    public var signature: String
}
public struct VolumeInfo: Identifiable, Codable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var total: Int64
    public var free: Int64
    public var local: Bool
    public var removable: Bool
    public var readOnly: Bool
}
public struct ScanResult: Codable {
    public var id = UUID()
    public var date = Date()
    public var findings: [Finding] = []
    public var roots: [String] = []
    public var issues: [String] = []
    public var volumes: [VolumeInfo] = []
    public var complete = true
    public init() {}
}
public struct Settings: Codable {
    public var roots: [String] = []
    public var exclusions: [String] = []
    public var toolOverrides: [String: String] = [:]
    public var scheduledScans = false
    public var lowSpaceNotifications = false
    public var largeFileThreshold: Int64 = 500_000_000
    public init() {}
}
public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}
public enum ReclaimError: LocalizedError {
    case refused(String)
    public var errorDescription: String? { switch self { case .refused(let s): return s } }
}
public func bytes(_ count: Int64) -> String { count == 0 ? "0 B" : ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
public func isWithin(_ path: String, _ root: String) -> Bool {
    let p = URL(fileURLWithPath: path).standardized.path
    let r = URL(fileURLWithPath: root).standardized.path
    return p == r || p.hasPrefix(r == "/" ? "/" : r + "/")
}
