import Foundation
import SwiftData
import Testing
@testable import PennsKit

@Suite struct StoreSafetyTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "PennsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a store the way builds before the versioned schema did.
    private func writeStore(at url: URL, text: String) throws {
        let container = try ModelContainer(
            for: Schema([Note.self, Profile.self]),
            configurations: ModelConfiguration(schema: Schema([Note.self, Profile.self]), url: url, cloudKitDatabase: .none)
        )
        let store = NoteStore(context: ModelContext(container))
        store.setText(text, of: store.activeNote())
        try store.save()
    }

    @Test func versionedStoreOpensAnExistingStoreWithItsText() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Penns.store")
        try writeStore(at: url, text: "Keep me")

        let container = try SharedContainer.open(at: url, cloudKitDatabase: .none)
        let store = NoteStore(context: ModelContext(container))
        #expect(store.activeNote().text == "Keep me")
    }

    @Test func backupCopiesTheStoreWithItsWriteAheadLog() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Penns.store")
        try writeStore(at: url, text: "Backed up")

        let backup = try #require(StoreBackup.backUp(storeAt: url, now: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(FileManager.default.fileExists(atPath: backup.appending(path: "Penns.store").path))

        // The copy opens on its own and holds the text.
        let container = try SharedContainer.open(at: backup.appending(path: "Penns.store"), cloudKitDatabase: .none)
        #expect(NoteStore(context: ModelContext(container)).activeNote().text == "Backed up")
    }

    @Test func backupsAreThrottledAndOnlyTheNewestAreKept() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Penns.store")
        try writeStore(at: url, text: "Note")

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(StoreBackup.backUpIfDue(storeAt: url, now: start) != nil)
        #expect(StoreBackup.backUpIfDue(storeAt: url, now: start.addingTimeInterval(60)) == nil)
        // A forced backup (new app version, before a migration) always runs.
        #expect(StoreBackup.backUpIfDue(storeAt: url, now: start.addingTimeInterval(120), force: true) != nil)

        for day in 1...10 {
            _ = StoreBackup.backUpIfDue(storeAt: url, now: start.addingTimeInterval(Double(day) * 86_400))
        }
        #expect(StoreBackup.backups(forStoreAt: url).count == StoreBackup.keepCount)
    }

    @Test func noBackupWithoutAStore() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(StoreBackup.backUpIfDue(storeAt: directory.appending(path: "Penns.store"), now: .now) == nil)
    }

    @Test func rescueCopyKeepsUnsavedText() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Penns.store")

        let file = try #require(StoreBackup.writeRescueCopy("Unsaved words", storeAt: url, now: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(try String(contentsOf: file, encoding: .utf8) == "Unsaved words")
    }
}
