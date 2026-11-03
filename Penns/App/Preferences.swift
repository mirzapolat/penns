import Foundation
import KeyboardShortcuts

enum Prefs {
    static let titleMode = "menuBarTitleMode"
    static let showInDock = "showInDock"
    static let menuBarIcon = "menuBarIcon"
    static let didShowWelcome = "didShowWelcome"
}

/// Icons to choose from for the menu bar item (SF Symbols).
enum MenuBarIcon {
    static let all = [
        "note.text", "square.and.pencil", "pencil", "pencil.line",
        "text.alignleft", "list.bullet", "checklist", "doc.text",
        "quote.bubble", "lightbulb", "star", "heart",
        "bookmark", "pin", "flag", "leaf",
        "sun.max", "moon", "sparkles", "circle.fill",
    ]

    static var current: String {
        let name = UserDefaults.standard.string(forKey: Prefs.menuBarIcon) ?? ""
        return all.contains(name) ? name : all[0]
    }
}

enum MenuBarTitleMode: String, CaseIterable, Identifiable {
    case icon
    case firstLine
    case textOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: "Icon only"
        case .firstLine: "Icon and first line"
        case .textOnly: "First line only"
        }
    }

    static var current: MenuBarTitleMode {
        MenuBarTitleMode(rawValue: UserDefaults.standard.string(forKey: Prefs.titleMode) ?? "") ?? .icon
    }
}

extension KeyboardShortcuts.Name {
    static let toggleNote = Self("toggleNote", default: .init(.n, modifiers: [.command, .option]))
}
