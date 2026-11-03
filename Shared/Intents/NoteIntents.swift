import AppIntents
import Foundation
import PennsKit
import SwiftData
import WidgetKit

/// Runs one store mutation with a fresh context, saves, and tells the app and
/// widgets. Used by every intent, in the app and in the widget extension.
enum IntentStore {
    static func mutate<T>(_ body: (NoteStore) throws -> T) throws -> T {
        let store = NoteStore(context: ModelContext(SharedContainer.shared))
        store.applyDueTransitions()
        let result = try body(store)
        try store.save()
        ChangeSignal.post()
        WidgetCenter.shared.reloadAllTimelines()
        return result
    }

    /// The given profile, or the one currently shown (Focus filter or user choice).
    static func resolve(_ entity: ProfileEntity?, in store: NoteStore) -> Profile {
        if let id = entity?.id, let profile = store.profile(id: id) {
            return profile
        }
        return store.currentProfile(preferredID: ProfileSelection.preferredID)
    }
}

// MARK: Profile entity

struct ProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Profile"
    static let defaultQuery = ProfileQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ profile: Profile) {
        self.init(id: profile.id, name: profile.name)
    }
}

struct ProfileQuery: EntityQuery {
    init() {}

    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        Self.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProfileEntity] {
        Self.all()
    }

    private static func all() -> [ProfileEntity] {
        let store = NoteStore(context: ModelContext(SharedContainer.shared))
        let profiles = store.profiles().map(ProfileEntity.init)
        try? store.save()
        return profiles
    }
}

enum LifespanOption: String, AppEnum {
    case untilDone
    case today
    case thisWeek

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Lifespan"
    static let caseDisplayRepresentations: [LifespanOption: DisplayRepresentation] = [
        .untilDone: "Until done",
        .today: "Today",
        .thisWeek: "This week",
    ]

    var lifespan: Lifespan { Lifespan(rawValue: rawValue) ?? .untilDone }
}

// MARK: Intents

struct AppendToNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Note"
    static let description = IntentDescription("Adds a line to the end of your Penns note.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Profile", description: "Leave empty for the profile currently shown.")
    var profile: ProfileEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to note") {
            \.$profile
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let line = text
        let entity = profile
        let result = try IntentStore.mutate { store in
            store.append(line, in: IntentStore.resolve(entity, in: store)).text
        }
        return .result(value: result)
    }
}

struct SetNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Note"
    static let description = IntentDescription("Archives the current note and starts a new one with this text.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Lifespan", default: .untilDone)
    var lifespan: LifespanOption

    @Parameter(title: "Expires at", description: "An exact date and time. Overrides Lifespan.")
    var expiresAt: Date?

    @Parameter(title: "Profile", description: "Leave empty for the profile currently shown.")
    var profile: ProfileEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("New note \(\.$text)") {
            \.$lifespan
            \.$expiresAt
            \.$profile
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let text = text
        let lifespan = lifespan.lifespan
        let expiresAt = expiresAt
        let entity = profile
        let result = try IntentStore.mutate { store in
            let note = store.replaceActive(with: text, lifespan: lifespan, in: IntentStore.resolve(entity, in: store))
            if let expiresAt, expiresAt > store.now {
                store.setExpiry(expiresAt, of: note)
            }
            return note.text
        }
        return .result(value: result)
    }
}

struct GetNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Note"
    static let description = IntentDescription("Returns the text of your Penns note.")

    @Parameter(title: "Profile", description: "Leave empty for the profile currently shown.")
    var profile: ProfileEntity?

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let entity = profile
        let text = try IntentStore.mutate { store in
            store.activeNote(in: IntentStore.resolve(entity, in: store)).text
        }
        return .result(value: text)
    }
}

struct ArchiveNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Archive Note"
    static let description = IntentDescription("Archives your note and leaves a blank one.")

    @Parameter(title: "Profile", description: "Leave empty for the profile currently shown.")
    var profile: ProfileEntity?

    init() {}

    init(profile: ProfileEntity?) {
        self.profile = profile
    }

    func perform() async throws -> some IntentResult {
        let entity = profile
        try IntentStore.mutate { store in
            _ = store.archive(store.activeNote(in: IntentStore.resolve(entity, in: store)))
        }
        return .result()
    }
}

/// Ticks a checklist line. Used by widget buttons; hidden from Shortcuts.
struct ToggleChecklistItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Checklist Item"
    static let isDiscoverable = false

    @Parameter(title: "Item")
    var itemID: String

    @Parameter(title: "Profile")
    var profileID: String?

    init() {}

    init(itemID: String, profileID: UUID?) {
        self.itemID = itemID
        self.profileID = profileID?.uuidString
    }

    func perform() async throws -> some IntentResult {
        let id = itemID
        let entity = profileID.flatMap(UUID.init(uuidString:)).map { ProfileEntity(id: $0, name: "") }
        try IntentStore.mutate { store in
            _ = store.toggleChecklistItem(id, in: IntentStore.resolve(entity, in: store))
        }
        return .result()
    }
}
