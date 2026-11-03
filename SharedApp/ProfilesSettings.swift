import Observation
import os
import PennsKit
import SwiftData
import SwiftUI
import WidgetKit

/// Edits profiles in the shared store; the note panel reloads on change.
/// Every write fetches the profile fresh by id (`NoteStore.updateProfile`), so
/// Settings never saves an old copy over newer values from the panel, the
/// widget or an intent (e.g. `clearedCount`).
@MainActor
@Observable
final class ProfilesModel {
    private(set) var profiles: [Profile] = []
    @ObservationIgnored private let container = SharedContainer.shared
    @ObservationIgnored private let logger = Logger(subsystem: "com.mirzapolat.penns", category: "settings")

    func reload() {
        profiles = NoteStore(context: ModelContext(container)).profiles()
    }

    func add() {
        let store = NoteStore(context: ModelContext(container))
        let profile = store.createProfile(name: "Profile \(store.profiles().count + 1)")
        _ = store.activeNote(in: profile)
        save { try store.save() }
    }

    func rename(_ profile: Profile, to name: String) {
        update(profile) { profile, _ in profile.name = name }
    }

    func setColor(_ hex: String, for profile: Profile) {
        update(profile) { profile, _ in profile.colorHex = hex }
    }

    func setMorningReset(enabled: Bool, minutes: Int, for profile: Profile) {
        update(profile) { profile, store in
            store.setMorningReset(enabled: enabled, minutes: minutes, for: profile)
        }
    }

    func delete(_ profile: Profile) {
        update(profile) { profile, store in store.deleteProfile(profile) }
    }

    private func update(_ profile: Profile, _ change: (Profile, NoteStore) -> Void) {
        let id = profile.id
        let container = container
        save { try NoteStore.updateProfile(id: id, in: container, change) }
    }

    private func save(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            logger.error("Saving profiles failed: \(error.localizedDescription, privacy: .public)")
        }
        reload()
        ChangeSignal.post(sender: self)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct ProfilesSection: View {
    @State private var model = ProfilesModel()
    @State private var expandedID: UUID?

    var body: some View {
        Section {
            ForEach(model.profiles) { profile in
                ProfileHeaderRow(profile: profile, isExpanded: expandedID == profile.id) {
                    withAnimation(.snappy(duration: 0.25)) {
                        expandedID = expandedID == profile.id ? nil : profile.id
                    }
                }
                if expandedID == profile.id {
                    ProfileDetailRows(profile: profile, model: model) {
                        expandedID = nil
                    }
                }
            }
            Button {
                model.add()
                withAnimation(.snappy(duration: 0.25)) { expandedID = model.profiles.last?.id }
            } label: {
                Label("Add Profile", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Profiles")
        } footer: {
            Text("Each profile has its own note. Pick a profile per Focus in System Settings → Focus → Focus Filters → Penns.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: model.reload)
    }
}

/// The whole row is the click target; the chevron shows the state.
private struct ProfileHeaderRow: View {
    let profile: Profile
    let isExpanded: Bool
    var toggle: () -> Void

    static func timeText(minutes: Int) -> String {
        let date = Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Circle()
                    .fill(ProfileColors.color(profile.colorHex))
                    .frame(width: 10, height: 10)
                Text(profile.name.isEmpty ? "Untitled" : profile.name)
                    .foregroundStyle(.primary)
                if profile.morningResetEnabled {
                    Label(Self.timeText(minutes: profile.morningResetMinutes), systemImage: "sunrise")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("Fresh start every morning")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .frame(minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(profile.name)
        .accessibilityHint(isExpanded ? "Collapse" : "Expand")
    }
}

/// Plain Settings rows, so labels and controls line up with the rest of the form.
private struct ProfileDetailRows: View {
    let profile: Profile
    let model: ProfilesModel
    var didDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        TextField("Name", text: Binding(
            get: { profile.name },
            set: { model.rename(profile, to: $0) }
        ))

        LabeledContent("Color") {
            HStack(spacing: 8) {
                ForEach(ProfileColors.all, id: \.self) { hex in
                    Button {
                        model.setColor(hex, for: profile)
                    } label: {
                        Circle()
                            .fill(ProfileColors.color(hex))
                            .frame(width: 16, height: 16)
                            .padding(3)
                            .overlay {
                                if profile.colorHex == hex {
                                    Circle().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
                                }
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex)
                    .accessibilityAddTraits(profile.colorHex == hex ? .isSelected : [])
                }
            }
        }

        // The time sits right next to the switch and appears as soon as it's on.
        LabeledContent {
            HStack(spacing: 10) {
                if profile.morningResetEnabled {
                    DatePicker("Time", selection: Binding(
                        get: { Self.date(minutes: profile.morningResetMinutes) },
                        set: { model.setMorningReset(enabled: true, minutes: Self.minutes(of: $0), for: profile) }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    #if os(macOS)
                    .datePickerStyle(.field)
                    #else
                    .datePickerStyle(.compact)
                    #endif
                    .fixedSize()
                    .transition(.opacity)
                }
                Toggle("Fresh start every morning", isOn: Binding(
                    get: { profile.morningResetEnabled },
                    set: { enabled in
                        withAnimation(.snappy(duration: 0.2)) {
                            model.setMorningReset(enabled: enabled, minutes: profile.morningResetMinutes, for: profile)
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fresh start every morning")
                Text(profile.morningResetEnabled
                     ? "Yesterday's note is archived at this time."
                     : "Archive yesterday's note each morning.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        if model.profiles.count > 1 {
            HStack {
                Spacer()
                Button("Delete Profile…", role: .destructive) {
                    confirmingDelete = true
                }
                .confirmationDialog(
                    "Delete “\(profile.name)” and its notes?",
                    isPresented: $confirmingDelete
                ) {
                    Button("Delete", role: .destructive) {
                        model.delete(profile)
                        didDelete()
                    }
                } message: {
                    Text("The note and its archive will be removed.")
                }
            }
        }
    }

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private static func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
