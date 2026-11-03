#if os(iOS)
import AppIntents
import Foundation
import PennsKit

/// Shows the note as a Live Activity: full width on the Lock Screen and in the
/// Dynamic Island. Also the Control Center / Action Button control.
struct GoLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Go Live"
    static let description = IntentDescription("Shows your note on the Lock Screen and in the Dynamic Island.")

    @Parameter(title: "Profile", description: "Leave empty for the profile currently shown.")
    var profile: ProfileEntity?

    init() {}

    func perform() async throws -> some IntentResult {
        try await LiveNote.start(profileID: profile?.id)
        return .result()
    }
}

struct EndLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Live Activity"
    static let description = IntentDescription("Takes your note off the Lock Screen.")

    @Parameter(title: "Profile", description: "Leave empty to end every Penns Live Activity.")
    var profile: ProfileEntity?

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveNote.end(profileID: profile?.id)
        return .result()
    }
}

/// A checklist circle in the Live Activity. Runs in the app so the activity
/// updates right away.
struct LiveToggleItemIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Checklist Item"
    static let isDiscoverable = false

    @Parameter(title: "Item")
    var itemID: String

    @Parameter(title: "Profile")
    var profileID: String

    init() {}

    init(itemID: String, profileID: UUID) {
        self.itemID = itemID
        self.profileID = profileID.uuidString
    }

    func perform() async throws -> some IntentResult {
        let id = itemID
        let entity = UUID(uuidString: profileID).map { ProfileEntity(id: $0, name: "") }
        try IntentStore.mutate { store in
            _ = store.toggleChecklistItem(id, in: IntentStore.resolve(entity, in: store))
        }
        await LiveNote.refreshAll()
        return .result()
    }
}

/// The Archive pill in the Live Activity: archives the note and ends the activity.
struct LiveArchiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Archive Live Note"
    static let isDiscoverable = false

    @Parameter(title: "Profile")
    var profileID: String

    init() {}

    init(profileID: UUID) {
        self.profileID = profileID.uuidString
    }

    func perform() async throws -> some IntentResult {
        let entity = UUID(uuidString: profileID).map { ProfileEntity(id: $0, name: "") }
        try IntentStore.mutate { store in
            _ = store.archive(store.activeNote(in: IntentStore.resolve(entity, in: store)))
        }
        await LiveNote.refreshAll()
        return .result()
    }
}
#endif
