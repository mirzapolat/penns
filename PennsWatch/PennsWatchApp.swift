import Observation
import PennsKit
import SwiftUI
import WatchConnectivity
import WidgetKit

@main
struct PennsWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchNoteView(model: model)
        }
    }
}

/// The watch's view of the note: the iPhone's last snapshot, plus the result
/// of anything done here that the iPhone hasn't confirmed yet.
@MainActor
@Observable
final class WatchModel {
    private(set) var snapshot: WatchSnapshot?
    /// The profile shown here; follows the iPhone until picked on the watch.
    var selectedID: UUID?

    @ObservationIgnored private let session = WatchSession()

    init() {
        snapshot = WatchSnapshot.load(from: ProfileSelection.defaults)
        session.onSnapshot = { [weak self] snapshot in self?.receive(snapshot) }
        session.start()
    }

    var page: WatchSnapshot.Page? {
        guard let snapshot else { return nil }
        return selectedID.flatMap(snapshot.page) ?? snapshot.current
    }

    var pages: [WatchSnapshot.Page] { snapshot?.pages ?? [] }

    func receive(_ snapshot: WatchSnapshot) {
        guard snapshot.updatedAt >= (self.snapshot?.updatedAt ?? .distantPast) || self.snapshot == nil else { return }
        self.snapshot = snapshot
        store()
    }

    func send(_ command: WatchCommand) {
        guard let snapshot else { return }
        self.snapshot = snapshot.applying(command)
        store()
        session.send(command)
    }

    /// Complications read the same snapshot from the App Group.
    private func store() {
        snapshot?.save(to: ProfileSelection.defaults)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// WatchConnectivity on the watch: snapshots in, commands out. Commands go
/// straight to the iPhone when it's reachable and are queued otherwise.
final class WatchSession: NSObject, WCSessionDelegate, @unchecked Sendable {
    var onSnapshot: (@MainActor (WatchSnapshot) -> Void)?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: WatchCommand) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.transferUserInfo(command.message)
            return
        }
        if session.isReachable {
            session.sendMessage(command.message) { [weak self] reply in
                if let snapshot = WatchSnapshot(message: reply) { self?.deliver(snapshot) }
            } errorHandler: { _ in
                session.transferUserInfo(command.message)
            }
        } else {
            session.transferUserInfo(command.message)
        }
    }

    private func deliver(_ snapshot: WatchSnapshot) {
        Task { @MainActor [onSnapshot] in onSnapshot?(snapshot) }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let snapshot = WatchSnapshot(message: session.receivedApplicationContext) { deliver(snapshot) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        if let snapshot = WatchSnapshot(message: context) { deliver(snapshot) }
    }
}
