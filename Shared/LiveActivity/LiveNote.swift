#if os(iOS)
import ActivityKit
import Foundation
import PennsKit
import SwiftData

/// The note on the Lock Screen and in the Dynamic Island, full width.
struct NoteActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The note, trimmed to what a Live Activity can show.
        var text: String
        var expiresAt: Date?
        var profileName: String
        var profileColor: String
        var showsProfile: Bool

        var lines: [Checklist.Line] { Checklist.parse(text.trimmingCharacters(in: .newlines)) }
        var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var allChecked: Bool { Checklist.allChecked(text) }
        var progress: (done: Int, total: Int) {
            let items = Checklist.items(in: text)
            return (items.filter(\.isChecked).count, items.count)
        }
    }

    var profileID: UUID
    /// When this activity was started; iOS ends Live Activities after about 8 hours.
    var startedAt: Date
}

/// Starts, updates, renews and ends the note's Live Activities: one per profile.
enum LiveNote {
    /// iOS ends a Live Activity after 8 hours; renew a little before that.
    static let renewAfter: TimeInterval = 7 * 60 * 60
    /// Live Activities are small: keep the payload well under the 4 KB limit.
    static let maxTextLength = 1_500
    static let maxLines = 12

    private static let wantedKey = "liveProfileIDs"

    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static var activities: [Activity<NoteActivityAttributes>] { Activity<NoteActivityAttributes>.activities }

    static func activity(for profileID: UUID) -> Activity<NoteActivityAttributes>? {
        activities.first { $0.attributes.profileID == profileID && $0.activityState == .active }
    }

    static func isLive(_ profileID: UUID) -> Bool { activity(for: profileID) != nil }

    // MARK: Which profiles the user wants live (survives the 8-hour limit)

    static var wantedProfileIDs: Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: wantedKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    /// The user swiped the activity away: don't bring it back on its own.
    static func forget(_ profileID: UUID) {
        setWanted(profileID, false)
    }

    private static func setWanted(_ profileID: UUID, _ wanted: Bool) {
        var ids = wantedProfileIDs
        if wanted { ids.insert(profileID) } else { ids.remove(profileID) }
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: wantedKey)
    }

    // MARK: Content

    static func state(for profile: Profile, in store: NoteStore) -> NoteActivityAttributes.ContentState {
        let note = store.activeNote(in: profile)
        var lines = note.text.trimmingCharacters(in: .newlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(maxLines)
            .joined(separator: "\n")
        if lines.utf8.count > maxTextLength {
            lines = String(lines.prefix(maxTextLength))
        }
        return .init(
            text: lines,
            expiresAt: note.expiresAt,
            profileName: profile.name,
            profileColor: profile.colorHex,
            showsProfile: store.profiles().count > 1
        )
    }

    // MARK: Actions

    /// Shows the profile's note (or the current one) as a Live Activity, or
    /// updates it if it's already live. Must run while the app is in front.
    @discardableResult
    static func start(profileID: UUID? = nil) async throws -> Bool {
        guard isAvailable else { return false }
        let store = NoteStore(context: ModelContext(SharedContainer.shared))
        store.applyDueTransitions()
        let profile = profileID.flatMap { store.profile(id: $0) }
            ?? store.currentProfile(preferredID: ProfileSelection.preferredID)
        let state = state(for: profile, in: store)
        try? store.save()
        setWanted(profile.id, true)

        if let existing = activity(for: profile.id) {
            await existing.update(ActivityContent(state: state, staleDate: nil))
            return true
        }
        _ = try Activity.request(
            attributes: NoteActivityAttributes(profileID: profile.id, startedAt: .now),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        return true
    }

    /// Ends the profile's Live Activity (or all of them).
    static func end(profileID: UUID? = nil) async {
        for activity in activities where profileID == nil || activity.attributes.profileID == profileID {
            setWanted(activity.attributes.profileID, false)
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if profileID == nil {
            UserDefaults.standard.removeObject(forKey: wantedKey)
        }
    }

    /// Brings every Live Activity up to date with the store. A note that was
    /// archived or deleted ends its activity: there's nothing left to show.
    static func refreshAll() async {
        let running = activities.filter { $0.activityState == .active }
        guard !running.isEmpty else { return }
        let store = NoteStore(context: ModelContext(SharedContainer.shared))
        for activity in running {
            guard let profile = store.profile(id: activity.attributes.profileID) else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let state = state(for: profile, in: store)
            if state.isEmpty {
                setWanted(profile.id, false)
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            } else if state != activity.content.state {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    /// Run when the app comes to the front: restarts activities close to the
    /// 8-hour limit, and (with auto-renew) brings back ones iOS ended.
    /// Returns the profiles whose activity ended and wasn't renewed.
    @discardableResult
    static func renew(automatically: Bool) async -> [UUID] {
        guard isAvailable else { return [] }
        var lapsed: [UUID] = []
        for activity in activities where activity.activityState == .active
            && Date.now.timeIntervalSince(activity.attributes.startedAt) > renewAfter {
            let id = activity.attributes.profileID
            await activity.end(nil, dismissalPolicy: .immediate)
            _ = try? await start(profileID: id)
        }
        for id in wantedProfileIDs where !isLive(id) {
            if automatically {
                _ = try? await start(profileID: id)
            } else {
                lapsed.append(id)
            }
        }
        return lapsed
    }
}
#endif
