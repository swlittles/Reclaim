import AppKit
import SwiftUI
import Combine
import ReclaimCore

@main struct ReclaimEntry {
    static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            let info: [String: Any] = ["name": AppIdentity.name, "development": AppIdentity.development, "dataDirectory": AppIdentity.dataURL.path, "feedPresent": Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil]
            if let d = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) { print(String(decoding: d, as: UTF8.self)) }; return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(delegate) {}
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var model: AppModel!
    var statusItem: NSStatusItem!
    var window: NSWindow?
    var subscription: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        model = AppModel(); model.showWindow = { [weak self] in self?.openWindow() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false; statusItem.menu = menu
        subscription = model.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.updateIcon() } }
        updateIcon()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--show-window") {
            UserDefaults.standard.set(true, forKey: "hasLaunched"); openWindow()
        }
        if CommandLine.arguments.contains("--smoke-test") {
            openWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { print("Reclaim native UI smoke test completed"); NSApp.terminate(nil) }
        }
    }
    func installMainMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title: AppIdentity.name)
        func item(_ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key); i.target = target; return i
        }
        appMenu.addItem(item("About Reclaim", #selector(about), target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(settings), ",", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit Reclaim", #selector(quit), "q", target: self))
        appItem.submenu = appMenu; bar.addItem(appItem)
        let fileItem = NSMenuItem(); let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("Open Reclaim…", #selector(openWindow), "o", target: self))
        fileMenu.addItem(item("Scan Storage…", #selector(scan), "r", target: self))
        fileMenu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))
        fileItem.submenu = fileMenu; bar.addItem(fileItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        editItem.submenu = editMenu; bar.addItem(editItem)
        NSApp.mainMenu = bar
    }
    func updateIcon() {
        let symbol = model.busy ? "arrow.triangle.2.circlepath" : (model.updates.availableVersion == nil ? "externaldrive.badge.checkmark" : "externaldrive.badge.plus")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: AppIdentity.name); image?.isTemplate = true
        statusItem.button?.image = image; statusItem.button?.toolTip = AppIdentity.name + " · " + model.status
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ selector: Selector, key: String = "", enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = self; item.isEnabled = enabled; menu.addItem(item)
        }
        let title = NSMenuItem(title: AppIdentity.name, action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        if let v = model.startupVolume { let item = NSMenuItem(title: "\(bytes(v.free)) available of \(bytes(v.total))", action: nil, keyEquivalent: ""); menu.addItem(item) }
        menu.addItem(.separator())
        add("Open Reclaim…", #selector(openWindow), key: "o")
        add("Scan Storage…", #selector(scan), enabled: !model.busy)
        add("Worktrees…", #selector(worktrees))
        add("Developer Storage…", #selector(developer))
        if model.busy { add(model.cleaning ? "Stop After Current Item" : "Cancel Scan", #selector(cancel)) }
        menu.addItem(.separator())
        add("Settings…", #selector(settings), key: ",")
        add(model.updates.enabled ? model.updates.title : "Updates disabled in Dev build", #selector(update), enabled: model.updates.canCheck)
        add("About Reclaim", #selector(about))
        menu.addItem(.separator()); add("Quit Reclaim", #selector(quit), key: "q")
    }
    @objc func openWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = AppIdentity.name; w.titlebarAppearsTransparent = true; w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 960, height: 640); w.contentView = NSHostingView(rootView: MainView(model: model)); w.center(); window = w
            w.setFrameAutosaveName(AppIdentity.name + "Main")
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openWindow(); return true }
    @objc func scan() { openWindow(); model.scan() }
    @objc func worktrees() { model.page = .worktrees; openWindow() }
    @objc func developer() { model.page = .developer; openWindow() }
    @objc func settings() { model.page = .settings; openWindow() }
    @objc func cancel() { model.token.cancel() }
    @objc func update() { model.updates.check() }
    @objc func about() { NSApp.activate(ignoringOtherApps: true); NSApp.orderFrontStandardAboutPanel(options: [.applicationName: AppIdentity.name, .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "Storage cleanup for developers.\nMIT licensed · Local-first · No analytics")]) }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.cleaning { model.token.cancel(); model.errorMessage = "Cleanup will stop after the current item. Quit again when it has finished."; openWindow(); return .terminateCancel }
        model.token.cancel(); return .terminateNow
    }
}
