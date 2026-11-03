import Observation
import PennsKit
import SwiftData
import SwiftUI
import WidgetKit

/// Edits profiles directly in the shared store; the note panel reloads on change.
@MainActor
@Observable
final class ProfilesModel {
    private(set) var profiles: [Profile] = []
    @ObservationIgnored private var store = NoteStore(context: ModelContext(SharedContainer.shared))

    func reload() {
        store = NoteStore(context: ModelContext(SharedContainer.shared))
        profiles = store.profiles()
    }

    func add() {
        let profile = store.createProfile(name: "Profile \(profiles.count + 1)")
        _ = store.activeNote(in: profile)
        commit()
    }

    func rename(_ profile: Profile, to name: String) {
        profile.name = name
        commit()
    }

    func setColor(_ hex: String, for profile: Profile) {
        profile.colorHex = hex
        commit()
    }

    func setMorningReset(enabled: Bool, minutes: Int, for profile: Profile) {
        store.setMorningReset(enabled: enabled, minutes: minutes, for: profile)
        commit()
    }

    func delete(_ profile: Profile) {
        store.deleteProfile(profile)
        commit()
    }

    private func commit() {
        try? store.save()
        profiles = store.profiles()
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

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Circle()
                    .fill(ProfileColors.color(profile.colorHex))
                    .frame(width: 10, height: 10)
                Text(profile.name.isEmpty ? "Untitled" : profile.name)
                    .foregroundStyle(.primary)
                if profile.morningResetEnabled {
                    Image(systemName: "sunrise")
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

        Toggle("Fresh start every morning", isOn: Binding(
            get: { profile.morningResetEnabled },
            set: { model.setMorningReset(enabled: $0, minutes: profile.morningResetMinutes, for: profile) }
        ))

        if profile.morningResetEnabled {
            DatePicker("Archive yesterday's note at", selection: Binding(
                get: { Self.date(minutes: profile.morningResetMinutes) },
                set: { model.setMorningReset(enabled: true, minutes: Self.minutes(of: $0), for: profile) }
            ), displayedComponents: .hourAndMinute)
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
