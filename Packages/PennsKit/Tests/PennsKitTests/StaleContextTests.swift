import Foundation
import SwiftData
import Testing
@testable import PennsKit

/// Settings and the note panel use separate contexts. A write from a context
/// holding an old copy of a profile must not undo newer values.
@Suite struct StaleContextTests {
    /// Documents the hazard: saving an old copy overwrites newer values.
    @Test func staleProfileSaveOverwritesNewerValues() throws {
        let container = SharedContainer.make(inMemory: true)
        let panel = NoteStore(context: ModelContext(container))
        let profile = panel.defaultProfile()
        panel.setText("Buy milk", of: panel.activeNote(in: profile))
        try panel.save()

        // Settings loads the profile (clearedCount == 0)...
        let settings = NoteStore(context: ModelContext(container))
        let staleProfile = try #require(settings.profile(id: profile.id))
        #expect(staleProfile.clearedCount == 0)

        // ...the panel archives (clearedCount == 1)...
        panel.archive(panel.activeNote(in: profile))
        try panel.save()

        // ...then Settings saves a rename from its old copy.
        staleProfile.name = "Work"
        try settings.save()

        let fresh = try #require(NoteStore(context: ModelContext(container)).profile(id: profile.id))
        #expect(fresh.name == "Work")
        #expect(fresh.clearedCount == 0, "SwiftData wrote the stale clearedCount back")
    }

    @Test func updateProfileReadsFreshAndKeepsNewerValues() throws {
        let container = SharedContainer.make(inMemory: true)
        let panel = NoteStore(context: ModelContext(container))
        let profile = panel.defaultProfile()
        panel.setText("Buy milk", of: panel.activeNote(in: profile))
        try panel.save()

        // Settings only remembers the id, then the panel archives.
        let id = profile.id
        panel.archive(panel.activeNote(in: profile))
        try panel.save()

        let updated = try NoteStore.updateProfile(id: id, in: container) { profile, _ in profile.name = "Work" }
        #expect(updated)

        let fresh = try #require(NoteStore(context: ModelContext(container)).profile(id: id))
        #expect(fresh.name == "Work")
        #expect(fresh.clearedCount == 1)
    }

    @Test func updateProfileReportsMissingProfile() throws {
        let container = SharedContainer.make(inMemory: true)
        #expect(try NoteStore.updateProfile(id: UUID(), in: container) { _, _ in } == false)
    }
}

@Suite struct ConflictCopyTests {
    @Test func keepsTheOtherVersionInTheArchive() throws {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("Buy milk and eggs", of: note)
        try f.store.save()

        let copy = try #require(f.store.keepConflictCopy("Buy milk, eggs and bread", of: note))
        try f.store.save()
        #expect(copy.isActive == false)
        #expect(copy.profile?.id == note.profile?.id)
        #expect(f.store.archivedNotes(in: note.profile).map(\.text) == ["Buy milk, eggs and bread"])
        #expect(f.store.activeNote(in: note.profile).text == "Buy milk and eggs")
    }

    @Test func keepsNothingWhenBlankOrIdentical() {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("Same", of: note)
        #expect(f.store.keepConflictCopy("Same", of: note) == nil)
        #expect(f.store.keepConflictCopy("  \n", of: note) == nil)
        #expect(f.store.archivedNotes(in: note.profile).isEmpty)
    }
}
