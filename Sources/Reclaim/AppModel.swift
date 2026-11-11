import AppKit
import Combine
import ReclaimCore
import ServiceManagement
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    let store = LocalStore()
    lazy var executor = CleanupExecutor(store: store)
    let updates = UpdateService()
    @Published var settings: ReclaimCore.Settings { didSet { do { try store.write(settings, to: "settings.json") } catch { errorMessage = error.localizedDescription } } }
    @Published var result: ScanResult?
    @Published var selected = Set<String>()
    @Published var focused: String?
    @Published var page: Page = .overview
    @Published var search = ""
    @Published var selectionNote: String?
    @Published var busy = false
    @Published var cleaning = false
    @Published var status = "Ready to scan"
    @Published var errorMessage: String?
    @Published var review: ReviewState?
    @Published var history: [HistoryEntry] = []
    @Published var duplicates: [DuplicateGroup] = []
    @Published var hashComplete = false
    @Published var duplicateNotes: [String] = []
    @Published var volumes: [VolumeInfo] = StorageScanner.volumes()
    @Published var toolReport = ""
    @Published var volumeReport = ""
    var token = CancellationToken()
    var showWindow: (() -> Void)?
    var timer: Timer?
    var lastAutomaticScan = Date.distantPast
    var lastLowSpaceNotice = Date.distantPast
    init() {
        settings = LocalStore().read(ReclaimCore.Settings.self, from: "settings.json") ?? ReclaimCore.Settings()
        result = LocalStore().read(ScanResult.self, from: "scan.json")
        if var saved = result { saved.findings = Finding.coalesced(saved.findings); result = saved }
        history = CleanupExecutor().history()
        updates.isCleaning = { [weak self] in self?.cleaning ?? false }
        updates.changed = { [weak self] in self?.objectWillChange.send() }
        updates.start()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in self?.scheduledTick() } }
    }
    var findings: [Finding] { result?.findings ?? [] }
    var eligibleSelection: [Finding] { findings.filter { f in selected.contains(f.id) && f.selectable && !settings.exclusions.contains(where: { isWithin(f.path, $0) }) } }
    func selectAllVisible(_ visible: [Finding]) {
        guard !busy else { return }
        let result = SelectionPolicy.select(visible: visible, all: findings, selected: selected, exclusions: settings.exclusions, duplicatePaths: duplicates.map(\.paths))
        selected = result.selection
        selectionNote = "\(result.added) added · \(result.skipped) skipped (protected, excluded, overlapping, or a retained duplicate)."
    }
    func clearSelection() { selected.removeAll(); selectionNote = nil }
    var selectedBytes: Int64 { FileSystem.nonoverlapping(eligibleSelection.filter { $0.docker == nil }).reduce(0) { $0 + $1.measurement.allocated } }
    var inventoryBytes: Int64 { FileSystem.nonoverlapping(findings.filter { $0.docker == nil }).reduce(0) { $0 + $1.measurement.allocated } }
    var startupVolume: VolumeInfo? { volumes.first(where: { $0.path == "/" }) ?? volumes.first }
    var roots: [String] { Array(Set(settings.roots + StorageScanner.defaultRoots(home: FileManager.default.homeDirectoryForCurrentUser.path))).sorted() }
    func scan(deep: Bool = false, targeted: Bool = false) {
        if targeted && settings.roots.isEmpty { errorMessage = "Add at least one custom folder before a targeted scan."; return }
        guard !busy else { return }; busy = true; selected.removeAll(); selectionNote = nil; duplicates = []; hashComplete = false; token = CancellationToken()
        status = deep ? "Searching accessible home folders…" : "Scanning storage…"
        let t = token, config = settings
        let options = ScanOptions(roots: config.roots, exclusions: config.exclusions, deep: deep, includeSystemLocations: !targeted, largeFileThreshold: config.largeFileThreshold, toolOverrides: config.toolOverrides)
        var partial = ScanResult(); partial.complete = false; result = partial
        let owner = self
        Task.detached(priority: .utility) {
            let scanned = StorageScanner(token: t).scan(options) { path, items in
                Task { @MainActor in
                    if owner.busy && !owner.cleaning { owner.status = path; owner.result?.findings.append(contentsOf: items) }
                }
            }
            await MainActor.run {
                var scan = scanned
                owner.applyRunningAppProtection(&scan)
                owner.result = scan; owner.volumes = scan.volumes; owner.busy = false
                owner.status = scan.complete ? "Scan finished · \(scan.findings.count) items" : "Partial scan · \(scan.findings.count) items"
                do { try owner.store.write(scan, to: "scan.json") } catch { owner.errorMessage = error.localizedDescription }
                owner.notifyLowSpace()
            }
        }
    }
    func applyRunningAppProtection(_ scan: inout ScanResult) {
        let apps = NSWorkspace.shared.runningApplications
        for i in scan.findings.indices {
            let f = scan.findings[i]
            guard f.action == .trash else { continue }
            let running = apps.contains { app in
                if let url = app.bundleURL, isWithin(url.path, f.path) { return true }
                if let id = app.bundleIdentifier {
                    let name = URL(fileURLWithPath: f.path).lastPathComponent
                    if name == id || name.hasPrefix(id + ".") { return true }
                    let browserCaches = ["org.mozilla.firefox": ["Firefox"], "com.apple.Safari": ["com.apple.Safari"], "com.google.Chrome": ["Google", "Google Chrome"]]
                    if f.category == .caches, browserCaches[id]?.contains(name) == true { return true }
                }
                return false
            }
            if running { scan.findings[i].blockedReason = "The owning application is running. Quit it and rescan." }
            if isWithin(Bundle.main.bundlePath, f.path) { scan.findings[i].blockedReason = "Reclaim cannot remove its own running app or parent folder." }
        }
    }
    func makeReview() {
        do {
            let candidates = eligibleSelection
            for group in duplicates where group.paths.allSatisfy({ p in candidates.contains(where: { isWithin(p, $0.path) }) }) { throw ReclaimError.refused("Keep at least one file from every duplicate group.") }
            review = ReviewState(plan: try CleanupPlan(findings: candidates, exclusions: settings.exclusions))
        } catch { errorMessage = error.localizedDescription }
    }
    func execute(_ plan: CleanupPlan) {
        guard !busy else { return }
        // Recheck native running app ownership at the final UI boundary.
        var check = ScanResult(); check.findings = plan.findings; applyRunningAppProtection(&check)
        guard !check.findings.contains(where: { !$0.selectable }) else { errorMessage = "An owning application is now running; rescan before cleanup."; return }
        busy = true; cleaning = true; token = CancellationToken(); review = nil
        do { try store.write(settings, to: "settings.json") } catch { busy = false; cleaning = false; errorMessage = error.localizedDescription; return }
        let t = token, executor = executor, store = store, owner = self
        status = "Applying reviewed actions…"
        Task.detached(priority: .utility) {
            let entries = executor.execute(plan, exclusions: { store.read(ReclaimCore.Settings.self, from: "settings.json")?.exclusions ?? ["/"] }, token: t, progress: { entry in
                Task { @MainActor in owner.status = entry.path }
            })
            await MainActor.run {
                owner.history = executor.history(); owner.selected.removeAll(); owner.busy = false; owner.cleaning = false
                owner.status = "\(entries.filter { $0.status == "Completed" }.count) of \(plan.findings.count) actions completed"
                // Every related finding is stale after mutation; require a fresh scan for further cleanup.
                owner.result = nil; try? owner.store.write(ScanResult(), to: "scan.json")
                owner.volumes = StorageScanner.volumes(); owner.page = .history
                owner.updates.resumeDeferredInstall()
            }
        }
    }
    func restore(_ entry: HistoryEntry) {
        guard !busy else { return }; busy = true
        let executor = executor, exclusions = settings.exclusions, owner = self
        Task.detached {
            var message: String?
            do { try executor.restore(entry, exclusions: exclusions) } catch { message = error.localizedDescription }
            let finalMessage = message
            await MainActor.run { owner.busy = false; owner.history = executor.history(); owner.errorMessage = finalMessage }
        }
    }
    func findDuplicates() {
        guard !busy else { return }; busy = true; token = CancellationToken(); status = "Hashing duplicate candidates…"; hashComplete = false
        let roots = roots, exclusions = settings.exclusions, t = token, owner = self
        Task.detached(priority: .utility) {
            var notes: [String] = []
            let groups = DuplicateScanner.scan(roots: roots, exclusions: exclusions, token: t, progress: { path in Task { @MainActor in owner.status = path } }, issue: { notes.append($0) })
            let scanNotes = notes
            // Add content-verified duplicates to the same review pipeline.
            let extra = groups.flatMap { group in group.paths.map { path in Finding(path: path, category: .largeFiles, detail: "Content-identical duplicate · SHA-256 \(group.digest). Keep at least one copy.", measurement: FileSystem.measure(path, token: t)) } }
            await MainActor.run {
                owner.duplicates = groups; owner.duplicateNotes = scanNotes; owner.hashComplete = !t.isCancelled && scanNotes.isEmpty
                if owner.result == nil { owner.result = ScanResult() }
                for f in extra where !owner.findings.contains(where: { $0.id == f.id }) { owner.result?.findings.append(f) }
                owner.busy = false; owner.status = t.isCancelled || !scanNotes.isEmpty ? "Partial duplicate search · \(groups.count) groups" : "\(groups.count) duplicate groups found"
            }
        }
    }
    func clearScanCache() {
        guard !busy else { return }
        result = nil; selected.removeAll(); duplicates = []; duplicateNotes = []; hashComplete = false; focused = nil; status = "Ready to scan"
        let cache = store.directory.appendingPathComponent("scan.json")
        do { if FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.removeItem(at: cache) } } catch { errorMessage = error.localizedDescription }
    }
    func addRoot() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.message = "Choose project folders, custom worktree locations, or a mounted local volume."
        if panel.runModal() == .OK { settings.roots = Array(Set(settings.roots + panel.urls.map(\.path))).sorted() }
    }
    func exclude(_ path: String) { settings.exclusions = Array(Set(settings.exclusions + [path])).sorted(); selected = selected.filter { id in !findings.contains { $0.id == id && isWithin($0.path, path) } } }
    func reveal(_ path: String) { if !path.hasPrefix("docker://") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
    func checkTools() {
        guard !busy else { return }; busy = true; status = "Checking developer tools…"
        let overrides = settings.toolOverrides, owner = self
        Task.detached(priority: .utility) {
            var lines: [String] = []
            let runner = ProcessRunner()
            for (name, args) in [("git", ["--version"]), ("brew", ["cleanup", "--dry-run"]), ("xcrun", ["simctl", "list", "devices", "unavailable", "--json"])] {
                guard let exe = ToolLocator.find(name, overrides: overrides) else { lines.append("\(name): unavailable"); continue }
                do { let r = try runner.run(exe, args, cwd: "/", timeout: 30, token: nil); lines.append("\(name) (\(exe)) · exit \(r.code)\n" + String((r.output + r.error).prefix(8000))) } catch { lines.append("\(name): " + error.localizedDescription) }
            }
            let report = lines.joined(separator: "\n\n")
            await MainActor.run { owner.toolReport = report; owner.busy = false; owner.status = "Read-only tool checks complete" }
        }
    }
    func inspectAPFS() {
        guard !busy else { return }; busy = true
        let owner = self
        Task.detached(priority: .utility) {
            let report: String
            do { let r = try ProcessRunner().run("/usr/sbin/diskutil", ["apfs", "list"], cwd: "/", timeout: 20, token: nil); report = r.code == 0 ? r.output : r.error } catch { report = error.localizedDescription }
            await MainActor.run { owner.volumeReport = report; owner.busy = false }
        }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; objectWillChange.send() } catch { errorMessage = error.localizedDescription }
    }
    func scheduledTick() {
        volumes = StorageScanner.volumes()
        if settings.scheduledScans && !busy && Date().timeIntervalSince(lastAutomaticScan) > 86_400 { lastAutomaticScan = Date(); scan() }
        notifyLowSpace()
    }
    func enableNotifications(_ value: Bool) {
        settings.lowSpaceNotifications = value
        guard value else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func notifyLowSpace() {
        guard settings.lowSpaceNotifications, Date().timeIntervalSince(lastLowSpaceNotice) > 86_400, let v = startupVolume, v.free < 20_000_000_000 else { return }
        lastLowSpaceNotice = Date()
        let content = UNMutableNotificationContent(); content.title = "Storage is running low"; content.body = "\(bytes(v.free)) available. Open Reclaim to review storage. Nothing is removed automatically."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-space", content: content, trigger: nil))
    }
}
struct ReviewState: Identifiable { let id = UUID(); let plan: CleanupPlan }
enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview", cleanup = "Cleanup", worktrees = "Worktrees", developer = "Developer Storage", largeFiles = "Large Files", duplicates = "Duplicates", applications = "Applications", volumes = "Volumes", history = "History", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .overview: return "square.grid.2x2"; case .cleanup: return "sparkles"; case .worktrees: return "point.3.connected.trianglepath.dotted"; case .developer: return "hammer"; case .largeFiles: return "doc.zipper"; case .duplicates: return "doc.on.doc"; case .applications: return "app.dashed"; case .volumes: return "externaldrive"; case .history: return "clock.arrow.circlepath"; case .settings: return "gearshape" }
    }
}
