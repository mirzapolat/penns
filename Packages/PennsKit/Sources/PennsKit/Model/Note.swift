import Foundation
import SwiftData

/// A single note. Exactly one note per profile is active; the rest are archived.
@Model
public final class Note {
    public var id: UUID = UUID()
    /// Plain text. Checklist lines use "- [ ] " / "- [x] " prefixes.
    public var text: String = ""
    public var createdAt: Date = Date.distantPast
    public var updatedAt: Date = Date.distantPast
    /// `nil` while the note is active or before it was ever archived.
    public var archivedAt: Date?
    /// When a lifespan is set, the moment the note archives itself.
    public var expiresAt: Date?
    /// Raw value of `Lifespan`.
    public var lifespanRaw: String = "untilDone"
    /// Last time the user answered "Keep" to the still-relevant prompt.
    public var staleDismissedAt: Date?
    public var isActive: Bool = false
    public var profile: Profile?

    public init(text: String = "", profile: Profile? = nil, isActive: Bool = false, now: Date = .now) {
        self.id = UUID()
        self.text = text
        self.createdAt = now
        self.updatedAt = now
        self.isActive = isActive
        self.profile = profile
    }
}

public extension Note {
    /// True when the note holds nothing but whitespace.
    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var lifespan: Lifespan {
        Lifespan(rawValue: lifespanRaw) ?? .untilDone
    }

    /// First non-empty line, with any checklist marker removed.
    var firstLine: String {
        let line = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let stripped = Checklist.stripMarker(line)
        return Markdown.heading(of: stripped)?.text ?? stripped
    }
}
