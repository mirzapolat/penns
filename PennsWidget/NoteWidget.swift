import AppIntents
import PennsKit
import SwiftData
import SwiftUI
import WidgetKit

struct NoteEntry: TimelineEntry, Sendable {
    let date: Date
    let text: String
    let expiresAt: Date?
    var profileID: UUID? = nil
    var profileName: String = ""
    var profileColor: String = ProfileColors.all[0]
    /// Show the profile dot and name (only when there are several profiles).
    var showsProfile = false

    var lines: [Checklist.Line] { Checklist.parse(text.trimmingCharacters(in: .newlines)) }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var allChecked: Bool { Checklist.allChecked(text) }

    func cleared(at date: Date) -> NoteEntry {
        var entry = self
        entry = NoteEntry(date: date, text: "", expiresAt: nil, profileID: profileID,
                          profileName: profileName, profileColor: profileColor, showsProfile: showsProfile)
        return entry
    }

    static let sample = NoteEntry(
        date: .now,
        text: "Call the bakery about Saturday\n- [x] Flowers\n- [ ] Candles",
        expiresAt: nil
    )
}

/// Pick a profile per widget, or follow the one currently shown.
struct NoteWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Note"
    static let description = IntentDescription("Choose which profile's note this widget shows.")

    @Parameter(title: "Profile", description: "Leave empty to follow the profile currently shown.")
    var profile: ProfileEntity?

    init() {}
}

struct NoteProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NoteEntry { .sample }

    func snapshot(for configuration: NoteWidgetIntent, in context: Context) async -> NoteEntry {
        context.isPreview ? .sample : Self.loadEntry(profileID: configuration.profile?.id, now: .now).entry
    }

    func timeline(for configuration: NoteWidgetIntent, in context: Context) async -> Timeline<NoteEntry> {
        let now = Date.now
        let (entry, clearing) = Self.loadEntry(profileID: configuration.profile?.id, now: now)
        guard let clearing else {
            return Timeline(entries: [entry], policy: .never)
        }
        // Show the blank state the moment a lifespan ends or the morning reset
        // runs, even if Penns isn't running.
        return Timeline(entries: [entry, entry.cleared(at: clearing)], policy: .after(clearing))
    }

    /// Reads the note synchronously with a context owned by this call.
    static func loadEntry(profileID: UUID?, now: Date) -> (entry: NoteEntry, clearing: Date?) {
        let store = NoteStore(context: ModelContext(SharedContainer.shared))
        store.applyDueTransitions()
        let profile = profileID.flatMap { store.profile(id: $0) }
            ?? store.currentProfile(preferredID: ProfileSelection.preferredID)
        let note = store.activeNote(in: profile)
        let clearing = store.nextClearing(for: profile)
        let multiple = store.profiles().count > 1
        try? store.save()
        let entry = NoteEntry(
            date: now,
            text: note.text,
            expiresAt: note.expiresAt,
            profileID: profile.id,
            profileName: profile.name,
            profileColor: profile.colorHex,
            showsProfile: multiple
        )
        return (entry, clearing)
    }
}

struct NoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NoteWidget", intent: NoteWidgetIntent.self, provider: NoteProvider()) { entry in
            NoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Note")
        .description("Your note, always in sight.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct NoteWidgetView: View {
    let entry: NoteEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.isEmpty {
                Text("Tap to write")
                    .font(.system(size: textSize))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(entry.lines.prefix(maxLines).enumerated()), id: \.offset) { _, line in
                        lineView(line)
                    }
                }
            }

            Spacer(minLength: 0)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "penns://note"))
    }

    @ViewBuilder
    private func lineView(_ line: Checklist.Line) -> some View {
        switch line {
        case .text(let text):
            if let heading = Markdown.heading(of: text) {
                Text(heading.text)
                    .font(.system(
                        size: textSize + [4, 2, 0][heading.level - 1],
                        weight: heading.level == 3 ? .semibold : .bold
                    ))
                    .foregroundStyle(.primary)
                    .widgetAccentable()
            } else {
                Text(text.isEmpty ? " " : text.replacingOccurrences(of: "\t", with: "    "))
                    .font(.system(size: textSize))
                    .foregroundStyle(.primary)
                    .widgetAccentable()
            }
        case .item(let item):
            Button(intent: ToggleChecklistItemIntent(itemID: item.id, profileID: entry.profileID)) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: textSize + 1))
                        .foregroundStyle(item.isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .widgetAccentable()
                    Text(item.title)
                        .font(.system(size: textSize))
                        .strikethrough(item.isChecked)
                        .foregroundStyle(.primary)
                        .opacity(item.isChecked ? 0.8 : 1)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(item.indent) * 14)
        }
    }

    @ViewBuilder
    private var footer: some View {
        let label = entry.expiresAt.map { Lifecycle.expiryLabel($0, now: entry.date) }
        if entry.allChecked || label != nil || entry.showsProfile {
            HStack(spacing: 6) {
                if entry.showsProfile, !entry.allChecked {
                    Circle()
                        .fill(ProfileColors.color(entry.profileColor))
                        .frame(width: 6, height: 6)
                    Text(entry.profileName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if entry.allChecked {
                    Button(intent: ArchiveNoteIntent(profile: entry.profileID.map { ProfileEntity(id: $0, name: entry.profileName) })) {
                        Label("Archive", systemImage: "archivebox.fill")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.mini)
                }
                Spacer(minLength: 0)
                if let label {
                    Label(label, systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.top, 6)
        }
    }

    /// One text size per widget family; no headings.
    private var textSize: CGFloat { family == .systemSmall ? 13 : 14 }

    private var maxLines: Int {
        switch family {
        case .systemSmall: 6
        case .systemMedium: 5
        default: 14
        }
    }
}

#Preview(as: .systemMedium) {
    NoteWidget()
} timeline: {
    NoteEntry.sample
    NoteEntry(date: .now, text: "", expiresAt: nil)
}
