#if os(iOS)
import ActivityKit
import AppIntents
import PennsKit
import SwiftUI
import WidgetKit

/// The note across the whole Lock Screen, and in the Dynamic Island.
struct NoteLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NoteActivityAttributes.self) { context in
            LiveBanner(state: context.state, profileID: context.attributes.profileID)
                .padding(16)
                .activitySystemActionForegroundColor(.primary)
                .widgetURL(URL(string: "penns://note"))
        } dynamicIsland: { context in
            let state = context.state
            let profileID = context.attributes.profileID
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ProfileColors.color(state.profileColor))
                            .frame(width: 7, height: 7)
                        Text(state.showsProfile ? state.profileName : "Penns")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveStatus(state: state)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        LiveLines(state: state, profileID: profileID, maxLines: 4, size: 15)
                        if state.allChecked {
                            LiveArchiveButton(profileID: profileID)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Image(systemName: state.allChecked ? "checkmark.circle.fill" : "note.text")
                    .foregroundStyle(ProfileColors.color(state.profileColor))
            } compactTrailing: {
                LiveStatus(state: state)
                    .frame(maxWidth: 72)
            } minimal: {
                Image(systemName: state.allChecked ? "checkmark.circle.fill" : "note.text")
                    .foregroundStyle(ProfileColors.color(state.profileColor))
            }
            .widgetURL(URL(string: "penns://note"))
        }
    }
}

/// Lock Screen: the first lines, full width, with tappable circles.
private struct LiveBanner: View {
    let state: NoteActivityAttributes.ContentState
    let profileID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LiveLines(state: state, profileID: profileID, maxLines: 5, size: min(NoteStyle.current.size, 16))
            if state.allChecked || state.showsProfile || state.expiresAt != nil {
                HStack(spacing: 8) {
                    if state.showsProfile {
                        Circle()
                            .fill(ProfileColors.color(state.profileColor))
                            .frame(width: 6, height: 6)
                        Text(state.profileName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let expiresAt = state.expiresAt {
                        Label {
                            Text(expiresAt, style: .relative)
                        } icon: {
                            Image(systemName: "hourglass")
                        }
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if state.allChecked {
                        LiveArchiveButton(profileID: profileID)
                    }
                }
                .font(.caption.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The note's lines: text, headings and checklist items with circles.
private struct LiveLines: View {
    let state: NoteActivityAttributes.ContentState
    let profileID: UUID
    let maxLines: Int
    let size: CGFloat

    var body: some View {
        let lines = state.lines
        VStack(alignment: .leading, spacing: 4) {
            if state.isEmpty {
                Text("Nothing on your mind.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(lines.prefix(maxLines).enumerated()), id: \.offset) { _, line in
                row(line)
            }
            if lines.count > maxLines {
                Text("+ \(lines.count - maxLines) more")
                    .font(.system(size: size - 3))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(NoteStyle(font: NoteStyle.current.font, size: size).swiftUIFont())
    }

    @ViewBuilder
    private func row(_ line: Checklist.Line) -> some View {
        switch line {
        case .text(let text):
            if let heading = Markdown.heading(of: text) {
                Text(InlineMarkup.attributed(heading.text))
                    .fontWeight(.semibold)
                    .lineLimit(1)
            } else {
                Text(InlineMarkup.attributed(text.isEmpty ? " " : text.replacingOccurrences(of: "\t", with: "    ")))
                    .lineLimit(1)
            }
        case .item(let item):
            Button(intent: LiveToggleItemIntent(itemID: item.id, profileID: profileID)) {
                HStack(spacing: 8) {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text(InlineMarkup.attributed(item.title))
                        .strikethrough(item.isChecked)
                        .opacity(item.isChecked ? 0.75 : 1)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(item.indent) * 14)
        }
    }
}

/// "2/5" for checklists, otherwise the time left, otherwise nothing.
private struct LiveStatus: View {
    let state: NoteActivityAttributes.ContentState

    var body: some View {
        let progress = state.progress
        if progress.total > 0 {
            Text("\(progress.done)/\(progress.total)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(state.allChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        } else if let expiresAt = state.expiresAt {
            Text(timerInterval: Date.now...max(expiresAt, .now), countsDown: true)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LiveArchiveButton: View {
    let profileID: UUID

    var body: some View {
        Button(intent: LiveArchiveIntent(profileID: profileID)) {
            Label("Archive", systemImage: "archivebox.fill")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.glassProminent)
        .controlSize(.small)
    }
}

/// Control Center, the Lock Screen and the Action Button: put the note on the Lock Screen.
struct GoLiveControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mirzapolat.penns.golive") {
            ControlWidgetButton(action: GoLiveIntent()) {
                Label("Go Live", systemImage: "note.text")
            }
        }
        .displayName("Penns Live")
        .description("Shows your note on the Lock Screen and in the Dynamic Island.")
    }
}
#endif
