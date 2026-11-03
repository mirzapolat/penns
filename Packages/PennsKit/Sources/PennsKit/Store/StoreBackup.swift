import Foundation
import os

/// Safety copies of the note store on disk, next to it:
///
///     Penns.store
///     Backups/2026-11-03_081500/Penns.store (+ -wal, -shm)
///     Rescue/2026-11-03_081500.txt
///
/// Backups are taken by the app before the store is opened (at most every
/// `minimumInterval`, always when the app version changed), so a failed
/// migration or a damaged file never takes the only copy with it.
/// Rescue copies hold plain text that couldn't be saved.
public enum StoreBackup {
    public static let keepCount = 5
    public static let minimumInterval: TimeInterval = 12 * 60 * 60
    private static let suffixes = ["", "-wal", "-shm"]
    private static let logger = Logger(subsystem: "com.mirzapolat.penns", category: "backup")

    public static func backupsDirectory(forStoreAt store: URL) -> URL {
        store.deletingLastPathComponent().appending(path: "Backups", directoryHint: .isDirectory)
    }

    public static func rescueDirectory(forStoreAt store: URL) -> URL {
        store.deletingLastPathComponent().appending(path: "Rescue", directoryHint: .isDirectory)
    }

    /// Backup folders, newest first.
    public static func backups(forStoreAt store: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: backupsDirectory(forStoreAt: store),
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        // Folder names are timestamps, so name order is date order.
        return contents.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Backs up when the newest backup is older than `minimumInterval`, or
    /// always with `force`. Returns the new backup folder.
    @discardableResult
    public static func backUpIfDue(storeAt store: URL, now: Date = .now, force: Bool = false) -> URL? {
        if !force, let newest = backups(forStoreAt: store).first.flatMap({ date(ofBackup: $0) }),
           now.timeIntervalSince(newest) < minimumInterval {
            return nil
        }
        return backUp(storeAt: store, now: now)
    }

    /// Copies the store with its write-ahead log and prunes old backups.
    /// Returns nil when there's no store yet or copying failed.
    @discardableResult
    public static func backUp(storeAt store: URL, now: Date = .now) -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: store.path) else { return nil }
        let folder = backupsDirectory(forStoreAt: store).appending(path: stamp(now), directoryHint: .isDirectory)
        do {
            if fileManager.fileExists(atPath: folder.path) {
                try fileManager.removeItem(at: folder)
            }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for suffix in suffixes {
                let from = URL(fileURLWithPath: store.path + suffix)
                guard fileManager.fileExists(atPath: from.path) else { continue }
                try fileManager.copyItem(at: from, to: folder.appending(path: store.lastPathComponent + suffix))
            }
            logger.notice("Backed up the store to \(folder.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("Backup failed: \(error.localizedDescription, privacy: .public)")
            try? fileManager.removeItem(at: folder)
            return nil
        }
        prune(storeAt: store)
        return folder
    }

    /// Writes `text` to a plain text file next to the store, for text that
    /// couldn't be saved to the store. Returns the file.
    @discardableResult
    public static func writeRescueCopy(_ text: String, storeAt store: URL, now: Date = .now) -> URL? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let directory = rescueDirectory(forStoreAt: store)
        let file = directory.appending(path: stamp(now) + ".txt")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            logger.notice("Wrote a rescue copy: \(file.lastPathComponent, privacy: .public)")
            return file
        } catch {
            logger.fault("Rescue copy failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Private

    private static func prune(storeAt store: URL) {
        for old in backups(forStoreAt: store).dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }

    private static func stamp(_ date: Date) -> String {
        formatter().string(from: date)
    }

    private static func date(ofBackup folder: URL) -> Date? {
        formatter().date(from: folder.lastPathComponent)
    }
}
