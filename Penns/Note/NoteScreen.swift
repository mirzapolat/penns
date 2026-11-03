import AppKit
import PennsKit
import SwiftUI

/// Everything inside the menu bar popover. The popover itself is Liquid Glass;
/// controls float above the note as glass capsules.
struct NoteScreen: View {
    @Bindable var model: NoteViewModel
    var openSettings: () -> Void
    var close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(NoteStyle.fontKey, store: ProfileSelection.defaults) private var fontValue = "system"
    @AppStorage(NoteStyle.sizeKey, store: ProfileSelection.defaults) private var fontSize = NoteStyle.defaultSize

    private var style: NoteStyle { NoteStyle(fontValue: fontValue, size: fontSize) }

    /// One margin for everything: text, pills and headers sit this far from every edge.
    static let margin: CGFloat = 16
    static let pillHeight: CGFloat = 30
    static let toolbarClearance: CGFloat = margin + pillHeight + 10

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.showingArchive {
                ArchiveView(model: model)
                    .transition(.opacity)
            } else {
                noteView
                    .transition(.opacity)
            }

            if let toast = model.toast {
                ToastView(toast: toast, perform: model.performToastAction)
                    .padding(.bottom, Self.toolbarClearance)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: model.toast?.id)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: model.showingArchive)
    }

    private var noteView: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                if model.isStale {
                    StalePrompt(keep: model.keepStale, archive: model.archive)
                        .padding(.horizontal, Self.margin)
                        .padding(.top, Self.margin)
                }

                ZStack(alignment: .topLeading) {
                    NoteEditor(
                        text: $model.text,
                        style: style,
                        focusToken: model.focusToken,
                        bottomInset: Self.toolbarClearance,
                        onEscape: close,
                        onTyping: model.noteTyping
                    )
                    if model.note.text.isEmpty {
                        Text(model.placeholder)
                            .font(style.swiftUIFont())
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
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
                .padding(.horizontal, Self.margin)
                .padding(.top, model.isStale ? 10 : Self.margin)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            BottomBar(model: model, openSettings: openSettings)
                .padding(.horizontal, Self.margin)
                .padding(.bottom, Self.margin)
                .opacity(model.controlsVisible ? 1 : 0)
                .onHover { hovering in
                    if hovering { model.showControls() }
                }
        }
    }
}

private struct BottomBar: View {
    @Bindable var model: NoteViewModel
    var openSettings: () -> Void
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if model.hasMultipleProfiles {
                    ProfileMenu(model: model)
                }
                if !model.note.isBlank {
                    LifespanMenu(model: model)
                }

                Spacer(minLength: 0)

                // When every checklist item is ticked, archiving is the obvious next
                // step: the archive button grows into a tinted "Archive" pill.
                if model.allChecked {
                    Button(action: model.archive) {
                        HStack(spacing: 6) {
                            Image(systemName: "archivebox.fill")
                            Text("Archive")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: NoteScreen.pillHeight)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .layoutPriority(2)
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
                    .glassEffectID("archive", in: glass)
                    .help("All done — archive this note (⇧⌘A)")
                }

                HStack(spacing: 0) {
                    if !model.allChecked {
                        ToolbarIcon(systemName: "archivebox", help: "Archive note (⇧⌘A)", action: model.archive)
                            .keyboardShortcut("a", modifiers: [.command, .shift])
                            .disabled(model.note.isBlank)
                            .glassEffectID("archive", in: glass)
                    }
                    ShareLink(item: model.shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 32, height: NoteScreen.pillHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.note.isBlank ? .tertiary : .primary)
                    .disabled(model.note.isBlank)
                    .help("Share note")
                    .accessibilityLabel("Share note")

                    ToolbarIcon(systemName: "clock.arrow.circlepath", help: "Archive (⌘Y)") {
                        model.showingArchive = true
                    }
                    .keyboardShortcut("y", modifiers: .command)

                    Menu {
                        Button("Delete Note", role: .destructive, action: model.deleteNote)
                            .disabled(model.note.isBlank)
                        Divider()
                        Button(model.hasMultipleProfiles ? "Profiles…" : "New Profile…", action: openSettings)
                        Button("Settings…", action: openSettings)
                        Button("Quit Penns") { NSApp.terminate(nil) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 32, height: NoteScreen.pillHeight)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More")
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
        .background {
            // Keyboard-only shortcuts, kept out of the row so they add no spacing:
            // ⌥⌘⌫ deletes the note, ⌘1…⌘9 switch profiles.
            ZStack {
                Button("Delete Note", action: model.deleteNote)
                    .keyboardShortcut(.delete, modifiers: [.command, .option])
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
}

private struct ProfileMenu: View {
    @Bindable var model: NoteViewModel

    var body: some View {
        Menu {
            ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                Button {
                    model.switchProfile(to: profile)
                } label: {
                    if profile.id == model.profile.id {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
                .keyboardShortcut(index < 9 ? KeyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command) : nil)
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(ProfileColors.color(model.profile.colorHex))
                    .frame(width: 7, height: 7)
                Text(model.profile.name)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: NoteScreen.pillHeight)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("Switch profile (⌘1…⌘9)")
    }
}

private struct LifespanMenu: View {
    @Bindable var model: NoteViewModel
    @State private var pickingCustom = false

    var body: some View {
        Menu {
            ForEach(Lifespan.presets, id: \.self) { lifespan in
                Button {
                    model.setLifespan(lifespan)
                } label: {
                    if model.note.lifespan == lifespan {
                        Label(lifespan.title, systemImage: "checkmark")
                    } else {
                        Text(lifespan.title)
                    }
                }
            }
            Divider()
            Button {
                pickingCustom = true
            } label: {
                if model.note.lifespan == .custom {
                    Label("Custom…", systemImage: "checkmark")
                } else {
                    Text("Custom…")
                }
            }
        } label: {
            // Full label when there's room, just the hourglass when the bar is busy.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    Image(systemName: "hourglass")
                    Text(model.lifespanChipText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                Image(systemName: "hourglass")
                    .frame(width: NoteScreen.pillHeight)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(height: NoteScreen.pillHeight)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .layoutPriority(0)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("How long this note lives: \(model.lifespanChipText)")
        .popover(isPresented: $pickingCustom, arrowEdge: .top) {
            CustomExpiryPicker(initial: model.note.expiresAt) { date in
                model.setExpiry(date)
            }
        }
    }
}

/// The native macOS date and time picker. Changes apply as you pick;
/// click outside to dismiss.
private struct CustomExpiryPicker: View {
    var set: (Date) -> Void
    @State private var date: Date

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
        DatePicker(
            "Expires",
            selection: $date,
            in: Date.now...,
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .padding(12)
        .onAppear { set(date) }
        .onChange(of: date) { _, newValue in set(newValue) }
    }
}

private struct ToolbarIcon: View {
    let systemName: String
    let help: String
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: NoteScreen.pillHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct StalePrompt: View {
    var keep: () -> Void
    var archive: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Still relevant?")
                .foregroundStyle(.secondary)
            Button("Keep", action: keep)
            Button("Archive", action: archive)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 26)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToastView: View {
    let toast: Toast
    var perform: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(toast.message)
                .foregroundStyle(.secondary)
            if let title = toast.actionTitle {
                Button(title, action: perform)
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .keyboardShortcut("z", modifiers: [.command, .shift, .option])
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: NoteScreen.pillHeight)
        .glassEffect(.regular, in: .capsule)
    }
}
