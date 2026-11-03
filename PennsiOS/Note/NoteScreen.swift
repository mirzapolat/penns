import PennsKit
import SwiftUI

/// The whole app: one note, edge to edge, with controls floating above it as
/// Liquid Glass pills, the same as the Mac panel.
struct NoteScreen: View {
    @Bindable var model: NoteViewModel
    @State private var showingSettings = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(NoteStyle.fontKey, store: ProfileSelection.defaults) private var fontValue = "system"
    @AppStorage(NoteStyle.sizeKey, store: ProfileSelection.defaults) private var fontSize = NoteStyle.defaultSize
    @AppStorage(IOSPrefs.showsFoldLine) private var showsFoldLine = true

    private var style: NoteStyle { NoteStyle(fontValue: fontValue, size: fontSize) }

    /// One margin for everything: text, pills and toasts sit this far from the edges.
    static let margin: CGFloat = 16
    static let pillHeight: CGFloat = 44
    static let toolbarClearance: CGFloat = margin + pillHeight + 16
    /// Comfortable line length on iPad and in landscape.
    static let readableWidth: CGFloat = 680

    var body: some View {
        GeometryReader { proxy in
            let side = max(Self.margin, (proxy.size.width - Self.readableWidth) / 2)
            ZStack(alignment: .bottom) {
                noteView(side: side)

                VStack(spacing: 10) {
                    if let toast = model.toast {
                        ToastView(toast: toast, perform: model.performToastAction)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 8)))
                    }
                    BottomBar(model: model, openSettings: { showingSettings = true })
                        .opacity(model.controlsVisible ? 1 : 0)
                        .allowsHitTesting(model.controlsVisible)
                }
                .padding(.horizontal, side)
                .padding(.bottom, Self.margin)
            }
        }
        .background(Color(.systemBackground))
        .animation(.spring(duration: 0.3, bounce: 0.2), value: model.toast?.id)
        .sheet(isPresented: $model.showingArchive) {
            ArchiveSheet(model: model)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .background { HardwareKeyboardShortcuts(model: model, openSettings: { showingSettings = true }) }
    }

    private func noteView(side: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.isStale {
                StalePrompt(keep: model.keepStale, archive: model.archive)
                    .padding(.horizontal, side)
                    .padding(.top, 8)
            }

            ZStack(alignment: .topLeading) {
                NoteEditor(
                    text: $model.text,
                    style: style,
                    focusToken: model.focusToken,
                    showsFoldLine: showsFoldLine,
                    insets: UIEdgeInsets(
                        top: model.isStale ? 10 : Self.margin,
                        left: side,
                        bottom: Self.toolbarClearance,
                        right: side
                    ),
                    onPullDown: { model.showingArchive = true },
                    onTyping: model.noteTyping,
                    formatBridge: model.formatBridge
                )
                if model.note.text.isEmpty {
                    Text(model.placeholder)
                        .font(style.swiftUIFont())
                        .foregroundStyle(.tertiary)
                        .padding(.top, model.isStale ? 10 : Self.margin)
                        .padding(.leading, side)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .id(model.note.id)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .simultaneousGesture(TapGesture().onEnded { model.showControls() })
    }
}

enum IOSPrefs {
    static let showsFoldLine = "showsLockScreenFoldLine"
    static let didShowWelcome = "didShowWelcome"
}

// MARK: - Bottom bar

private struct BottomBar: View {
    @Bindable var model: NoteViewModel
    var openSettings: () -> Void
    @Namespace private var glass
    @Environment(LiveController.self) private var live

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if model.hasMultipleProfiles {
                    ProfileMenu(model: model)
                }
                if !model.note.isBlank {
                    LifespanMenu(model: model)
                }

                Spacer(minLength: 0)

                // When every checklist item is ticked, the archive button grows into
                // a tinted "Archive" pill: the obvious next step, nothing extra.
                if model.allChecked {
                    Button(action: archive) {
                        Label("Archive", systemImage: "archivebox.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .frame(height: NoteScreen.pillHeight)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .layoutPriority(2)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                    .glassEffectID("archive", in: glass)
                    .accessibilityHint("Every item is done")
                }

                HStack(spacing: 0) {
                    FormatMenu(model: model)
                    if !model.allChecked {
                        ToolbarIcon(systemName: "archivebox", label: "Archive note", action: archive)
                            .disabled(model.note.isBlank)
                            .glassEffectID("archive", in: glass)
                    }
                    ShareLink(item: model.shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17))
                            .frame(width: 44, height: NoteScreen.pillHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.note.isBlank ? .tertiary : .primary)
                    .disabled(model.note.isBlank)
                    .accessibilityLabel("Share note")

                    Menu {
                        if live.isAvailable {
                            if live.isLive(model.profile.id) {
                                Button("End Live Activity", systemImage: "rectangle.slash") { live.end(model) }
                            } else {
                                Button("Go Live", systemImage: "rectangle.inset.topleft.filled") { live.goLive(model) }
                                    .disabled(model.note.isBlank)
                            }
                            Divider()
                        }
                        Button("Show Archive", systemImage: "clock.arrow.circlepath") {
                            model.showingArchive = true
                        }
                        Button("Settings", systemImage: "gearshape", action: openSettings)
                        Button(
                            model.hasMultipleProfiles ? "Profiles" : "New Profile",
                            systemImage: "person.2",
                            action: openSettings
                        )
                        Divider()
                        Button("Delete Note", systemImage: "trash", role: .destructive, action: model.deleteNote)
                            .disabled(model.note.isBlank)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17))
                            .frame(width: 44, height: NoteScreen.pillHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More")
                }
                .padding(.horizontal, 4)
                .frame(height: NoteScreen.pillHeight)
                .fixedSize()
                .layoutPriority(2)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("tools", in: glass)
            }
            .animation(.spring(duration: 0.4, bounce: 0.25), value: model.allChecked)
        }
        .foregroundStyle(.primary)
    }

    private func archive() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        model.archive()
    }
}

