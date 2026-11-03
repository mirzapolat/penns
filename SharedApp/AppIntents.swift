import AppIntents
import Foundation
import PennsKit
import WidgetKit

extension Notification.Name {
    static let pennsShowNote = Notification.Name("PennsShowNote")
}

/// Handoff between the Mac and the iPhone: the activity just opens the note;
/// the text itself arrives through iCloud sync.
enum Handoff {
    static let activityType = "com.mirzapolat.penns.note"
}

/// Opens the note (the menu bar panel on the Mac). App-only.
struct OpenNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Note"
    #if os(macOS)
    static let description = IntentDescription("Opens your Penns note in the menu bar.")
    #else
    static let description = IntentDescription("Opens your Penns note, ready to write.")
    #endif
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
        #if os(iOS)
        AppShortcut(
            intent: GoLiveIntent(),
            phrases: ["Put my \(.applicationName) note on the Lock Screen", "\(.applicationName) go live"],
            shortTitle: "Go Live",
            systemImageName: "rectangle.inset.topleft.filled"
        )
        AppShortcut(
            intent: EndLiveIntent(),
            phrases: ["End \(.applicationName) Live Activity"],
            shortTitle: "End Live Activity",
            systemImageName: "rectangle.slash"
        )
        #endif
        #if os(macOS)
        AppShortcut(
            intent: OpenNoteIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Note",
            systemImageName: "menubar.rectangle"
        )
        #else
        AppShortcut(
            intent: OpenNoteIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Note",
            systemImageName: "note.text"
        )
        #endif
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
