// Adapted from Bustelo's MIT-licensed Sparkle integration, © Stephen Little.
import AppKit
import Sparkle
import ReclaimCore

final class UpdateService: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    var changed: (() -> Void)?
    var isCleaning: (() -> Bool)?
    private(set) var availableVersion: String?
    private var deferredInstall: (() -> Void)?
    private var controller: SPUStandardUpdaterController?
    var enabled: Bool { !AppIdentity.development && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil }
    func start() {
        guard enabled, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }
    var automatic: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue; changed?() }
    }
    var canCheck: Bool { controller?.updater.canCheckForUpdates == true && isCleaning?() != true }
    var title: String { availableVersion.map { "Update to Reclaim \($0)…" } ?? "Check for Updates…" }
    func check() { guard canCheck else { return }; NSApp.activate(ignoringOtherApps: true); controller?.checkForUpdates(nil) }
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) { availableVersion = update.displayVersionString; changed?() }
    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil; changed?() }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if isCleaning?() == true { throw ReclaimError.refused("Finish cleanup before updating Reclaim.") }
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isCleaning?() == true else { return false }; deferredInstall = installHandler; return true
    }
    func resumeDeferredInstall() { guard isCleaning?() != true else { return }; let block = deferredInstall; deferredInstall = nil; block?() }
}
