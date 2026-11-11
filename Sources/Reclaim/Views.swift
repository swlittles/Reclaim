import SwiftUI
import AppKit
import ServiceManagement
import ReclaimCore

private let accent = Color(red: 0.22, green: 0.62, blue: 0.46)
struct MainView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.badge.checkmark").font(.title2).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reclaim").font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text(AppIdentity.development ? "DEVELOPMENT" : "STORAGE, SIMPLIFIED").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 16).padding(.top, 28)
                List(selection: $model.page) {
                    Section("STORAGE") {
                        ForEach(Array(Page.allCases.prefix(8))) { page in Label(page.rawValue, systemImage: page.symbol).tag(page).padding(.vertical, 4) }
                    }
                    Section {
                        ForEach(Array(Page.allCases.suffix(2))) { page in Label(page.rawValue, systemImage: page.symbol).tag(page).padding(.vertical, 4) }
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 7) {
                    Label("On this Mac. Under your control.", systemImage: "lock.shield").font(.caption2)
                    Text("Nothing is removed without review.").font(.caption2).foregroundStyle(.secondary)
                }.foregroundStyle(.secondary).padding(16)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                footer
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(accent)
        .sheet(item: $model.review) { review in ReviewView(model: model, plan: review.plan) }
        .alert("Reclaim", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") { model.errorMessage = nil } } message: { Text(model.errorMessage ?? "") }
    }
    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.page.rawValue).font(.system(size: 23, weight: .semibold, design: .rounded))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.busy { ProgressView().controlSize(.small); Button(model.cleaning ? "Stop after item" : "Cancel") { model.token.cancel() } }
            else {
                Button { model.addRoot() } label: { Label("Add Folder", systemImage: "folder.badge.plus") }
                Menu { Button("Quick Scan") { model.scan() }; Button("Deep Home Scan") { model.scan(deep: true) }; Button("Scan Added Folders Only") { model.scan(targeted: true) } } label: { Label("Scan Storage", systemImage: "arrow.clockwise") }.menuStyle(.borderlessButton).fixedSize().padding(8).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(.horizontal, 26).padding(.top, 26).padding(.bottom, 20)
    }
    var subtitle: String {
        switch model.page {
        case .worktrees: return "Every repository. Every linked location. Your work protected."
        case .developer: return "Build artifacts, package caches, containers, and virtual disks."
        case .duplicates: return "Compare content on demand. Keep the copies that matter."
        case .volumes: return "Mounted disks and shared capacity. Inventory only."
        case .history: return "A local record of every reviewed action."
        case .settings: return "Choose where Reclaim looks and what it leaves alone."
        default: return "See what is taking space. Decide what can go."
        }
    }
    @ViewBuilder var content: some View {
        switch model.page {
        case .overview: OverviewView(model: model)
        case .volumes: VolumesView(model: model)
        case .history: HistoryView(model: model)
        case .settings: SettingsView(model: model)
        case .duplicates: DuplicatesView(model: model)
        default: FindingsView(model: model)
        }
    }
    private var footer: some View {
        HStack(spacing: 12) {
            Circle().fill(model.busy ? Color.orange : accent).frame(width: 6, height: 6)
            Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if !model.selected.isEmpty {
                Text("\(model.eligibleSelection.count) selected · ~\(bytes(model.selectedBytes))").font(.caption.monospacedDigit())
                Button("Review Actions…") { model.makeReview() }.buttonStyle(.borderedProminent).disabled(model.busy || model.eligibleSelection.isEmpty)
            }
        }.padding(.horizontal, 22).padding(.vertical, 14)
    }
}
struct OverviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Room for your\nnext build.").font(.system(size: 38, weight: .semibold, design: .rounded)).tracking(-1)
                        Text("Find the clutter between projects.\nKeep the work that matters.").foregroundStyle(.secondary).lineSpacing(4)
                    }
                    Spacer()
                    Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 76, weight: .ultraLight)).foregroundStyle(accent).padding(22).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 26))
                }.padding(.vertical, 8)
                if let v = model.startupVolume {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Label(v.name, systemImage: "internaldrive").font(.headline); Spacer(); Text("\(bytes(v.free)) available").font(.headline.monospacedDigit()) }
                        ProgressView(value: Double(max(0, v.total - v.free)), total: Double(max(1, v.total))).tint(v.free < 20_000_000_000 ? .orange : accent)
                        HStack { Text("\(bytes(v.total - v.free)) used"); Spacer(); Text("\(bytes(v.total)) capacity") }.font(.caption).foregroundStyle(.secondary)
                    }.padding(20).card()
                }
                HStack(spacing: 14) {
                    MetricCard(title: "INVENTORIED", value: "~" + bytes(model.inventoryBytes), note: "Allocated size estimate", icon: "square.stack.3d.up")
                    MetricCard(title: "WORKTREES", value: String(model.findings.filter { $0.category == .worktrees && $0.git?.main != true }.count), note: "Across discovered repositories", icon: Page.worktrees.symbol)
                    MetricCard(title: "COVERAGE", value: model.result == nil ? "Not scanned" : (model.result?.complete == true ? "Finished" : "Partial"), note: "Accessible configured locations", icon: "viewfinder")
                }
                HStack { Text("Explore your storage").font(.headline); Spacer(); if let date = model.result?.date { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) } }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    explore("Worktrees", note: "Git-aware checks, across custom locations", symbol: Page.worktrees.symbol, page: .worktrees)
                    explore("Developer Storage", note: "Builds, dependencies, containers, VMs", symbol: "hammer", page: .developer)
                    explore("Cleanup", note: "Caches, logs, downloads, and backups", symbol: "sparkles", page: .cleanup)
                    explore("Large Files & Duplicates", note: "Review files and compare their content", symbol: "doc.on.doc", page: .largeFiles)
                }
                if let scan = model.result {
                    DisclosureGroup("Scan coverage · \(scan.roots.count) roots · \(scan.issues.count) notes") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(scan.roots, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                            ForEach(Array(scan.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }.padding(16).card()
                } else {
                    Label("Start with a scan. Add project folders or custom worktree locations for better coverage.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                }
                Text("Estimates account for overlapping folders and hard links. APFS clones, snapshots, and shared container layers can change the space actually recovered.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
    func explore(_ title: String, note: String, symbol: String, page: Page) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(accent).frame(width: 32)
                VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(note).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.padding(18).card()
        }.buttonStyle(.plain)
    }
}
struct MetricCard: View {
    var title: String; var value: String; var note: String; var icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(accent) }
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).card()
    }
}
struct FindingsView: View {
    @ObservedObject var model: AppModel
    @State private var largestFirst = true
    @State private var eligibility = 0
    @State private var ageDays = 0
    @State private var minBytes: Int64 = 0
    var visible: [Finding] {
        let items = model.findings.filter { f in
            let matches: Bool
            switch model.page {
            case .worktrees: matches = f.category == .worktrees
            case .developer: matches = [.developer, .containers, .virtualDisks].contains(f.category)
            case .largeFiles: matches = [.largeFiles, .downloads, .backups].contains(f.category)
            case .applications: matches = f.category == .applications
            default: matches = ![.worktrees, .containers, .virtualDisks, .applications].contains(f.category)
            }
            let eligible = eligibility == 0 || (eligibility == 1 ? f.selectable : !f.selectable)
            let age = ageDays == 0 || (f.modified.map { Date().timeIntervalSince($0) >= Double(ageDays) * 86400 } ?? false)
            return matches && eligible && age && f.measurement.allocated >= minBytes && (model.search.isEmpty || (f.path + f.detail + f.name).localizedCaseInsensitiveContains(model.search))
        }
        return items.sorted { largestFirst ? $0.measurement.allocated > $1.measurement.allocated : $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search paths, repositories, or tools", text: $model.search).textFieldStyle(.plain)
                Picker("Sort", selection: $largestFirst) { Text("Largest first").tag(true); Text("Path").tag(false) }.labelsHidden().frame(width: 125)
            }.padding(14).background(Color(nsColor: .controlBackgroundColor))
            HStack(spacing: 12) {
                Picker("Show", selection: $eligibility) { Text("All items").tag(0); Text("Eligible").tag(1); Text("Protected").tag(2) }.frame(width: 150)
                Picker("Age", selection: $ageDays) { Text("Any age").tag(0); Text("30+ days").tag(30); Text("90+ days").tag(90) }.frame(width: 150)
                Picker("Size", selection: $minBytes) { Text("Any size").tag(Int64(0)); Text("100 MB+").tag(Int64(100_000_000)); Text("1 GB+").tag(Int64(1_000_000_000)) }.frame(width: 145)
                Spacer()
                Text("\(visible.count) items").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            if model.page == .developer {
                HStack { Text("Shared stores, simulator devices, and VM images are inventory only.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Tool Checks…") { model.checkTools() }.disabled(model.busy) }.padding(12)
            }
            if visible.isEmpty { EmptyState(symbol: model.page.symbol, title: model.result == nil ? "Start with a storage scan" : "No matching items", detail: "Add folders for projects and worktrees outside the usual locations. Permission-limited and offline locations may not appear.", action: "Scan Storage") { model.scan() }.disabled(model.busy) }
            else {
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visible) { f in
                                FindingRow(model: model, finding: f).contentShape(Rectangle()).onTapGesture { model.focused = f.id }
                                    .background(model.focused == f.id ? accent.opacity(0.08) : Color.clear)
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                    if let f = visible.first(where: { $0.id == model.focused }) { Divider(); InspectorView(model: model, finding: f).frame(width: 280) }
                }
            }
            if !model.toolReport.isEmpty && model.page == .developer {
                DisclosureGroup("Read-only developer tool report") { ScrollView { Text(model.toolReport).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 180) }.padding(14)
            }
        }
    }
}
struct FindingRow: View {
    @ObservedObject var model: AppModel
    var finding: Finding
    var excluded: Bool { model.settings.exclusions.contains { isWithin(finding.path, $0) } }
    var body: some View {
        HStack(spacing: 12) {
            Toggle("Select \(finding.name)", isOn: Binding(get: { model.selected.contains(finding.id) }, set: { value in if value { model.selected.insert(finding.id) } else { model.selected.remove(finding.id) } })).labelsHidden().toggleStyle(.checkbox).disabled(!finding.selectable || model.busy || excluded)
            Image(systemName: finding.category.symbol).font(.title3).foregroundStyle(finding.selectable ? accent : .secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(finding.name).font(.system(size: 13, weight: .medium)).lineLimit(1); if finding.git?.main == true { pill("MAIN", color: .secondary) }; if excluded { pill("EXCLUDED", color: .orange) } }
                Text(finding.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(finding.blockedReason == nil ? finding.action.label : "Protected · " + (finding.blockedReason?.components(separatedBy: "\n").first ?? "")).font(.caption2).foregroundStyle(finding.blockedReason == nil ? Color.secondary : Color.orange).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(finding.docker == nil ? "~" + bytes(finding.measurement.allocated) : "Size shared").font(.system(size: 12, weight: .medium, design: .monospaced))
                Text(finding.category.rawValue).font(.caption2).foregroundStyle(.tertiary)
            }
        }.padding(.horizontal, 18).padding(.vertical, 14)
        .contextMenu { Button("Reveal in Finder") { model.reveal(finding.path) }.disabled(finding.docker != nil); Button("Exclude This Location") { model.exclude(finding.path) }.disabled(model.busy); Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(finding.path, forType: .string) } }
    }
}
struct InspectorView: View {
    @ObservedObject var model: AppModel
    var finding: Finding
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: finding.category.symbol).font(.largeTitle).foregroundStyle(accent)
                Text(finding.name).font(.headline).textSelection(.enabled)
                Text(finding.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                detail("LOCATION", finding.path)
                detail("ACTION", finding.action.label)
                if finding.docker == nil { detail("ALLOCATED / LOGICAL", "~\(bytes(finding.measurement.allocated)) / \(bytes(finding.measurement.logical))"); detail("FILES", String(finding.measurement.files)) }
                if let date = finding.modified { detail("MODIFIED", date.formatted(date: .abbreviated, time: .shortened)) }
                if let w = finding.git {
                    let artifacts = FileSystem.nonoverlapping(model.findings.filter { $0.category == .developer && $0.path != finding.path && isWithin($0.path, finding.path) }).reduce(Int64(0)) { $0 + $1.measurement.allocated }
                    detail("BUILD / DEPENDENCY ALLOCATION", "~" + bytes(artifacts))
                    detail("OTHER WORKTREE ALLOCATION", "~" + bytes(max(0, finding.measurement.allocated - artifacts)))
                    detail("COMMON GIT DIRECTORY", w.commonDirectory); detail("HEAD", w.head)
                    detail("BRANCH", w.branch ?? "Detached HEAD"); detail("UPSTREAM", w.upstream ?? "No upstream configured")
                }
                if let reason = finding.blockedReason { Label("Protected", systemImage: "lock.shield").foregroundStyle(.orange); Text(reason).font(.caption).textSelection(.enabled) }
                if finding.action.irreversible { Label("This action cannot be undone by Reclaim.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                Button("Reveal in Finder") { model.reveal(finding.path) }.disabled(finding.docker != nil)
                Button("Exclude This Location") { model.exclude(finding.path) }.disabled(model.busy)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    func detail(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary); Text(value).font(.caption.monospaced()).textSelection(.enabled) } }
}
struct ReviewView: View {
    @ObservedObject var model: AppModel
    let plan: CleanupPlan
    @State private var confirm = false
    var irreversible: Bool { plan.findings.contains { $0.action.irreversible } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Review \(plan.findings.count) actions", systemImage: "checklist").font(.title2.bold())
            Text("~\(bytes(plan.allocated)) of allocated storage selected. Moving files to Trash does not free space until Trash is emptied.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(plan.findings) { f in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(f.name).font(.headline)
                            Text(f.path).font(.caption.monospaced()).textSelection(.enabled)
                            Text(f.action.label).font(.caption).foregroundStyle(f.action.irreversible ? .orange : accent)
                            if f.action == .worktree { Text("Git removes this folder permanently. A new safety ref preserves HEAD; branches remain. Local files are not backed up.").font(.caption).foregroundStyle(.secondary) }
                            if f.action == .dockerVolume { Text("Volume data, including databases, is permanently lost. Unattached does not mean unused.").font(.caption).foregroundStyle(.orange) }
                        }
                        Divider()
                    }
                }
            }.frame(maxHeight: 330)
            if irreversible { Toggle("I understand the listed permanent removals have no app Undo.", isOn: $confirm).toggleStyle(.checkbox) }
            Text("Every target is checked again before its action. Changed, excluded, or unsafe items are skipped.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { model.review = nil }.keyboardShortcut(.cancelAction); Button("Apply Reviewed Actions") { model.execute(plan) }.buttonStyle(.borderedProminent).disabled(irreversible && !confirm) }
        }.padding(28).frame(width: 620)
    }
}
struct VolumesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("APFS volumes may share container capacity. Free space is not additive. Reclaim never erases disks or removes system snapshots.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                ForEach(model.volumes) { v in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Image(systemName: v.removable ? "externaldrive" : "internaldrive").font(.title2).foregroundStyle(accent); Text(v.name).font(.headline); Spacer(); Text("\(bytes(v.free)) available").font(.headline) }
                        ProgressView(value: Double(max(0, v.total - v.free)), total: Double(max(1, v.total)))
                        HStack { Text(v.path).font(.caption.monospaced()); Spacer(); Text(v.local ? "Local" : "Network"); if v.removable { Text("Removable") }; if v.readOnly { Text("Read-only") } }.font(.caption).foregroundStyle(.secondary)
                        Button("Reveal in Finder") { model.reveal(v.path) }
                    }.padding(20).card()
                }
                HStack {
                    Button("Add a Volume or Folder to Scan…") { model.addRoot() }.disabled(model.busy)
                    Button("Inspect APFS Layout…") { model.inspectAPFS() }.disabled(model.busy)
                }
                if !model.volumeReport.isEmpty { DisclosureGroup("APFS containers and volumes · read-only") { Text(model.volumeReport).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
                Text("Docker volumes and VM disk images appear under Developer Storage. Network and removable disks are scanned only when you add them.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
}
struct HistoryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if model.history.isEmpty { EmptyState(symbol: "clock.arrow.circlepath", title: "No cleanup actions yet", detail: "Reviewed actions and their outcomes will appear here. Reclaim never replays interrupted operations automatically.") {} }
        else {
            List(model.history) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(entry.status).font(.headline).foregroundStyle(entry.status == "Completed" || entry.status == "Restored" ? accent : .orange); Spacer(); Text(entry.date, style: .date).font(.caption).foregroundStyle(.secondary) }
                    Text(entry.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text(entry.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    if entry.status == "Completed", let path = entry.trashPath {
                        HStack { Button("Reveal in Trash") { model.reveal(path) }; Button("Restore…") { model.restore(entry) }.disabled(model.busy) }
                    }
                }.padding(.vertical, 12)
            }.listStyle(.inset)
        }
    }
}
struct DuplicatesView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Content hashing reads files in project and custom roots. It skips dependency caches, links, and cloud-only placeholders.").font(.callout).foregroundStyle(.secondary); Spacer(); Button("Find Duplicates") { model.findDuplicates() }.disabled(model.busy) }
            if !model.duplicateNotes.isEmpty { DisclosureGroup("Partial search · \(model.duplicateNotes.count) notes") { ForEach(Array(model.duplicateNotes.enumerated()), id: \.offset) { _, note in Text(note).font(.caption).foregroundStyle(.secondary) } } }
            if model.duplicates.isEmpty { EmptyState(symbol: "doc.on.doc", title: model.hashComplete ? "No duplicates found" : "Compare files when you need to", detail: "Files are grouped by size and verified with SHA-256. At least one copy in each group must stay.") {} }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.duplicates) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(group.paths.count) copies · \(bytes(group.size)) each").font(.headline)
                                ForEach(group.paths, id: \.self) { path in if let f = model.findings.first(where: { $0.path == path && $0.category == .largeFiles }) { FindingRow(model: model, finding: f) } }
                            }.padding(12).card()
                        }
                    }
                }
            }
        }.padding(24)
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("Scan locations") {
                Text("Common developer locations are included in Quick Scan. Add arbitrary repository/worktree parents or a mounted volume. Git metadata expands each discovered repository family across locations.").font(.callout).foregroundStyle(.secondary)
                ForEach(model.roots, id: \.self) { root in HStack { Text(root).font(.caption.monospaced()).textSelection(.enabled); Spacer(); if model.settings.roots.contains(root) { Button("Remove") { model.settings.roots.removeAll { $0 == root } } } } }
                Button("Add Folder…") { model.addRoot() }
            }
            Section("Exclusions") {
                Text("Excluded folders and their contents cannot be selected for cleanup.").font(.caption).foregroundStyle(.secondary)
                ForEach(model.settings.exclusions, id: \.self) { path in HStack { Text(path).font(.caption.monospaced()); Spacer(); Button("Remove") { model.settings.exclusions.removeAll { $0 == path } } } }
                Button("Exclude Folder…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
                    if panel.runModal() == .OK, let path = panel.url?.path { model.exclude(path) }
                }
            }
            Section("Automation") {
                Toggle("Open at Login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { model.setLogin($0) }))
                if SMAppService.mainApp.status == .requiresApproval { Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() } }
                Toggle("Scan once a day while Reclaim is running", isOn: $model.settings.scheduledScans)
                Toggle("Notify when startup disk has less than 20 GB available", isOn: Binding(get: { model.settings.lowSpaceNotifications }, set: { model.enableNotifications($0) }))
                Text("Scheduled scans are read-only. Cleanup always requires review.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Developer tools") {
                ForEach(["git", "docker", "brew", "xcrun"], id: \.self) { name in
                    TextField("\(name) executable", text: Binding(get: { model.settings.toolOverrides[name] ?? "" }, set: { if $0.isEmpty { model.settings.toolOverrides.removeValue(forKey: name) } else { model.settings.toolOverrides[name] = $0 } })).font(.caption.monospaced())
                }
                Text("Leave blank to use trusted system/Homebrew locations. Custom paths must be absolute executables.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                if model.updates.enabled {
                    Toggle("Check for updates automatically", isOn: Binding(get: { model.updates.automatic }, set: { model.updates.automatic = $0 }))
                    Button(model.updates.title) { model.updates.check() }.disabled(!model.updates.canCheck)
                    Text("Signed Sparkle updates from GitHub. You choose when to install.").font(.caption).foregroundStyle(.secondary)
                } else { Text("This Dev build never checks for updates. Rebuild from source. Release builds use a separate signed Sparkle feed.").foregroundStyle(.secondary) }
            }
            Section("Privacy & access") {
                Text("Scan metadata and history stay in \(AppIdentity.dataURL.path). No accounts or analytics. Full Disk Access can expand coverage; it is optional.").font(.caption).textSelection(.enabled)
                Button("Open Full Disk Access Settings…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
                Button("Clear scan cache") { model.clearScanCache() }
            }
        }.formStyle(.grouped).disabled(model.busy)
    }
}
struct EmptyState: View {
    var symbol: String; var title: String; var detail: String; var action: String? = nil; var perform: () -> Void
    var body: some View { VStack(spacing: 16) { Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(accent); Text(title).font(.title2.weight(.semibold)); Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430); if let action { Button(action, action: perform).buttonStyle(.borderedProminent) } }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity) }
}
private extension View { func card() -> some View { self.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.primary.opacity(0.06), lineWidth: 1)) } }
private func pill(_ text: String, color: Color) -> some View { Text(text).font(.system(size: 8, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule()).foregroundStyle(color) }
