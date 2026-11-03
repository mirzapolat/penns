import Foundation
import SwiftData
import os

/// Builds the SwiftData container shared by the app, widgets and intents
/// through the App Group container.
public enum SharedContainer {
    /// Info.plist key holding the App Group identifier (set from the
    /// `APP_GROUP_IDENTIFIER` build setting).
    public static let appGroupInfoKey = "PennsAppGroup"
    /// Info.plist key with the iCloud container ("iCloud.com.…"). Empty = sync off.
    public static let cloudKitInfoKey = "PennsCloudKitContainer"

    public static let schema = Schema([Note.self, Profile.self])

    /// The process-wide container. Each caller should create its own
    /// `ModelContext` from it so it always reads fresh data.
    public static let shared: ModelContainer = make()

    private static let logger = Logger(subsystem: "com.mirzapolat.penns", category: "store")

    public static func make(inMemory: Bool = false) -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let url = storeURL()
            migrateLegacyStoreIfNeeded(to: url)
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: cloudKitDatabase)
        }
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            logger.fault("Opening the store failed, falling back to memory: \(error.localizedDescription, privacy: .public)")
            // Keep the app usable rather than crash-looping; nothing is written to disk.
            return try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        }
    }

    /// iCloud sync runs only in the app, never in extensions, and only when an
    /// iCloud container is configured (requires the iCloud capability).
    public static var cloudKitContainerID: String? {
        guard Bundle.main.bundleURL.pathExtension != "appex",
              let container = Bundle.main.object(forInfoDictionaryKey: cloudKitInfoKey) as? String,
              !container.isEmpty else { return nil }
        return container
    }

    static var cloudKitDatabase: ModelConfiguration.CloudKitDatabase {
        cloudKitContainerID.map { .private($0) } ?? .none
    }

    /// Earlier builds may have stored the note elsewhere: in the app's own
    /// container when no App Group was available, or in a differently named App
    /// Group (the group id changes once a development team is set). If the
    /// current store doesn't exist yet, copy the newest earlier one over so the
    /// note never "disappears". The originals are left in place.
    static func migrateLegacyStoreIfNeeded(to target: URL) {
        let fileManager = FileManager.default
        guard Bundle.main.bundleURL.pathExtension != "appex",
              !fileManager.fileExists(atPath: target.path) else { return }

        let support = URL.applicationSupportDirectory
        let candidates = [
            support.appending(path: "Penns.store"),
            support.appending(path: "Penns/Penns.store"),
        ].filter { $0.standardizedFileURL != target.standardizedFileURL && fileManager.fileExists(atPath: $0.path) }

        let newest = candidates.max { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l < r
        }
        guard let source = newest else { return }

        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            // SQLite keeps recent writes in the -wal file; copy all three together.
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: source.path + suffix)
                let to = URL(fileURLWithPath: target.path + suffix)
                if fileManager.fileExists(atPath: from.path) {
                    try fileManager.copyItem(at: from, to: to)
                }
            }
            logger.notice("Migrated note store from \(source.path, privacy: .public)")
        } catch {
            logger.error("Store migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `<App Group>/Library/Application Support/Penns.store`, or the app's own
    /// Application Support folder when no App Group is available.
    public static func storeURL() -> URL {
        let fileManager = FileManager.default
        let directory: URL
        if let group = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
           !group.isEmpty,
           let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: group) {
            directory = groupURL.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        } else {
            directory = URL.applicationSupportDirectory.appending(path: "Penns", directoryHint: .isDirectory)
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Penns.store")
    }
}
