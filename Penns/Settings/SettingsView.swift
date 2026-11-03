import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// One sheet: general, profiles, widget.
struct SettingsView: View {
    @AppStorage(Prefs.titleMode) private var titleMode: MenuBarTitleMode = .icon
    @AppStorage(Prefs.showInDock) private var showInDock = false
    @AppStorage(Prefs.menuBarIcon) private var menuBarIcon = MenuBarIcon.all[0]
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showWidgetGuide = false

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open note", name: .toggleNote)
                Picker("Menu bar shows", selection: $titleMode) {
                    ForEach(MenuBarTitleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if titleMode != .textOnly {
                    LabeledContent("Icon") {
                        IconPicker(selection: $menuBarIcon)
                    }
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                Toggle("Show in Dock", isOn: $showInDock)
            }
            ProfilesSection()
            Section {
                LabeledContent("Desktop widget") {
                    Button(showWidgetGuide ? "Hide" : "How to add…") {
                        withAnimation { showWidgetGuide.toggle() }
                    }
                }
                if showWidgetGuide {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Right-click the desktop and choose **Edit Widgets…**")
                        Text("2. Search for **Penns**.")
                        Text("3. Drag the **Note** widget onto your desktop or into Notification Center.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } footer: {
                HStack {
                    Text("Penns \(Bundle.main.shortVersion)")
                    Spacer()
                    Button("Show Welcome") {
                        NSApp.sendAction(#selector(AppDelegate.showWelcome), to: nil, from: nil)
                    }
                    Button("Quit Penns") { NSApp.terminate(nil) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .frame(minHeight: 420)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }
}

private struct IconPicker: View {
    @Binding var selection: String

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 6), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(MenuBarIcon.all, id: \.self) { name in
                Button {
                    selection = name
                } label: {
                    Image(systemName: name)
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selection == name ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(selection == name ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(name)
                .accessibilityLabel(name)
                .accessibilityAddTraits(selection == name ? .isSelected : [])
            }
        }
        .fixedSize()
    }
}
