import ActivityKit
import Observation
import PennsKit
import SwiftUI

/// The app's side of the Live Activity: Go Live / End, keeping it in sync while
/// you type, and renewing it before iOS's 8-hour limit.
@MainActor
@Observable
final class LiveController {
    static let autoRenewKey = "liveAutoRenew"

    private(set) var liveProfileIDs: Set<UUID> = []
    var isAvailable: Bool { LiveNote.isAvailable }

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [Task<Void, Never>] = []

    init() {
        sync()
        observers.append(Task { [weak self] in
            for await activity in Activity<NoteActivityAttributes>.activityUpdates {
                self?.sync()
                self?.watch(activity)
            }
        })
        for activity in LiveNote.activities { watch(activity) }
    }

    func isLive(_ profileID: UUID) -> Bool { liveProfileIDs.contains(profileID) }

    func goLive(_ model: NoteViewModel) {
        model.flush()
        Task {
            do {
                try await LiveNote.start(profileID: model.profile.id)
            } catch {
                model.showToast("Live Activities are off for Penns", actionTitle: nil, action: nil)
            }
            sync()
        }
    }

    func end(_ model: NoteViewModel) {
        Task {
            await LiveNote.end(profileID: model.profile.id)
            sync()
        }
    }

    /// Typing updates the Live Activity, at most a few times a second.
    func noteChanged() {
        guard !liveProfileIDs.isEmpty else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await LiveNote.refreshAll()
            sync()
        }
    }

    /// The app came to the front: renew what's about to expire and bring back
    /// what iOS ended (or offer to, when auto-renew is off).
    func appBecameActive(_ model: NoteViewModel) {
        let automatically = UserDefaults.standard.object(forKey: Self.autoRenewKey) as? Bool ?? true
        Task {
            let lapsed = await LiveNote.renew(automatically: automatically)
            await LiveNote.refreshAll()
            sync()
            if lapsed.contains(model.profile.id) {
                model.showToast("Live Activity ended", actionTitle: "Go Live") { [weak self, weak model] in
                    guard let self, let model else { return }
                    self.goLive(model)
                }
            }
        }
    }

    private func sync() {
        liveProfileIDs = Set(LiveNote.activities.filter { $0.activityState == .active }.map(\.attributes.profileID))
    }

    /// Swiping the activity away on the Lock Screen means "not now": don't bring it back.
    private func watch(_ activity: Activity<NoteActivityAttributes>) {
        observers.append(Task { [weak self] in
            for await state in activity.activityStateUpdates {
                if state == .dismissed,
                   Date.now.timeIntervalSince(activity.attributes.startedAt) < LiveNote.renewAfter {
                    LiveNote.forget(activity.attributes.profileID)
                }
                self?.sync()
            }
        })
    }
}
