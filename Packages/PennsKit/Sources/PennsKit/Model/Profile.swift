import Foundation
import SwiftData

/// A context with its own active note, e.g. Work or Home.
@Model
public final class Profile {
    public var id: UUID = UUID()
    public var name: String = "Default"
    public var colorHex: String = "#8E8E93"
    public var sortIndex: Int = 0
    /// Number of notes archived or deleted — shown as "N notes cleared".
    public var clearedCount: Int = 0
    /// Morning fresh start: archive yesterday's note at `morningResetMinutes`.
    public var morningResetEnabled: Bool = false
    /// Minutes after local midnight (420 = 07:00).
    public var morningResetMinutes: Int = 420
    /// "2026-11-03" of the last reset, so devices never reset twice.
    public var lastResetDay: String?
    @Relationship(deleteRule: .cascade, inverse: \Note.profile)
    public var notes: [Note]? = []

    public init(id: UUID = UUID(), name: String = "Default", sortIndex: Int = 0, colorHex: String = ProfileColors.all[0]) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.colorHex = colorHex
    }
}

public extension Profile {
    /// Every device creates its first profile with this id, so when iCloud
    /// brings two of them together they're recognised as the same profile.
    static let defaultID = UUID(uuidString: "5E1F0D3A-7C2B-4E6A-9B1D-000000000001")!
}
