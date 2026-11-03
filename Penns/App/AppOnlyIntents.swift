import AppIntents
import Foundation
import PennsKit
import WidgetKit

/// Opens the note popover. App-only: extensions can't open the menu bar.
struct OpenNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Note"
    static let description = IntentDescription("Opens your Penns note in the menu bar.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .pennsShowNote, object: nil)
        return .result()
    }
}

struct PennsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AppendToNoteIntent(),
            phrases: ["Add to my \(.applicationName) note", "Add to \(.applicationName)"],
            shortTitle: "Add to Note",
            systemImageName: "text.append"
        )
        AppShortcut(
            intent: SetNoteIntent(),
            phrases: ["New \(.applicationName) note"],
            shortTitle: "New Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: GetNoteIntent(),
            phrases: ["Read my \(.applicationName) note", "What's my \(.applicationName) note"],
            shortTitle: "Get Note",
            systemImageName: "note.text"
        )
        AppShortcut(
            intent: ArchiveNoteIntent(),
            phrases: ["Archive my \(.applicationName) note"],
            shortTitle: "Archive Note",
            systemImageName: "archivebox"
        )
        AppShortcut(
            intent: OpenNoteIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Note",
            systemImageName: "menubar.rectangle"
        )
    }
}

/// System Settings → Focus → Focus Filters → Penns: show a profile while a Focus is on.
struct PennsFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Set Penns Profile"
    static let description: IntentDescription? = IntentDescription("Shows this profile's note while the Focus is on.")

    @Parameter(title: "Profile")
    var profile: ProfileEntity?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(profile?.name ?? "Current profile")")
    }

    init() {}

    func perform() async throws -> some IntentResult {
        // Called with the Focus's values when it turns on, and with defaults (nil) when it turns off.
        ProfileSelection.setFocus(profile?.id)
        ChangeSignal.post()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
