import Foundation

/// What the Apple Watch shows: every profile's note, as sent by the iPhone.
/// The iPhone's store stays the only source of truth; the watch keeps this
/// snapshot (also for its complications) and sends `WatchCommand`s back.
public struct WatchSnapshot: Codable, Equatable, Sendable {
    public struct Page: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        public var colorHex: String
        public var text: String
        public var expiresAt: Date?

        public init(id: UUID, name: String, colorHex: String, text: String, expiresAt: Date?) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.text = text
            self.expiresAt = expiresAt
        }

        public var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        public var lines: [Checklist.Line] { Checklist.parse(text.trimmingCharacters(in: .newlines)) }
        public var firstLine: String { Note.firstLine(of: text) }
        public var allChecked: Bool { Checklist.allChecked(text) }
        public var progress: (done: Int, total: Int) {
            let items = Checklist.items(in: text)
            return (items.filter(\.isChecked).count, items.count)
        }
    }

    public var pages: [Page]
    /// The profile shown on the iPhone (Focus filter or user choice).
    public var currentID: UUID?
    public var updatedAt: Date

    public init(pages: [Page], currentID: UUID?, updatedAt: Date) {
        self.pages = pages
        self.currentID = currentID
        self.updatedAt = updatedAt
    }

    public var current: Page? { pages.first { $0.id == currentID } ?? pages.first }

    public func page(_ id: UUID) -> Page? { pages.first { $0.id == id } }

    /// Every profile's active note, read from the store.
    public static func make(from store: NoteStore, currentID: UUID?) -> WatchSnapshot {
        let pages = store.profiles().map { profile in
            let note = store.activeNote(in: profile)
            return Page(id: profile.id, name: profile.name, colorHex: profile.colorHex, text: note.text, expiresAt: note.expiresAt)
        }
        let current = store.currentProfile(preferredID: currentID).id
        return WatchSnapshot(pages: pages, currentID: current, updatedAt: store.now)
    }

    /// The watch shows a command's result right away, before the iPhone
    /// confirms it; the iPhone's next snapshot then replaces this one.
    public func applying(_ command: WatchCommand) -> WatchSnapshot {
        var result = self
        guard let index = result.pages.firstIndex(where: { $0.id == command.profileID }) else { return self }
        var page = result.pages[index]
        switch command {
        case .toggle(let itemID, _):
            if let toggled = Checklist.toggle(itemID, in: page.text) { page.text = toggled }
        case .append(let text, _):
            let line = text.trimmingCharacters(in: .newlines)
            guard !line.isEmpty else { return self }
            page.text = page.text.isEmpty ? line : page.text + (page.text.hasSuffix("\n") ? "" : "\n") + line
        case .replace(let text, _):
            page.text = text
            page.expiresAt = nil
        case .archive:
            page.text = ""
            page.expiresAt = nil
        }
        result.pages[index] = page
        return result
    }

    // MARK: Transport and storage

    public static let messageKey = "snapshot"
    public static let defaultsKey = "watchSnapshot"

    public var message: [String: Any] {
        [Self.messageKey: (try? JSONEncoder().encode(self)) ?? Data()]
    }

    public init?(message: [String: Any]) {
        guard let data = message[Self.messageKey] as? Data,
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return nil }
        self = snapshot
    }

    public static func load(from defaults: UserDefaults) -> WatchSnapshot? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}

/// Something done on the watch, carried out by the iPhone on its store.
public enum WatchCommand: Codable, Equatable, Sendable {
    case toggle(itemID: String, profileID: UUID)
    /// Dictated or typed: a new last line.
    case append(text: String, profileID: UUID)
    /// Dictated or typed: archive the note and start a new one with this text.
    case replace(text: String, profileID: UUID)
    case archive(profileID: UUID)

    public var profileID: UUID {
        switch self {
        case .toggle(_, let id), .append(_, let id), .replace(_, let id), .archive(let id): id
        }
    }

    public static let messageKey = "command"

    public var message: [String: Any] {
        [Self.messageKey: (try? JSONEncoder().encode(self)) ?? Data()]
    }

    public init?(message: [String: Any]) {
        guard let data = message[Self.messageKey] as? Data,
              let command = try? JSONDecoder().decode(WatchCommand.self, from: data) else { return nil }
        self = command
    }

    /// Carries the command out. The caller saves. Returns false if the
    /// profile no longer exists.
    @discardableResult
    public func apply(to store: NoteStore) -> Bool {
        guard let profile = store.profile(id: profileID) else { return false }
        switch self {
        case .toggle(let itemID, _):
            store.toggleChecklistItem(itemID, in: profile)
        case .append(let text, _):
            store.append(text, in: profile)
        case .replace(let text, _):
            store.replaceActive(with: text, in: profile)
        case .archive:
            store.archive(store.activeNote(in: profile))
        }
        return true
    }
}
