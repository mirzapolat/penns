import AppKit
import KeyboardShortcuts
import PennsKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: NoteViewModel!
    private var statusController: StatusItemController!
    private let settings = SettingsWindowController()
    private let welcome = WelcomeWindowController()
    private var tickTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockPreference()
        NSApp.mainMenu = MainMenu.make(settingsTarget: self, settingsAction: #selector(openSettings))
        if let failure = SharedContainer.loadFailure {
            showStoreFailure(failure)
            return
        }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        model = NoteViewModel(container: SharedContainer.shared)
        statusController = StatusItemController(model: model) { [weak self] in
            self?.openSettings()
        }

        KeyboardShortcuts.onKeyUp(for: .toggleNote) { [weak self] in
            self?.statusController.toggle()
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: .pennsShowNote, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusController.show() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDockPreference() }
        })

        if !UserDefaults.standard.bool(forKey: Prefs.didShowWelcome) {
            showWelcome()
        }

        // Lifespans expire on the minute; checking twice a minute is plenty.
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.tick() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.flush()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // penns://note (widget) opens the note; penns://archive opens the archive.
        guard statusController != nil else { return }
        statusController.show()
        if urls.contains(where: { $0.host == "archive" }) {
            model.showingArchive = true
        }
    }

    /// Handoff from the iPhone: open the note.
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == Handoff.activityType, statusController != nil else { return false }
        statusController.show()
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.show()
        return false
    }

    /// Services menu → "Add to Penns": appends the selected text in any app.
    @objc func addToNote(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, model != nil else {
            error.pointee = "No text to add." as NSString
            return
        }
        model.reload()
        model.appendFromService(text)
    }

    @objc func showWelcome() {
        statusController.close()
        welcome.show { [weak self] in
            UserDefaults.standard.set(true, forKey: Prefs.didShowWelcome)
            self?.statusController.show()
        }
    }

    @objc func openSettings() {
        statusController.close()
        settings.show()
    }

    /// The store didn't open. Typing into the empty stand-in would be lost,
    /// so Penns explains, offers the backups, and quits.
    private func showStoreFailure(_ details: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "Penns couldn't open your note")
        alert.informativeText = String(localized: "Your note is still on this Mac; nothing was changed or deleted. Quit Penns and open it again. If this keeps happening, copies of your note are in the Backups folder.") + "\n\n" + details
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Show Backups"))
        if alert.runModal() == .alertSecondButtonReturn {
            let store = SharedContainer.storeURL()
            let backups = StoreBackup.backups(forStoreAt: store)
            NSWorkspace.shared.activateFileViewerSelecting([backups.first ?? store])
        }
        NSApp.terminate(nil)
    }

    private func applyDockPreference() {
        let policy: NSApplication.ActivationPolicy = UserDefaults.standard.bool(forKey: Prefs.showInDock) ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}

