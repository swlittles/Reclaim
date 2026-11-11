import Foundation

/// Expected consequence is independent from eligibility. These rules do not prove a file is unused.
public enum ImpactClass: String, CaseIterable, Identifiable {
    case cache = "Cache · lower risk"
    case diagnostics = "Logs & diagnostics"
    case rebuild = "Rebuild / reinstall needed"
    case application = "App functionality & settings"
    case personal = "Personal data"
    case repository = "Repository content"
    case managed = "Tool-managed storage"
    case unknown = "Unknown impact"
    public var id: String { rawValue }
}

public struct ImpactAssessment {
    public let classification: ImpactClass
    public let evidence: String
    public let consequence: String
    private init(_ classification: ImpactClass, _ evidence: String, _ consequence: String) {
        self.classification = classification; self.evidence = evidence; self.consequence = consequence
    }
    public static func classify(_ f: Finding) -> ImpactAssessment {
        let parts = URL(fileURLWithPath: f.path).standardized.pathComponents
        let leaf = parts.last ?? ""
        func underLibrary(_ name: String) -> Bool {
            parts.indices.contains { i in parts[i] == "Library" && i + 1 < parts.count && parts[i + 1] == name }
        }
        if f.git != nil || f.category == .worktrees {
            return Self(.repository, "Git worktree registration and local safety checks.", "Removing a linked worktree removes its local files permanently. Branches and a safety ref remain. Main repositories, local changes, ignored files and active work are protected; age never overrides them.")
        }
        // Provider-managed storage always wins over a generic cache or large-file label.
        if f.action == .reportOnly || f.docker != nil || [.virtualDisks, .containers].contains(f.category) {
            return Self(.managed, "Shared store, container, virtual disk, or inventory-only provider data.", "May contain databases, installed tools, or shared dependencies. Use the owning tool's maintenance controls. An unattached volume can still hold valuable data.")
        }
        if f.category == .backups {
            return Self(.personal, "Device backup inventory.", "May be the only backup of device photos, messages, settings, and application data. Deleting it removes that recovery option; old age does not establish that it is disposable.")
        }
        if parts.contains(where: { $0.hasSuffix(".app") || $0.hasSuffix(".framework") || $0.hasSuffix(".plugin") }) {
            return Self(.application, "Application bundle or installed runtime component in the path.", "Removal can stop the app or a dependent app from launching. Reinstall the app to restore its executable components; moving it to Trash is not a cache cleanup.")
        }
        if ["Application Support", "Containers", "Group Containers", "Preferences", "Saved Application State", "Keychains"].contains(where: underLibrary) {
            return Self(.application, "App support, sandbox, settings, saved state, or keychain location.", "May reset preferences, sign you out, remove offline content, or delete application databases. This data is not assumed to regenerate. An exact bundle identifier associates data with an app; it does not prove removal is safe.")
        }
        if underLibrary("Caches") {
            return Self(.cache, "Located inside Library/Caches, macOS's conventional user cache location.", "Usually recreated by the owning app. Quit the owner first; expect slower startup or downloads. Some apps keep offline or nonstandard data in caches, so this is lower risk, never a guarantee of no impact.")
        }
        if underLibrary("Logs") || f.category == .logs {
            return Self(.diagnostics, "Log or diagnostic storage location.", "Removes troubleshooting history. Apps generally create new logs; keep evidence needed for support or debugging.")
        }
        if f.category == .developer && (["node_modules", ".build", "target", ".venv", "venv"].contains(leaf) || parts.contains("DerivedData") || parts.contains("iOS DeviceSupport")) {
            return Self(.rebuild, "Scanner identified build output, a dependency environment, or developer support files.", "Projects, scripts, or local services using these files can stop working until rebuilt or reinstalled. Downloads and toolchains may be required. Locally edited or installed-only content may not be recoverable.")
        }
        if [.downloads, .backups, .trash].contains(f.category) || (f.category == .developer && parts.contains("Archives")) {
            return Self(.personal, "Download, device backup, Trash content, or retained build archive.", "May be the only copy. Age and duplicate contents do not prove a file is unwanted or that another app does not reference its exact path. Review before removal.")
        }
        return Self(.unknown, "No verified rule establishes the purpose of this file.", "A third-party app, script, or user workflow may reference this path. Size, age, and matching contents cannot establish that deletion is safe. Inspect the owner and contents first.")
    }
}

public struct BulkSelection {
    public var selection: Set<String>
    public var added: Int
    public var skipped: Int
}
public enum SelectionPolicy {
    /// Prefer specific children over parent folders, never select the last known duplicate,
    /// and respect exclusions even when they were added after a scan.
    public static func select(visible: [Finding], all: [Finding], selected: Set<String>, exclusions: [String], duplicatePaths: [[String]] = []) -> BulkSelection {
        var kept: [Finding] = []
        func append(_ f: Finding) -> Bool {
            guard f.selectable, !exclusions.contains(where: { isWithin(f.path, $0) }) else { return false }
            guard !kept.contains(where: { $0.id == f.id || ($0.docker == nil && f.docker == nil && (isWithin(f.path, $0.path) || isWithin($0.path, f.path))) }) else { return false }
            let proposed = kept + [f]
            guard !duplicatePaths.contains(where: { group in !group.isEmpty && group.allSatisfy { path in proposed.contains { $0.docker == nil && isWithin(path, $0.path) } } }) else { return false }
            kept.append(f); return true
        }
        func ordered(_ findings: [Finding]) -> [Finding] {
            findings.sorted { $0.path.count == $1.path.count ? $0.id < $1.id : $0.path.count > $1.path.count }
        }
        for f in ordered(all.filter { selected.contains($0.id) }) { _ = append(f) }
        var added = 0, skipped = 0
        for f in ordered(visible) where !kept.contains(where: { $0.id == f.id }) {
            if append(f) { added += 1 } else { skipped += 1 }
        }
        return BulkSelection(selection: Set(kept.map(\.id)), added: added, skipped: skipped)
    }
}
