import PennsKit
import SwiftUI
import UIKit
import WidgetKit

/// Text, Lock Screen, profiles and widgets, in one native form.
struct SettingsView: View {
    @AppStorage(NoteStyle.fontKey, store: ProfileSelection.defaults) private var fontValue = "system"
    @AppStorage(NoteStyle.sizeKey, store: ProfileSelection.defaults) private var fontSize = NoteStyle.defaultSize
    @AppStorage(IOSPrefs.showsFoldLine) private var showsFoldLine = true
    @AppStorage(IOSPrefs.didShowWelcome) private var didShowWelcome = true
    @AppStorage(LiveController.autoRenewKey) private var liveAutoRenew = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    // The four system styles (plus a chosen family); every
                    // other installed font is in "More Fonts…".
                    Picker("Font", selection: $fontValue) {
                        ForEach(NoteFont.builtIn, id: \.self) { font in
                            Text(font.displayName)
                                .font(NoteStyle(font: font, size: 17).swiftUIFont())
                                .tag(font.storageValue)
                        }
                        if case .family(let family) = NoteFont(storageValue: fontValue) {
                            Text(family)
                                .font(.custom(family, size: 17))
                                .tag(fontValue)
                        }
                    }
                    .pickerStyle(.menu)
                    NavigationLink("More Fonts…") {
                        FontList(selection: $fontValue)
                            .navigationTitle("Fonts")
                            .navigationBarTitleDisplayMode(.inline)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "textformat.size.smaller")
                            .foregroundStyle(.secondary)
                        Slider(value: $fontSize, in: NoteStyle.sizeRange, step: 1)
                        Image(systemName: "textformat.size.larger")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Size")
                    .accessibilityValue("\(Int(fontSize)) points")

                    Text("One note, always one glance away.")
                        .font(NoteStyle(fontValue: fontValue, size: fontSize).swiftUIFont())
                        .padding(.vertical, 4)
                        .accessibilityLabel("Preview")
                }

                Section {
                    Toggle("Show Lock Screen line", isOn: $showsFoldLine)
                } footer: {
                    Text("A faint line in the note marks where the Lock Screen widget stops.")
                }

                if LiveNote.isAvailable {
                    Section {
                        Toggle("Renew automatically", isOn: $liveAutoRenew)
                    } header: {
                        Text("Live Activity")
                    } footer: {
                        Text("Go Live puts your note across the Lock Screen. iOS ends Live Activities after 8 hours; Penns starts a fresh one whenever you open it. To go live every morning: Shortcuts → Automation → Time of Day → Go Live.")
                    }
                }

                ProfilesSection()

                Section {
                    NavigationLink("Add a Widget") { WidgetGuide() }
                    Button("Show Welcome") {
                        dismiss()
                        didShowWelcome = false
                    }
                } footer: {
                    Text("Penns \(Bundle.main.shortVersion)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                }
            }
        }
        .onChange(of: fontValue) { WidgetCenter.shared.reloadAllTimelines() }
        .onChange(of: fontSize) { WidgetCenter.shared.reloadAllTimelines() }
    }
}

/// iOS can't add widgets for you, so this shows where they live.
struct WidgetGuide: View {
    var body: some View {
        List {
            Section("Home Screen") {
                step(1, "Touch and hold an empty spot until the apps jiggle.")
                step(2, "Tap **Edit**, then **Add Widget**.")
                step(3, "Search for **Penns** and pick a size.")
            }
            Section("Lock Screen") {
                step(1, "Touch and hold the Lock Screen, then tap **Customize**.")
                step(2, "Tap the area below the clock.")
                step(3, "Choose **Penns** — the first lines of your note.")
            }
            Section {
                step(1, "In the note, tap **…** → **Go Live**.")
                step(2, "Or add **Penns Live** to Control Center or the Action Button.")
            } header: {
                Text("Full width on the Lock Screen")
            } footer: {
                Text("A Live Activity shows your note across the whole Lock Screen and in the Dynamic Island, with circles you can tick.")
            }
        }
        .navigationTitle("Add a Widget")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
            Text(text)
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }
}
