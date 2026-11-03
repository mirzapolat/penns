import Foundation
import SwiftData

/// What's needed to bring back a deleted note.
public struct DeletedNote: Sendable {
    public let text: String
    public let createdAt: Date
    public let lifespanRaw: String
    public let expiresAt: Date?
    public let profileID: UUID?
}

/// The only place that mutates notes. Enforces the invariant that every
/// profile has exactly one active note. Callers decide when to `save()`.
public final class NoteStore {
    public let context: ModelContext
    private let calendar: Calendar
    private let clock: () -> Date

    public init(context: ModelContext, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.calendar = calendar
        self.clock = now
    }

    public var now: Date { clock() }

    // MARK: Reading

    public func defaultProfile() -> Profile {
        let descriptor = FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.sortIndex)])
        if let profile = (try? context.fetch(descriptor))?.first {
            return profile
        }
        let profile = Profile()
        context.insert(profile)
        return profile
    }

    public func profiles() -> [Profile] {
        let descriptor = FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.sortIndex)])
        let profiles = (try? context.fetch(descriptor)) ?? []
        return profiles.isEmpty ? [defaultProfile()] : profiles
    }

    public func profile(id: UUID) -> Profile? {
        profiles().first { $0.id == id }
    }

    /// The profile to show: the preferred one (Focus filter or user choice) if it
    /// still exists, otherwise the first.
    public func currentProfile(preferredID: UUID?) -> Profile {
        if let preferredID, let profile = profile(id: preferredID) {
            return profile
        }
        return defaultProfile()
    }

    @discardableResult
    public func createProfile(name: String, colorHex: String? = nil) -> Profile {
        let existing = profiles()
        let color = colorHex ?? ProfileColors.all[existing.count % ProfileColors.all.count]
        let profile = Profile(name: name, sortIndex: (existing.map(\.sortIndex).max() ?? -1) + 1, colorHex: color)
        context.insert(profile)
        return profile
    }

    /// Deletes a profile and its notes. The last profile can't be deleted.
    @discardableResult
    public func deleteProfile(_ profile: Profile) -> Bool {
        guard profiles().count > 1 else { return false }
        for note in notes(in: profile) {
            context.delete(note)
        }
        context.delete(profile)
        return true
    }

    /// Turns the morning fresh start on or off. Enabling it after today's reset
    /// time counts today as done, so the current note isn't archived right away.
    public func setMorningReset(enabled: Bool, minutes: Int, for profile: Profile) {
        profile.morningResetEnabled = enabled
        profile.morningResetMinutes = min(max(minutes, 0), 24 * 60 - 1)
        let moment = Lifecycle.resetMoment(on: now, minutes: profile.morningResetMinutes, calendar: calendar)
        if enabled, now >= moment {
            profile.lastResetDay = Lifecycle.dayKey(now, calendar: calendar)
        }
    }

    /// Next moment the profile's note will be cleared by a lifespan or the morning reset.
    public func nextClearing(for profile: Profile) -> Date? {
        let note = activeNote(in: profile)
        guard !note.isBlank else { return nil }
        var candidates: [Date] = []
        if let expiresAt = note.expiresAt { candidates.append(expiresAt) }
        if profile.morningResetEnabled {
            candidates.append(Lifecycle.nextResetMoment(after: now, minutes: profile.morningResetMinutes, calendar: calendar))
        }
        return candidates.filter { $0 > now }.min()
    }

    /// The active note of `profile`, created if missing. Repairs duplicates.
    public func activeNote(in profile: Profile? = nil) -> Note {
        let profile = profile ?? defaultProfile()
        repair(profile)
        if let note = notes(in: profile).first(where: \.isActive) {
            return note
        }
        return makeBlank(in: profile)
    }

    /// Archived notes, newest first.
    public func archivedNotes(in profile: Profile? = nil) -> [Note] {
        let profile = profile ?? defaultProfile()
        return notes(in: profile)
            .filter { !$0.isActive && $0.archivedAt != nil }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    public func isStale(_ note: Note) -> Bool {
        Lifecycle.isStale(note, now: now)
    }

    // MARK: Editing

    /// Edits that clear at least this many characters at once leave a copy in the archive.
    public static let clearSafetyThreshold = 20

    /// Updates the text. If one edit wipes a substantial note (select-all + delete,
    /// a run of undos, a bug), the previous text is kept in the archive so it can
    /// be restored. Deleting character by character doesn't trigger this.
    @discardableResult
    public func setText(_ text: String, of note: Note) -> Note? {
        guard note.text != text else { return nil }
        let previous = note.text
        note.text = text
        note.updatedAt = now

        let removed = previous.count - text.count
        guard note.isActive,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              removed >= Self.clearSafetyThreshold else { return nil }
        let copy = Note(text: previous, profile: nil, isActive: false, now: now)
        copy.createdAt = note.createdAt
        copy.archivedAt = now
        context.insert(copy)
        copy.profile = note.profile ?? defaultProfile()
        return copy
    }

    /// Expires the note at an exact moment; `nil` means "until done".
    public func setExpiry(_ date: Date?, of note: Note) {
        guard let date else {
            setLifespan(.untilDone, of: note)
            return
        }
        note.lifespanRaw = Lifespan.custom.rawValue
        note.expiresAt = date
    }

    public func setLifespan(_ lifespan: Lifespan, of note: Note) {
        guard lifespan != .custom else { return }
        note.lifespanRaw = lifespan.rawValue
        note.expiresAt = lifespan.expiry(from: now, calendar: calendar)
    }

    public func dismissStale(_ note: Note) {
        note.staleDismissedAt = now
    }

    /// Adds `line` as a new last line of the active note.
    @discardableResult
    public func append(_ line: String, in profile: Profile? = nil) -> Note {
        let note = activeNote(in: profile)
        let trimmed = line.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return note }
        if note.text.isEmpty {
            setText(trimmed, of: note)
        } else {
            let separator = note.text.hasSuffix("\n") ? "" : "\n"
            setText(note.text + separator + trimmed, of: note)
        }
        return note
    }

    /// Archives the current note (if it has content) and starts a new one with `text`.
    @discardableResult
    public func replaceActive(with text: String, lifespan: Lifespan = .untilDone, in profile: Profile? = nil) -> Note {
        let current = activeNote(in: profile)
        let target = current.isBlank ? current : archive(current)
        setText(text, of: target)
        setLifespan(lifespan, of: target)
        return target
    }

    @discardableResult
    public func toggleChecklistItem(_ itemID: String, in profile: Profile? = nil) -> Bool {
        let note = activeNote(in: profile)
        guard let toggled = Checklist.toggle(itemID, in: note.text) else { return false }
        setText(toggled, of: note)
        return true
    }

    // MARK: Lifecycle

    /// Archives `note` and returns the new blank active note.
    /// A blank note is left as is.
    @discardableResult
    public func archive(_ note: Note) -> Note {
        let profile = note.profile ?? defaultProfile()
        guard note.isActive else { return activeNote(in: profile) }
        guard !note.isBlank else { return note }
        retire(note)
        profile.clearedCount += 1
        return makeBlank(in: profile)
    }

    /// Deletes `note` and returns a snapshot for undo and the new blank active note.
    public func delete(_ note: Note) -> (snapshot: DeletedNote, active: Note) {
        let profile = note.profile ?? defaultProfile()
        let snapshot = DeletedNote(
            text: note.text,
            createdAt: note.createdAt,
            lifespanRaw: note.lifespanRaw,
            expiresAt: note.expiresAt,
            profileID: profile.id
        )
        let wasActive = note.isActive
        context.delete(note)
        profile.clearedCount += 1
        let active = wasActive ? makeBlank(in: profile) : activeNote(in: profile)
        return (snapshot, active)
    }

    /// Brings a deleted note back as the active note.
    @discardableResult
    public func undoDelete(_ snapshot: DeletedNote) -> Note {
        let profile = snapshot.profileID.flatMap { profile(id: $0) } ?? defaultProfile()
        let current = activeNote(in: profile)
        if current.isBlank {
            context.delete(current)
        } else {
            retire(current)
        }
        let note = Note(text: snapshot.text, profile: profile, isActive: true, now: now)
        note.createdAt = snapshot.createdAt
        note.lifespanRaw = snapshot.lifespanRaw
        note.expiresAt = snapshot.expiresAt
        context.insert(note)
        note.profile = profile
        profile.clearedCount = max(0, profile.clearedCount - 1)
        return note
    }

    /// Makes an archived note active again. The current note is archived if it
    /// has content, otherwise discarded. `isUndo` reverts the cleared counter.
    @discardableResult
    public func restore(_ archived: Note, isUndo: Bool = false) -> Note {
        let profile = archived.profile ?? defaultProfile()
        for current in notes(in: profile) where current.isActive && current.id != archived.id {
            if current.isBlank {
                context.delete(current)
            } else {
                retire(current)
                profile.clearedCount += 1
            }
        }
        archived.isActive = true
        archived.archivedAt = nil
        archived.staleDismissedAt = now
        if let expiresAt = archived.expiresAt, expiresAt <= now {
            archived.expiresAt = nil
            archived.lifespanRaw = Lifespan.untilDone.rawValue
        }
        if isUndo {
            profile.clearedCount = max(0, profile.clearedCount - 1)
        }
        return archived
    }

    public func deleteArchived(_ note: Note) {
        guard !note.isActive else { return }
        context.delete(note)
    }

    /// Applies lifespans and morning resets. Returns every note that was archived.
    @discardableResult
    public func applyDueTransitions() -> [Note] {
        applyExpiries() + applyMorningResets()
    }

    /// Archives notes edited before today's reset time, once per day per profile.
    @discardableResult
    public func applyMorningResets() -> [Note] {
        var archived: [Note] = []
        for profile in profiles() where profile.morningResetEnabled {
            let moment = Lifecycle.resetMoment(on: now, minutes: profile.morningResetMinutes, calendar: calendar)
            let today = Lifecycle.dayKey(now, calendar: calendar)
            guard now >= moment, profile.lastResetDay != today else { continue }
            profile.lastResetDay = today
            let note = activeNote(in: profile)
            if !note.isBlank, note.updatedAt < moment {
                archive(note)
                archived.append(note)
            }
        }
        return archived
    }

    /// Archives active notes whose lifespan ran out. Returns the archived notes.
    @discardableResult
    public func applyExpiries() -> [Note] {
        let moment = now
        let due = activeNotes().filter { note in
            guard let expiresAt = note.expiresAt else { return false }
            return expiresAt <= moment
        }
        var expired: [Note] = []
        for note in due {
            if note.isBlank {
                note.expiresAt = nil
                note.lifespanRaw = Lifespan.untilDone.rawValue
            } else {
                archive(note)
                expired.append(note)
            }
        }
        return expired
    }

    /// Fixes profiles that ended up with several active notes (e.g. after sync):
    /// the most recently edited stays active, others are archived (blank ones deleted).
    @discardableResult
    public func repair(_ profile: Profile) -> Bool {
        let active = notes(in: profile)
            .filter(\.isActive)
            .sorted { $0.updatedAt > $1.updatedAt }
        guard active.count > 1 else { return false }
        for note in active.dropFirst() {
            if note.isBlank {
                context.delete(note)
            } else {
                retire(note)
            }
        }
        return true
    }

    public func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    // MARK: Private

    private func allNotes() -> [Note] {
        (try? context.fetch(FetchDescriptor<Note>())) ?? []
    }

    private func activeNotes() -> [Note] {
        (try? context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.isActive }))) ?? []
    }

    private func notes(in profile: Profile) -> [Note] {
        let id = profile.id
        return allNotes().filter { $0.profile?.id == id && !$0.isDeleted }
    }

    private func makeBlank(in profile: Profile) -> Note {
        let note = Note(profile: nil, isActive: true, now: now)
        context.insert(note)
        note.profile = profile
        return note
    }

    private func retire(_ note: Note) {
        note.isActive = false
        note.archivedAt = now
    }
}
