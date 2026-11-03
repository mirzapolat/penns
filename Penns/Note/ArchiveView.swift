import PennsKit
import SwiftUI

struct ArchiveView: View {
    @Bindable var model: NoteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    model.showingArchive = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .keyboardShortcut(.cancelAction)
                .help("Back to note")
                .accessibilityLabel("Back to note")

                Text("Archive")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(clearedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, NoteScreen.margin)
            .padding(.top, NoteScreen.margin)
            .padding(.bottom, 8)

            if model.archived.isEmpty {
                Spacer()
                Text("Nothing archived yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.archived) { note in
                            ArchiveRow(
                                note: note,
                                restore: { model.restore(note) },
                                delete: { model.deleteArchived(note) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private var clearedText: String {
        model.clearedCount == 1 ? "1 note cleared" : "\(model.clearedCount) notes cleared"
    }
}

private struct ArchiveRow: View {
    let note: Note
    var restore: () -> Void
    var delete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Checklist.displayText(note.text).trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(NoteTypography.font)
                    .lineLimit(2)
                Text((note.archivedAt ?? note.updatedAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                rowButton("arrow.uturn.backward", help: "Restore", action: restore)
                rowButton("trash", help: "Delete forever", action: delete)
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: restore)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Restore", restore)
        .accessibilityAction(named: "Delete", delete)
    }

    private func rowButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
