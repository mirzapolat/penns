import Foundation
import SwiftData
import Testing
@testable import PennsKit

final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

struct Fixture {
    let container: ModelContainer
    let store: NoteStore
    let clock: TestClock

    init(now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        container = SharedContainer.make(inMemory: true)
        clock = TestClock(now)
        let clock = clock
        store = NoteStore(context: ModelContext(container), calendar: calendar, now: { clock.now })
    }

    func activeCount() -> Int {
        ((try? store.context.fetch(FetchDescriptor<Note>())) ?? []).filter(\.isActive).count
    }
}

@Suite struct NoteStoreTests {
    @Test func activeNoteIsCreatedOnceAndReused() throws {
        let f = Fixture()
        let first = f.store.activeNote()
        try f.store.save()
        #expect(f.store.activeNote().id == first.id)
        #expect(f.activeCount() == 1)
    }

    @Test func archiveCreatesBlankNoteAndCountsIt() throws {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("Buy milk", of: note)
        let blank = f.store.archive(note)

        #expect(blank.id != note.id)
        #expect(blank.isBlank && blank.isActive)
        #expect(!note.isActive && note.archivedAt != nil)
        #expect(f.store.defaultProfile().clearedCount == 1)
        #expect(f.store.archivedNotes().map(\.id) == [note.id])
        #expect(f.activeCount() == 1)
    }

    @Test func archivingBlankNoteDoesNothing() {
        let f = Fixture()
        let note = f.store.activeNote()
        #expect(f.store.archive(note).id == note.id)
        #expect(f.store.archivedNotes().isEmpty)
        #expect(f.store.defaultProfile().clearedCount == 0)
    }

    @Test func undoArchiveRestoresNoteAndDropsBlank() {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("Call mum", of: note)
        _ = f.store.archive(note)
        let restored = f.store.restore(note, isUndo: true)

        #expect(restored.id == note.id && restored.isActive)
        #expect(f.store.archivedNotes().isEmpty)
        #expect(f.store.defaultProfile().clearedCount == 0)
        #expect(f.activeCount() == 1)
    }

    @Test func restoreArchivesCurrentNoteWhenItHasContent() {
        let f = Fixture()
        let old = f.store.activeNote()
        f.store.setText("Old", of: old)
        let current = f.store.archive(old)
        f.store.setText("Current", of: current)

        let restored = f.store.restore(old)
        #expect(restored.id == old.id && restored.isActive)
        #expect(f.store.archivedNotes().map(\.id) == [current.id])
        #expect(f.activeCount() == 1)
    }

    @Test func deleteAndUndo() {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("Secret", of: note)
        let (snapshot, blank) = f.store.delete(note)
        #expect(blank.isBlank && blank.isActive)
        #expect(f.store.defaultProfile().clearedCount == 1)

        let back = f.store.undoDelete(snapshot)
        #expect(back.text == "Secret" && back.isActive)
        #expect(f.store.defaultProfile().clearedCount == 0)
        #expect(f.activeCount() == 1)
    }

    @Test func repairKeepsMostRecentlyEditedNote() {
        let f = Fixture()
        let profile = f.store.defaultProfile()
        let older = Note(text: "older", isActive: true, now: f.clock.now)
        let newer = Note(text: "newer", isActive: true, now: f.clock.now.addingTimeInterval(10))
        let blank = Note(text: "", isActive: true, now: f.clock.now)
        for note in [older, newer, blank] {
            f.store.context.insert(note)
            note.profile = profile
        }

        #expect(f.store.repair(profile))
        #expect(f.store.activeNote().id == newer.id)
        #expect(f.store.archivedNotes().map(\.id) == [older.id])
        #expect(f.activeCount() == 1)
    }

    @Test func appendAddsLines() {
        let f = Fixture()
        f.store.append("one")
        f.store.append("two")
        #expect(f.store.activeNote().text == "one\ntwo")
    }