/// "Aa": the same formats as the edit menu and the keyboard shortcuts.
private struct FormatMenu: View {
    let model: NoteViewModel

    var body: some View {
        Menu {
            ControlGroup {
                ForEach(TextFormat.styles, id: \.self) { format in
                    Button(format.title, systemImage: format.systemImage) { model.format(format) }
                }
            }
            .controlGroupStyle(.compactMenu)
            Section {
                ForEach(TextFormat.lists, id: \.self) { format in
                    Button(format.title, systemImage: format.systemImage) { model.format(format) }
                }
            }
        } label: {
            Image(systemName: "textformat")
                .font(.system(size: 17))
                .frame(width: 44, height: NoteScreen.pillHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Format")
    }
}

private struct ProfileMenu: View {
    @Bindable var model: NoteViewModel

    var body: some View {
        Menu {
            Picker("Profile", selection: Binding(
                get: { model.profile.id },
                set: { id in
                    if let profile = model.profiles.first(where: { $0.id == id }) {
                        model.switchProfile(to: profile)
                    }
                }
            )) {
                ForEach(model.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
        } label: {
            // Full name when there's room, only the colored dot when the bar is busy.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    dot
                    Text(model.profile.name)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                dot.frame(width: NoteScreen.pillHeight)
            }
            .font(.system(size: 15, weight: .medium))
            .frame(height: NoteScreen.pillHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Profile: \(model.profile.name)")
    }

    private var dot: some View {
        Circle()
            .fill(ProfileColors.color(model.profile.colorHex))
            .frame(width: 9, height: 9)
    }
}

private struct LifespanMenu: View {
    @Bindable var model: NoteViewModel
    @State private var pickingCustom = false

    var body: some View {
        Menu {
            Picker("Lifespan", selection: Binding(
                get: { model.note.lifespan },
                set: { lifespan in
                    if lifespan == .custom {
                        pickingCustom = true
                    } else {
                        model.setLifespan(lifespan)
                    }
                }
            )) {
                ForEach(Lifespan.presets, id: \.self) { lifespan in
                    Text(lifespan.title).tag(lifespan)
                }
                Text("Custom…").tag(Lifespan.custom)
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                    Text(model.lifespanChipText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                Image(systemName: "hourglass")
                    .frame(width: NoteScreen.pillHeight)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(height: NoteScreen.pillHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .layoutPriority(0)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Lifespan: \(model.lifespanChipText)")
        .sheet(isPresented: $pickingCustom) {
            CustomExpirySheet(initial: model.note.expiresAt) { model.setExpiry($0) }
        }
    }
}

/// The native date and time picker, in a small sheet.
private struct CustomExpirySheet: View {
    var set: (Date) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(initial: Date?, set: @escaping (Date) -> Void) {
        self.set = set
        let fallback = Calendar.current.nextDate(
            after: .now.addingTimeInterval(3600),
            matching: DateComponents(minute: 0),
            matchingPolicy: .nextTime
        ) ?? .now.addingTimeInterval(3600)
        _date = State(initialValue: max(initial ?? fallback, .now.addingTimeInterval(60)))
    }

    var body: some View {
        NavigationStack {
            DatePicker("Expires", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, NoteScreen.margin)
                .navigationTitle("Archive at")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Set", role: .confirm) {
                            set(date)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ToolbarIcon: View {
    let systemName: String
    let label: String
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17))
                .frame(width: 44, height: NoteScreen.pillHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
        .accessibilityLabel(label)
    }
}

private struct StalePrompt: View {
    var keep: () -> Void
    var archive: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("Still relevant?")
                .foregroundStyle(.secondary)
            Button("Keep", action: keep)
            Button("Archive", action: archive)
        }
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 16)
        .frame(height: 36)
        .glassEffect(.regular.interactive(), in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToastView: View {
    let toast: Toast
    var perform: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .foregroundStyle(.secondary)
            if let title = toast.actionTitle {
                Button(title, action: perform)
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 18)
        .frame(height: NoteScreen.pillHeight)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// Hardware-keyboard shortcuts (iPad), kept invisible and out of the layout.
private struct HardwareKeyboardShortcuts: View {
    let model: NoteViewModel
    var openSettings: () -> Void
    @Environment(LiveController.self) private var live

    var body: some View {
        ZStack {
            Button("Archive Note", action: model.archive)
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Show Archive") { model.showingArchive = true }
                .keyboardShortcut("y", modifiers: .command)
            Button("Delete Note", action: model.deleteNote)
                .keyboardShortcut(.delete, modifiers: [.command, .option])
            Button("Settings", action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
            Button("Go Live") {
                if live.isLive(model.profile.id) { live.end(model) } else { live.goLive(model) }
            }
            .keyboardShortcut("l", modifiers: .command)
            ForEach(0..<min(model.profiles.count, 9), id: \.self) { index in
                Button("Profile \(index + 1)") { model.switchProfile(at: index) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
