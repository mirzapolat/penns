import AppKit
import PennsKit

/// Penns has no visible menu bar, but the main menu still routes key
/// equivalents — without it ⌘C, ⌘V and ⌘Z would not work in the editor.
enum MainMenu {
    @MainActor
    static func make(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "Penns")
        appMenu.addItem(withTitle: "About Penns", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: settingsAction, keyEquivalent: ",")
        settings.target = settingsTarget
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Penns", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Penns", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: edit)
        main.addItem(submenu: formatMenu())

        return main
    }

    /// Bold, italic, underline, strikethrough and lists, with the Apple Notes
    /// shortcuts. Sent to the editor through the responder chain.
    @MainActor
    static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        for (index, format) in TextFormat.all.enumerated() {
            if index == TextFormat.styles.count { menu.addItem(.separator()) }
            let shortcut = format.keyEquivalent
            let item = menu.addItem(
                withTitle: format.title,
                action: #selector(PennsTextView.pennsFormat(_:)),
                keyEquivalent: shortcut.key
            )
            item.keyEquivalentModifierMask = shortcut.shift ? [.command, .shift] : [.command]
            item.tag = index
            item.image = NSImage(systemSymbolName: format.systemImage, accessibilityDescription: nil)
        }
        return menu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
