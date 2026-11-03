import PennsKit
import SwiftUI
import WatchKit

/// The note as one scrollable screen: tap a circle to tick it, dictate a new
/// line or a new note, archive when you're done.
struct WatchNoteView: View {
    @Bindable var model: WatchModel

    var body: some View {
        NavigationStack {
            if let page = model.page {
                note(page)
            } else {
                ContentUnavailableView(
                    "Open Penns on your iPhone",
                    systemImage: "iphone",
                    description: Text("Your note appears here once your iPhone sends it.")
                )
            }
        }
    }

    private func note(_ page: WatchSnapshot.Page) -> some View {
        List {
            if let expiresAt = page.expiresAt, !page.isBlank {
                Label {
                    Text(expiresAt, style: .relative)
                } icon: {
                    Image(systemName: "hourglass")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }

            if page.isBlank {
                Text("Nothing on your mind.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                row(line, in: page)
            }

            Section {
                TextFieldLink(prompt: Text("Add to note")) {
                    Label("Add", systemImage: "mic.fill")
                } onSubmit: { text in
                    model.send(.append(text: text, profileID: page.id))
                }

                if !page.isBlank {
                    TextFieldLink(prompt: Text("New note")) {
                        Label("New Note", systemImage: "square.and.pencil")
                    } onSubmit: { text in
                        model.send(.replace(text: text, profileID: page.id))
                    }

                    Button {
                        WKInterfaceDevice.current().play(.success)
                        model.send(.archive(profileID: page.id))
                    } label: {
                        Label("Archive", systemImage: page.allChecked ? "archivebox.fill" : "archivebox")
                    }
                    .listItemTint(page.allChecked ? Color.accentColor : nil)
                }
            }
        }
        .navigationTitle(model.pages.count > 1 ? page.name : "Penns")
        .toolbar {
            if model.pages.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        ProfilePicker(model: model)
                    } label: {
                        Circle()
                            .fill(ProfileColors.color(page.colorHex))
                            .frame(width: 12, height: 12)
                    }
                    .accessibilityLabel("Profiles")
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ line: Checklist.Line, in page: WatchSnapshot.Page) -> some View {
        switch line {
        case .text(let text):
            if let heading = Markdown.heading(of: text) {
                Text(InlineMarkup.attributed(heading.text))
                    .font(.headline)
                    .listRowBackground(Color.clear)
            } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(InlineMarkup.attributed(text.trimmingCharacters(in: .whitespaces)))
                    .listRowBackground(Color.clear)
            }
        case .item(let item):
            Button {
                WKInterfaceDevice.current().play(.click)
                model.send(.toggle(itemID: item.id, profileID: page.id))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .imageScale(.large)
                    Text(InlineMarkup.attributed(item.title))
                        .strikethrough(item.isChecked)
                        .opacity(item.isChecked ? 0.75 : 1)
                }
                .padding(.leading, CGFloat(item.indent) * 10)
            }
            .accessibilityAddTraits(item.isChecked ? .isSelected : [])
        }
    }
}

private struct ProfilePicker: View {
    @Bindable var model: WatchModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(model.pages) { page in
            Button {
                model.selectedID = page.id
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(ProfileColors.color(page.colorHex))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.name)
                        if !page.isBlank {
                            Text(page.firstLine)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("Profiles")
    }
}
