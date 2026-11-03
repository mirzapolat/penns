import PennsKit
import SwiftUI

/// Notes you let go of. Tap one to bring it back; swipe to restore or delete.
struct ArchiveSheet: View {
    @Bindable var model: NoteViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.archived.isEmpty {
                    ContentUnavailableView(
                        "Nothing archived yet",
                        systemImage: "archivebox",
                        description: Text("Archived and expired notes wait here.")
                    )
                } else {
                    List {
                        ForEach(model.archived) { note in
                            Button {
                                model.restore(note)
                            } label: {
                                ArchiveRow(note: note)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                Button("Restore", systemImage: "arrow.uturn.backward") { model.restore(note) }
                                    .tint(.accentColor)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    withAnimation { model.deleteArchived(note) }
                                }
                            }
                            .contextMenu {
                                Button("Restore", systemImage: "arrow.uturn.backward") { model.restore(note) }
                                ShareLink(item: Checklist.displayText(note.text))
                                Divider()
                                Button("Delete Forever", systemImage: "trash", role: .destructive) {
                                    model.deleteArchived(note)
                                }
                            }
                            .accessibilityHint("Restores this note")
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Archive")
            .navigationSubtitle(clearedText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var clearedText: String {
        model.clearedCount == 1 ? "1 note cleared" : "\(model.clearedCount) notes cleared"
    }
}

private struct ArchiveRow: View {
    let note: Note

    /// Everything after the first line, as clean text (○ / ✓ for checklists).
    private var preview: String {
        let lines = Checklist.displayText(note.text)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.dropFirst().joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.firstLine)
                .font(NoteStyle.current.swiftUIFont(weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if !preview.isEmpty {
                Text(preview)
                    .font(NoteTypography.font)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text((note.archivedAt ?? note.updatedAt).formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
