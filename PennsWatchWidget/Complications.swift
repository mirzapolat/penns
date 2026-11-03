import PennsKit
import SwiftUI
import WidgetKit

@main
struct PennsWatchWidgets: WidgetBundle {
    var body: some Widget {
        NoteComplication()
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let page: WatchSnapshot.Page?
    let relevance: TimelineEntryRelevance?

    static var sample: ComplicationEntry {
        ComplicationEntry(
            date: .now,
            page: .init(id: UUID(), name: "Penns", colorHex: ProfileColors.all[0],
                        text: "Saturday\n- [x] Flowers\n- [ ] Candles", expiresAt: nil),
            relevance: nil
        )
    }
}

/// Reads the snapshot the watch app keeps in the App Group.
struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview ? .sample : entries(now: .now).first ?? .sample)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        completion(Timeline(entries: entries(now: .now), policy: .never))
    }

    /// Now, and the blank note the moment a lifespan ends.
    private func entries(now: Date) -> [ComplicationEntry] {
        let page = WatchSnapshot.load(from: ProfileSelection.defaults)?.current
        // Smart Stack: a note with something in it is worth showing.
        let relevance = TimelineEntryRelevance(score: page.map { $0.isBlank ? 0 : 50 } ?? 0)
        var entries = [ComplicationEntry(date: now, page: page, relevance: relevance)]
        if var cleared = page, let expiresAt = cleared.expiresAt, expiresAt > now {
            cleared.text = ""
            cleared.expiresAt = nil
            entries.append(ComplicationEntry(date: expiresAt, page: cleared, relevance: TimelineEntryRelevance(score: 0)))
        }
        return entries
    }
}

struct NoteComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NoteComplication", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "penns://note"))
        }
        .configurationDisplayName("Note")
        .description("The first lines of your note.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
    }
}

private struct ComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var page: WatchSnapshot.Page? { entry.page }
    private var firstLine: String {
        guard let page, !page.isBlank else { return "Penns" }
        return page.firstLine
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(firstLine)
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            Image(systemName: "note.text")
                .font(.title3)
                .widgetLabel(firstLine)
        default:
            rectangular
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let page, page.progress.total > 0 {
            Gauge(value: Double(page.progress.done), in: 0...Double(page.progress.total)) {
                Image(systemName: "checklist")
            } currentValueLabel: {
                Text("\(page.progress.done)/\(page.progress.total)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "note.text")
                    .font(.title3)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let page, !page.isBlank {
                ForEach(Array(LockScreenFold.visibleLines(of: page.text).enumerated()), id: \.offset) { _, line in
                    lineView(line)
                }
            } else {
                Text("Nothing on your mind.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetAccentable()
    }

    @ViewBuilder
    private func lineView(_ line: Checklist.Line) -> some View {
        switch line {
        case .text(let text):
            let heading = Markdown.heading(of: text)
            Text(InlineMarkup.attributed(heading?.text ?? text))
                .fontWeight(heading == nil ? .regular : .semibold)
                .lineLimit(1)
        case .item(let item):
            HStack(spacing: 4) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                Text(InlineMarkup.attributed(item.title))
                    .strikethrough(item.isChecked)
                    .lineLimit(1)
            }
        }
    }
}
