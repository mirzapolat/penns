import Foundation
import SwiftData
import Testing
@testable import PennsKit

@Suite struct ProfileTests {
    @Test func profilesHaveIndependentActiveNotes() {
        let f = Fixture()
        let home = f.store.defaultProfile()
        let work = f.store.createProfile(name: "Work")
        f.store.setText("home", of: f.store.activeNote(in: home))
        f.store.setText("work", of: f.store.activeNote(in: work))

        #expect(f.store.activeNote(in: home).text == "home")
        #expect(f.store.activeNote(in: work).text == "work")
        #expect(f.store.profiles().map(\.name) == ["Default", "Work"])
        #expect(f.activeCount() == 2)
    }

    @Test func archiveCountsPerProfile() {
        let f = Fixture()
        let work = f.store.createProfile(name: "Work")
        let note = f.store.activeNote(in: work)
        f.store.setText("x", of: note)
        f.store.archive(note)
        #expect(work.clearedCount == 1)
        #expect(f.store.defaultProfile().clearedCount == 0)
        #expect(f.store.archivedNotes(in: work).count == 1)
        #expect(f.store.archivedNotes(in: f.store.defaultProfile()).isEmpty)
    }

    @Test func currentProfileFallsBackWhenPreferredIsGone() {
        let f = Fixture()
        let work = f.store.createProfile(name: "Work")
        #expect(f.store.currentProfile(preferredID: work.id).id == work.id)
        #expect(f.store.deleteProfile(work))
        #expect(f.store.currentProfile(preferredID: work.id).id == f.store.defaultProfile().id)
    }

    @Test func lastProfileCannotBeDeleted() {
        let f = Fixture()
        #expect(!f.store.deleteProfile(f.store.defaultProfile()))
    }

    @Test func undoDeleteReturnsNoteToItsProfile() {
        let f = Fixture()
        _ = f.store.defaultProfile()
        let work = f.store.createProfile(name: "Work")
        let note = f.store.activeNote(in: work)
        f.store.setText("work note", of: note)
        let (snapshot, _) = f.store.delete(note)
        let back = f.store.undoDelete(snapshot)
        #expect(back.profile?.id == work.id)
        #expect(f.store.activeNote(in: work).text == "work note")
    }
}

@Suite struct MorningResetTests {
    // 2027-01-15 08:00 UTC; reset at 07:00.
    static let eight = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func archivesYesterdaysNoteOncePerDay() {
        let f = Fixture(now: Self.eight.addingTimeInterval(-12 * 3600)) // previous evening 20:00
        let profile = f.store.defaultProfile()
        f.store.setMorningReset(enabled: true, minutes: 420, for: profile)
        let note = f.store.activeNote(in: profile)
        f.store.setText("yesterday", of: note)

        f.clock.now = Self.eight
        #expect(f.store.applyMorningResets().map(\.id) == [note.id])
        #expect(f.store.activeNote(in: profile).isBlank)

        f.store.setText("today", of: f.store.activeNote(in: profile))
        f.clock.advance(3600)
        #expect(f.store.applyMorningResets().isEmpty)
    }

    @Test func keepsNoteEditedAfterResetTime() {
        let f = Fixture(now: Self.eight.addingTimeInterval(-12 * 3600))
        let profile = f.store.defaultProfile()
        f.store.setMorningReset(enabled: true, minutes: 420, for: profile)
        f.clock.now = Self.eight.addingTimeInterval(-1800) // 07:30, edited after reset time
        f.store.setText("fresh", of: f.store.activeNote(in: profile))
        f.clock.now = Self.eight
        #expect(f.store.applyMorningResets().isEmpty)
        #expect(f.store.activeNote(in: profile).text == "fresh")
    }

    @Test func enablingLateInTheDayDoesNotArchiveImmediately() {
        let f = Fixture(now: Self.eight.addingTimeInterval(7 * 3600)) // 15:00
        let profile = f.store.defaultProfile()
        f.store.setText("keep me", of: f.store.activeNote(in: profile))
        f.store.setMorningReset(enabled: true, minutes: 420, for: profile)
        #expect(f.store.applyMorningResets().isEmpty)
    }

    @Test func nextResetMomentRollsOverToTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let next = Lifecycle.nextResetMoment(after: Self.eight, minutes: 420, calendar: calendar)
        #expect(next == Self.eight.addingTimeInterval(23 * 3600))
        #expect(Lifecycle.dayKey(Self.eight, calendar: calendar) == "2027-01-15")
    }

    @Test func nextClearingPicksEarliest() {
        let f = Fixture(now: Self.eight)
        let profile = f.store.defaultProfile()
        let note = f.store.activeNote(in: profile)
        f.store.setText("x", of: note)
        f.store.setLifespan(.today, of: note) // midnight
        f.store.setMorningReset(enabled: true, minutes: 420, for: profile) // tomorrow 07:00
        #expect(f.store.nextClearing(for: profile) == note.expiresAt)
    }
}