    @Test func replaceActiveArchivesNonEmptyNote() {
        let f = Fixture()
        let first = f.store.activeNote()
        f.store.setText("first", of: first)
        let second = f.store.replaceActive(with: "second", lifespan: .today)
        #expect(second.text == "second" && second.lifespan == .today && second.expiresAt != nil)
        #expect(f.store.archivedNotes().map(\.text) == ["first"])
    }

    @Test func todayLifespanExpiresAtMidnightAndArchives() {
        let f = Fixture(now: Date(timeIntervalSince1970: 1_800_000_000)) // 2027-01-15 08:00 UTC
        let note = f.store.activeNote()
        f.store.setText("Today only", of: note)
        f.store.setLifespan(.today, of: note)
        #expect(note.expiresAt == Date(timeIntervalSince1970: 1_800_057_600)) // next midnight UTC

        f.clock.now = note.expiresAt!.addingTimeInterval(-1)
        #expect(f.store.applyDueTransitions().isEmpty)

        f.clock.now = note.expiresAt!
        #expect(f.store.applyDueTransitions().map(\.id) == [note.id])
        #expect(f.store.activeNote().isBlank)
    }

    @Test func restoringExpiredNoteClearsLifespan() {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("x", of: note)
        f.store.setLifespan(.today, of: note)
        f.clock.advance(2 * 24 * 3600)
        f.store.applyDueTransitions()
        let restored = f.store.restore(note)
        #expect(restored.lifespan == .untilDone && restored.expiresAt == nil)
    }

    @Test func staleAfterSevenDaysUntilDismissed() {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("Old idea", of: note)
        f.clock.advance(Lifecycle.staleInterval - 60)
        #expect(!f.store.isStale(note))
        f.clock.advance(120)
        #expect(f.store.isStale(note))
        f.store.dismissStale(note)
        #expect(!f.store.isStale(note))
    }

    @Test func toggleChecklistItemThroughStore() {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("- [ ] eggs", of: note)
        let id = Checklist.items(in: note.text)[0].id
        #expect(f.store.toggleChecklistItem(id))
        #expect(note.text == "- [x] eggs")
    }

    @Test func customExpiryArchivesAtThatMoment() {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("Dentist", of: note)
        let moment = f.clock.now.addingTimeInterval(90 * 60)
        f.store.setExpiry(moment, of: note)
        #expect(note.lifespan == .custom && note.expiresAt == moment)

        f.clock.now = moment.addingTimeInterval(-1)
        #expect(f.store.applyExpiries().isEmpty)
        f.clock.now = moment
        #expect(f.store.applyExpiries().map(\.id) == [note.id])
    }

    @Test func clearingCustomExpiryReturnsToUntilDone() {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setExpiry(f.clock.now.addingTimeInterval(60), of: note)
        f.store.setExpiry(nil, of: note)
        #expect(note.lifespan == .untilDone && note.expiresAt == nil)
    }

    @Test func expiryLabelShowsTimeForCustomMoments() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000) // Fri 08:00 UTC
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        #expect(Lifecycle.expiryLabel(midnight, now: now, calendar: calendar) == "today")
        let later = Lifecycle.expiryLabel(now.addingTimeInterval(2 * 86400 + 3600), now: now, calendar: calendar)
        #expect(later.hasPrefix("until ") && later.contains(":"))
    }

    @Test func clearingSubstantialNoteKeepsCopyInArchive() {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("This is actually important, keep it", of: note)
        let copy = f.store.setText("", of: note)
        #expect(copy?.text == "This is actually important, keep it")
        #expect(f.store.archivedNotes().map(\.text) == ["This is actually important, keep it"])
        #expect(f.store.defaultProfile().clearedCount == 0)
        #expect(f.activeCount() == 1)
    }

    @Test func deletingCharacterByCharacterKeepsNoCopy() {
        let f = Fixture()
        let note = f.store.activeNote()
        f.store.setText("short", of: note)
        f.store.setText("", of: note)
        #expect(f.store.archivedNotes().isEmpty)
    }
}
