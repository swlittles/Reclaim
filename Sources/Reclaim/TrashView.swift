import SwiftUI
import AppKit
import ReclaimCore

struct TrashView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    @State private var focused: String?
    @State private var showCoverage = false
    private var items: [Finding] { model.trashInventory?.findings ?? [] }
    private func eligible(_ finding: Finding) -> Bool {
        finding.selectable && !model.settings.exclusions.contains { isWithin(finding.path, $0) || isWithin($0, finding.path) }
    }
    private var visible: [Finding] { items.filter { search.isEmpty || ($0.name + $0.path).localizedCaseInsensitiveContains(search) } }
    private var selectedItems: [Finding] { items.filter { model.trashSelected.contains($0.id) && eligible($0) } }
    private var canEmpty: Bool { model.trashInventory?.complete == true && !items.isEmpty && items.allSatisfy(eligible) && !model.trashNeedsRefresh }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "trash").font(.title).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.trashInventory == nil ? "Refresh to review Trash" : (model.trashInventory?.complete == true ? "\(items.count) items · ~\(bytes(model.trashInventory?.allocated ?? 0)) allocated" : "\(items.count) items found · scan incomplete")).font(.headline)
                    Text("Permanent deletion cannot be undone. Items added after this scan are left for the next refresh.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Empty Trash…", role: .destructive) { model.makeTrashReview(emptyAll: true) }.disabled(model.busy || !canEmpty)
                    .help("Review every scanned Trash item, regardless of search. Requires complete access and no protected or excluded items.")
            }.padding(18)
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Trash", text: $search).textFieldStyle(.plain)
                Menu {
                    Button("Select All Shown") { model.trashSelected.formUnion(visible.filter(eligible).map(\.id)) }.disabled(model.busy || visible.isEmpty)
                    Button("Clear Selection") { model.trashSelected.removeAll() }.disabled(model.busy || model.trashSelected.isEmpty)
                } label: { Label("Select", systemImage: "checklist") }.fixedSize()
                Text("\(selectedItems.count) selected").font(.caption).foregroundStyle(.secondary).fixedSize()
                Button("Delete Selected…") { model.makeTrashReview() }.disabled(model.busy || selectedItems.isEmpty || model.trashNeedsRefresh)
            }.padding(.horizontal, 14).frame(height: 46).background(Color(nsColor: .controlBackgroundColor))
            Divider()
            if let inventory = model.trashInventory {
                if !inventory.complete || items.contains(where: { !eligible($0) }) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(inventory.complete ? "Some items are protected or excluded" : "Trash access or scan coverage is incomplete").font(.callout.weight(.medium))
                            Text("You can review eligible items individually. Empty Trash is available only after every scanned location and item can be checked. See Locations for details.").font(.caption).foregroundStyle(.secondary)
                            if !inventory.complete {
                                Button("Full Disk Access Settings…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }.font(.caption)
                            }
                        }
                        Spacer()
                    }.padding(14)
                    Divider()
                }
                if inventory.isEmpty {
                    EmptyState(symbol: "trash", title: "Trash is empty", detail: "No items were found in the accessible home and mounted local-disk Trash locations.") {}
                } else if visible.isEmpty {
                    EmptyState(symbol: "trash", title: items.isEmpty ? "Trash could not be fully checked" : "No matching Trash items", detail: items.isEmpty ? "Refresh after resolving the location notes below. Reclaim has not deleted anything." : "Clear the search to see the other items. Empty Trash reviews all scanned items, including those hidden by search.") {}
                } else {
                    HStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(visible) { finding in
                                    FindingRow(model: model, finding: finding, selection: $model.trashSelected)
                                        .contentShape(Rectangle()).onTapGesture { focused = finding.id }
                                        .background(focused == finding.id ? Color.accentColor.opacity(0.08) : Color.clear)
                                    Divider().padding(.leading, 50)
                                }
                            }
                        }
                        if let finding = visible.first(where: { $0.id == focused }) { Divider(); InspectorView(model: model, finding: finding).frame(width: 280) }
                    }
                }
                Divider()
                HStack {
                    Button { showCoverage.toggle() } label: { Label("Locations (\(inventory.locations.count))", systemImage: "info.circle") }
                        .popover(isPresented: $showCoverage) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Trash locations").font(.headline)
                                    Text("Home Trash and the current user's Trash on mounted local disks. Other users' Trash, offline disks, and network servers are not emptied.").font(.caption).foregroundStyle(.secondary)
                                    ForEach(inventory.locations) { location in VStack(alignment: .leading, spacing: 4) { Text(location.path).font(.caption.monospaced()).textSelection(.enabled); Text(location.status).font(.caption).foregroundStyle(.secondary) } }
                                    ForEach(Array(inventory.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                                }.padding(18)
                            }.frame(width: 420, height: 300)
                        }
                    Spacer()
                    Text("Checked \(inventory.date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    Button("History") { model.page = .history }
                }.padding(12)
            } else {
                EmptyState(symbol: "trash", title: model.busy ? "Checking Trash…" : "Review your Trash", detail: "Refresh Trash to see items and their allocated size. Nothing is deleted until you review and confirm.", action: model.busy ? nil : "Refresh Trash") { model.refreshTrash() }.disabled(model.busy)
            }
        }.onAppear { if model.trashInventory == nil && !model.busy { model.refreshTrash() } }
    }
}
