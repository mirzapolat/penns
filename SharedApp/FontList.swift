import PennsKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Every installed font family, searchable, each shown in its own face.
/// Settings keeps the main picker short (the four system styles) and opens
/// this only when asked, so a long font list never slows Settings down.
struct FontList: View {
    @Binding var selection: String
    var done: (() -> Void)?
    @State private var query = ""
    @State private var families: [String] = []

    static var installedFamilies: [String] {
        #if os(macOS)
        NSFontManager.shared.availableFontFamilies.sorted()
        #else
        UIFont.familyNames.sorted()
        #endif
    }

    private var filtered: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return families }
        return families.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List(filtered, id: \.self) { family in
            let value = NoteFont.family(family).storageValue
            Button {
                selection = value
                done?()
            } label: {
                HStack {
                    Text(family)
                        .font(.custom(family, size: 16))
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection == value {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == value ? .isSelected : [])
        }
        .searchable(text: $query, prompt: "Search fonts")
        .overlay {
            if families.isEmpty {
                ProgressView()
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task {
            // Loaded once, after the list is on screen.
            if families.isEmpty { families = Self.installedFamilies }
        }
    }
}
