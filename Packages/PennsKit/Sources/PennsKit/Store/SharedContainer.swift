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

    public static let schema = Schema(versionedSchema: PennsSchemaV1.self)

    /// The process-wide container. Each caller should create its own
    /// `ModelContext` from it so it always reads fresh data.
    public static var shared: ModelContainer { opened.container }

    /// Why the store on disk couldn't be opened, or nil when it's fine. While
    /// set, `shared` is an empty in-memory store: nothing typed there is kept,
    /// so the apps show an error instead of the note and extensions refuse to
    /// write (`requireAvailable()`). The file on disk is left untouched.
    public static var loadFailure: String? { opened.failure }
    public static var isAvailable: Bool { loadFailure == nil }

    public struct UnavailableError: LocalizedError {
        public var errorDescription: String? { "Penns couldn't open your note. Open the Penns app to see what happened." }
    }

    /// Throws when the note can't be saved because the store didn't open.
    public static func requireAvailable() throws {
        if !isAvailable { throw UnavailableError() }
    }

    private static let logger = Logger(subsystem: "com.mirzapolat.penns", category: "store")
    private static let opened: (container: ModelContainer, failure: String?) = openShared()

    /// An in-memory container for tests and previews.
    public static func make(inMemory: Bool = true) -> ModelContainer {
        precondition(inMemory, "Use SharedContainer.shared for the store on disk")
        return memoryContainer()
    }

    /// Opens the store at `url` with the versioned schema and migration plan.
    public static func open(at url: URL, cloudKitDatabase: ModelConfiguration.CloudKitDatabase) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: PennsMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: cloudKitDatabase)
        )
    }

    private static func openShared() -> (container: ModelContainer, failure: String?) {
        let url = storeURL()
        let isApp = Bundle.main.bundleURL.pathExtension != "appex"
        if isApp {
            migrateLegacyStoreIfNeeded(to: url)
            backUpBeforeOpening(url)
        }
        do {
            return (try open(at: url, cloudKitDatabase: cloudKitDatabase), nil)
        } catch {
            logger.error("Opening the store failed, retrying: \(error.localizedDescription, privacy: .public)")
        }
        // Another process (a widget, an intent) may be holding the file for a moment.
        Thread.sleep(forTimeInterval: 0.5)
        do {
            return (try open(at: url, cloudKitDatabase: cloudKitDatabase), nil)
        } catch {
            logger.fault("Opening the store failed: \(String(describing: error), privacy: .public)")
            if isApp { StoreBackup.backUp(storeAt: url) }
            return (memoryContainer(), error.localizedDescription)
        }
    }

    /// A backup at most every 12 hours, and always when the app version
    /// changed (a new version may migrate the store).
    private static func backUpBeforeOpening(_ url: URL) {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "")-\(info["CFBundleVersion"] as? String ?? "")"
        let marker = StoreBackup.backupsDirectory(forStoreAt: url).appending(path: ".version")
        let lastVersion = try? String(contentsOf: marker, encoding: .utf8)
        let force = lastVersion != version
        if StoreBackup.backUpIfDue(storeAt: url, force: force) != nil || lastVersion == nil {
            try? version.write(to: marker, atomically: true, encoding: .utf8)
        }
    }

    private static func memoryContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        } catch {
            fatalError("An in-memory store can't fail to open: \(error)")
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
