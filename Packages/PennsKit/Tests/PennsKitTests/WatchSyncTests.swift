import Foundation
import Testing
@testable import PennsKit

@Suite struct WatchSyncTests {
    private func fixture(_ text: String) throws -> (Fixture, Profile) {
        let f = Fixture()
        let profile = f.store.defaultProfile()
        f.store.setText(text, of: f.store.activeNote(in: profile))
        try f.store.save()
        return (f, profile)
    }

    @Test func snapshotHasEveryProfile() throws {
        let (f, profile) = try fixture("Milk")
        let work = f.store.createProfile(name: "Work")
        f.store.setText("Slides", of: f.store.activeNote(in: work))
        try f.store.save()

        let snapshot = WatchSnapshot.make(from: f.store, currentID: work.id)
        #expect(snapshot.pages.map(\.text) == ["Milk", "Slides"])
        #expect(snapshot.current?.id == work.id)
        #expect(snapshot.page(profile.id)?.name == profile.name)
    }

    /// What the watch shows right away must match what the iPhone then does.
    @Test(arguments: [
        "toggle", "append", "replace", "archive",
    ])
    func optimisticResultMatchesThePhone(kind: String) throws {
        let (f, profile) = try fixture("Groceries\n- [ ] Milk\n- [x] Eggs")
        let before = WatchSnapshot.make(from: f.store, currentID: profile.id)
        let itemID = Checklist.items(in: before.pages[0].text)[0].id
        let command: WatchCommand = switch kind {
        case "toggle": .toggle(itemID: itemID, profileID: profile.id)
        case "append": .append(text: "Bread", profileID: profile.id)
        case "replace": .replace(text: "Call Mia", profileID: profile.id)
        default: .archive(profileID: profile.id)
        }

        let predicted = before.applying(command)
        #expect(command.apply(to: f.store))
        try f.store.save()
        let actual = WatchSnapshot.make(from: f.store, currentID: profile.id)
        #expect(predicted.pages.map(\.text) == actual.pages.map(\.text))
    }

    @Test func archivedNoteLandsInTheArchive() throws {
        let (f, profile) = try fixture("Done")
        WatchCommand.archive(profileID: profile.id).apply(to: f.store)
        #expect(f.store.archivedNotes(in: profile).map(\.text) == ["Done"])
    }

    @Test func unknownProfileIsIgnored() throws {
        let (f, _) = try fixture("Milk")
        #expect(!WatchCommand.archive(profileID: UUID()).apply(to: f.store))
    }

    @Test func messagesRoundTrip() throws {
        let (f, profile) = try fixture("Milk")
        let snapshot = WatchSnapshot.make(from: f.store, currentID: profile.id)
        #expect(WatchSnapshot(message: snapshot.message) == snapshot)
        let command = WatchCommand.append(text: "Eggs", profileID: profile.id)
        #expect(WatchCommand(message: command.message) == command)
        #expect(WatchCommand(message: ["other": 1]) == nil)
    }

    @Test func snapshotIsStoredForComplications() throws {
        let (f, profile) = try fixture("Milk")
        let defaults = try #require(UserDefaults(suiteName: "WatchSyncTests-\(UUID().uuidString)"))
        let snapshot = WatchSnapshot.make(from: f.store, currentID: profile.id)
        snapshot.save(to: defaults)
        #expect(WatchSnapshot.load(from: defaults) == snapshot)
    }
}
