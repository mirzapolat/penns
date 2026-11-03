import Foundation
import PennsKit
import SwiftData
import WatchConnectivity
import os

/// The iPhone's half of the watch connection. The iPhone's store is the only
/// source of truth: it sends the watch a snapshot of every profile's note and
/// carries out what the watch asks for (tick, add, new note, archive).
final class WatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchBridge()

    private let queue = DispatchQueue(label: "com.mirzapolat.penns.watch")
    private let logger = Logger(subsystem: "com.mirzapolat.penns", category: "watch")
    private var pendingPush: DispatchWorkItem?

    private var session: WCSession? { WCSession.isSupported() ? .default : nil }

    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Sends a fresh snapshot shortly after the last change (typing stays cheap).
    func schedulePush() {
        queue.async { [self] in
            pendingPush?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.push() }
            pendingPush = work
            queue.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func push() {
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(snapshot().message)
    }

    private func snapshot() -> WatchSnapshot {
        let store = NoteStore(context: ModelContext(SharedContainer.shared))
        store.applyDueTransitions()
        let snapshot = WatchSnapshot.make(from: store, currentID: ProfileSelection.preferredID)
        try? store.save()
        return snapshot
    }

    /// Carries out a command from the watch. Saving posts the usual change
    /// signal, so the open note, widgets and Live Activity follow.
    private func handle(_ message: [String: Any]) -> [String: Any] {
        guard let command = WatchCommand(message: message) else { return [:] }
        do {
            _ = try IntentStore.mutate { store in command.apply(to: store) }
        } catch {
            logger.error("Watch command failed: \(error.localizedDescription, privacy: .public)")
        }
        Task { await LiveNote.refreshAll() }
        let current = snapshot()
        push()
        return current.message
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated { schedulePush() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another watch: start talking to the new one.
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        schedulePush()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        replyHandler(handle(message))
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        _ = handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        _ = handle(userInfo)
    }
}
