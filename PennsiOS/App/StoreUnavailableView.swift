import SwiftUI

/// Shown instead of the note when the store on disk couldn't be opened.
/// Typing into an empty in-memory note would be lost, so there's no editor.
struct StoreUnavailableView: View {
    let details: String

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Open Your Note", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Your note is still on this device; nothing was changed or deleted. Close Penns completely and open it again.")
        } actions: {
            Text(details)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(16)
    }
}
