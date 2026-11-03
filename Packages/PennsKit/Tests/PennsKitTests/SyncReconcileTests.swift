import Foundation
import SwiftData
import Testing
@testable import PennsKit

/// iCloud merges records from several devices without unique constraints, so
/// the store must stay correct when it sees duplicates: two copies of the
/// default profile, several active notes in one profile.
@Suite struct SyncReconcileTests {
    @Test func defaultProfileHasTheSameIDOnEveryDevice() {
        let first = Fixture().store.defaultProfile()
        let second = Fixture().store.defaultProfile()
        #expect(first.id == Profile.defaultID)
        #expect(second.id == first.id)
    }

    @Test func duplicateProfilesShowAsOne() throws {
        let f = Fixture()
        let mine = f.store.defaultProfile()
        let theirs = Profile()
        theirs.id = mine.id
        f.store.context.insert(theirs)
        try f.store.save()

        #expect(f.store.profiles().count == 1)
        #expect(f.store.profile(id: mine.id) != nil)
    }

    @Test func activeNoteWithTextWinsOverNewerBlankOne() throws {
        let f = Fixture()
        let profile = f.store.defaultProfile()
        let note = f.store.activeNote(in: profile)
        f.store.setText("Call the bakery", of: note)
        try f.store.save()

        // Another device (or a failed fetch) created a fresh blank note later.
        f.clock.advance(60)
        let blank = Note(profile: nil, isActive: true, now: f.clock.now)
        f.store.context.insert(blank)
        blank.profile = profile
        try f.store.save()

        let active = f.store.activeNote(in: profile)
        #expect(active.id == note.id)
        #expect(active.text == "Call the bakery")
        #expect(f.activeCount() == 1)
    }

    @Test func notesOfBothDuplicateProfilesStayVisible() throws {
        let f = Fixture()
        let mine = f.store.defaultProfile()
        let myNote = f.store.activeNote(in: mine)
        f.store.setText("Mine", of: myNote)

        let theirs = Profile()
        theirs.id = mine.id
        f.store.context.insert(theirs)
        f.clock.advance(60)
        let theirNote = Note(text: "Theirs", profile: nil, isActive: true, now: f.clock.now)
        f.store.context.insert(theirNote)
        theirNote.profile = theirs
        try f.store.save()

        let active = f.store.activeNote(in: mine)
        #expect(active.text == "Theirs")
        #expect(f.store.archivedNotes(in: mine).map(\.text) == ["Mine"])
        #expect(f.activeCount() == 1)
    }

    @Test func reconcileAlignsDuplicateProfiles() throws {
        let f = Fixture()
        let mine = f.store.defaultProfile()
        mine.clearedCount = 3
        mine.lastResetDay = "2026-11-02"
        let theirs = Profile()
        theirs.id = mine.id
        theirs.clearedCount = 5
        theirs.lastResetDay = "2026-11-03"
        f.store.context.insert(theirs)
        try f.store.save()

        f.store.reconcile()
        #expect(mine.clearedCount == 5 && theirs.clearedCount == 5)
        #expect(mine.lastResetDay == "2026-11-03" && theirs.lastResetDay == "2026-11-03")
        // Nothing is deleted: removing a copy would cascade to its notes.
        let all = try f.store.context.fetch(FetchDescriptor<Profile>())
        #expect(all.count == 2)
    }

    @Test func settingsChangesReachEveryCopy() throws {
        let f = Fixture()
        let mine = f.store.defaultProfile()
        let theirs = Profile()
        theirs.id = mine.id
        f.store.context.insert(theirs)
        try f.store.save()

        try NoteStore.updateProfile(id: mine.id, in: f.container) { profile, _ in
            profile.name = "Home"
        }
        let names = try ModelContext(f.container).fetch(FetchDescriptor<Profile>()).map(\.name)
        #expect(names == ["Home", "Home"])
    }

    @Test func deletingAProfileRemovesEveryCopyButKeepsOthers() throws {
        let f = Fixture()
        let home = f.store.defaultProfile()
        let work = f.store.createProfile(name: "Work")
        let copy = Profile(name: "Work")
        copy.id = work.id
        f.store.context.insert(copy)
        try f.store.save()

        #expect(f.store.deleteProfile(work))
        try f.store.save()
        let left = try f.store.context.fetch(FetchDescriptor<Profile>())
        #expect(left.map(\.id) == [home.id])
    }

    @Test func morningResetRunsOncePerProfileEvenWithCopies() throws {
        let f = Fixture()
        let mine = f.store.defaultProfile()
        f.store.setMorningReset(enabled: true, minutes: 0, for: mine)
        mine.lastResetDay = nil
        let theirs = Profile()
        theirs.id = mine.id
        theirs.morningResetEnabled = true
        theirs.morningResetMinutes = 0
        f.store.context.insert(theirs)
        let note = f.store.activeNote(in: mine)
        f.store.setText("Yesterday", of: note)
        note.updatedAt = f.clock.now.addingTimeInterval(-86_400)
        try f.store.save()

        #expect(f.store.applyMorningResets().count == 1)
        #expect(f.store.applyMorningResets().isEmpty)
        #expect(f.store.archivedNotes(in: mine).map(\.text) == ["Yesterday"])
    }
}
