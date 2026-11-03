import AppKit
import PennsKit
import SwiftUI

/// The menu bar item: click for the note, hover to peek, right-click for a menu.
@MainActor
final class StatusItemController: NSResponder {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var noteWindow: NoteWindowController!
    private let peek = PeekPanel()
    private let model: NoteViewModel
    private let openSettings: () -> Void
    private var hoverTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?

    init(model: NoteViewModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
        configureButton()
        configureWindow()
        model.onNoteChange = { [weak self] in self?.refreshTitle() }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTitle() }
        }
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Popover

    func toggle() {
        if noteWindow.isVisible {
            close()
        } else if Date().timeIntervalSince(noteWindow.lastClosed) > 0.3 {
            // Clicking the menu bar item first closes the panel (it loses key);
            // don't reopen it on the same click.
            show()
        }
    }

    func show() {
        guard let button = statusItem.button, let window = button.window else { return }
        hoverTask?.cancel()
        peek.hide()
        model.prepareForDisplay()
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        noteWindow.show(below: anchor)
    }

    func close() {
        noteWindow.close()
    }

    // MARK: Hover peek

    override func mouseEntered(with event: NSEvent) {
        guard !noteWindow.isVisible, !model.note.isBlank else { return }
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.showPeek()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverTask?.cancel()
        peek.hide()
    }

    private func showPeek() {
        guard !noteWindow.isVisible, let button = statusItem.button, let window = button.window else { return }
        model.reload()
        guard !model.note.isBlank else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        peek.show(text: model.note.text, below: anchor)
    }

    // MARK: Title

    func refreshTitle() {
        guard let button = statusItem.button else { return }
        let title = model.menuBarTitle
        let icon = NSImage(systemSymbolName: MenuBarIcon.current, accessibilityDescription: "Penns")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: MenuBarIcon.currentSize, weight: .regular))
        icon?.isTemplate = true
        switch MenuBarTitleMode.current {
        case .icon:
            button.image = icon
            button.title = ""
        case .firstLine:
            button.image = icon
            button.title = title.isEmpty ? "" : " " + title
        case .textOnly:
            // Fall back to the icon while the note is empty so the item never vanishes.
            button.image = title.isEmpty ? icon : nil
            button.title = title
        }
        button.setAccessibilityLabel(title.isEmpty ? "Penns" : "Penns: \(title)")
    }

    // MARK: Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(buttonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    private func configureWindow() {
        let root = NoteScreen(
            model: model,
            openSettings: { [weak self] in self?.openSettings() },
            close: { [weak self] in self?.close() }
        )
        noteWindow = NoteWindowController(rootView: root)
        noteWindow.onClose = { [weak self] in
            self?.model.flush()
            self?.model.showingArchive = false
        }
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        hoverTask?.cancel()
        peek.hide()
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            toggle()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        close()
        model.reload()
        let menu = NSMenu()
        menu.addItem(item("Open Note", #selector(menuOpen)))
        let archive = item("Archive Note", #selector(menuArchive))
        archive.isEnabled = !model.note.isBlank
        menu.addItem(archive)
        if model.hasMultipleProfiles {
            menu.addItem(.separator())
            for (index, profile) in model.profiles.enumerated() {
                let entry = item(profile.name, #selector(menuSwitchProfile(_:)))
                entry.tag = index
                entry.state = profile.id == model.profile.id ? .on : .off
                menu.addItem(entry)
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(menuSettings)))
        menu.addItem(item("Quit Penns", #selector(menuQuit)))
        menu.autoenablesItems = false
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuOpen() { show() }
    @objc private func menuSwitchProfile(_ sender: NSMenuItem) { model.reload(); model.switchProfile(at: sender.tag) }
    @objc private func menuArchive() { model.reload(); model.archive() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
