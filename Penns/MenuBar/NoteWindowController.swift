import AppKit
import SwiftUI

/// A resizable Liquid Glass panel that drops down from the menu bar item and
/// behaves like a popover: clicking elsewhere or pressing Esc closes it.
@MainActor
final class NoteWindowController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 340, height: 430)
    static let minSize = NSSize(width: 260, height: 220)
    static let maxSize = NSSize(width: 760, height: 960)
    private static let sizeKey = "noteWindowSize"
    /// Gap between the menu bar and the arrow's tip.
    private static let menuBarGap: CGFloat = 2

    var onClose: (() -> Void)?
    private let panel: NotePanel
    private let geometry = PanelGeometry()
    private(set) var lastClosed = Date.distantPast
    private var outsideClickMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?

    var isVisible: Bool { panel.isVisible }
    var isKey: Bool { panel.isKeyWindow }

    init<Content: View>(rootView: Content) {
        panel = NotePanel(
            contentRect: NSRect(origin: .zero, size: Self.savedSize),
            // Non-activating: the panel takes key focus the instant it opens, so
            // the first click and keystroke land in the note.
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.minSize = Self.minSize
        panel.maxSize = Self.maxSize
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }

        let hosting = FirstClickHostingView(rootView: NotePanelRoot(geometry: geometry, content: rootView))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func show(below anchor: NSRect) {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 8
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: visible.maxY - Self.menuBarGap - size.height)
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        // Point the arrow at the menu bar item even when the panel is pushed
        // in from a screen edge.
        geometry.arrowX = anchor.midX - origin.x
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        startWatchingOutsideClicks()
    }

    func close() {
        guard panel.isVisible else { return }
        stopWatchingOutsideClicks()
        panel.orderOut(nil)
        lastClosed = Date()
        onClose?()
    }

    /// Clicks in other apps (or on the desktop) close the panel, like a popover.
    /// Losing key focus alone isn't reliable for a menu bar app.
    private func startWatchingOutsideClicks() {
        stopWatchingOutsideClicks()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func stopWatchingOutsideClicks() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
        resignActiveObserver = nil
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Wait a beat: if focus moved to our own popover (e.g. the date picker),
        // keep the panel open.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            if let key = NSApp.keyWindow, key === self.panel || self.isAttached(key) {
                return
            }
            self.close()
        }
    }

    private func isAttached(_ window: NSWindow) -> Bool {
        if self.panel.childWindows?.contains(window) == true { return true }
        var parent = window.parent
        while let current = parent {
            if current === self.panel { return true }
            parent = current.parent
        }
        return String(describing: type(of: window)).contains("Popover")
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        UserDefaults.standard.set(NSStringFromSize(panel.frame.size), forKey: Self.sizeKey)
        // Keep the panel hanging from the menu bar after resizing from the bottom.
        panel.invalidateShadow()
    }

    private static var savedSize: NSSize {
        guard let string = UserDefaults.standard.string(forKey: sizeKey) else { return defaultSize }
        let size = NSSizeFromString(string)
        guard size.width >= minSize.width, size.height >= minSize.height else { return defaultSize }
        return NSSize(width: min(size.width, maxSize.width), height: min(size.height, maxSize.height))
    }
}

/// Clicks act immediately instead of only focusing the panel first.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotePanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
