import Observation
import PennsKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// Share → Penns: adds the shared text or link as a new line at the end of the note.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

@MainActor
@Observable
final class ShareModel {
    struct ProfileOption: Identifiable, Hashable {
        let id: UUID
        let name: String
        let color: String
    }

    var text = ""
    var profiles: [ProfileOption] = []
    var profileID: UUID?
    private(set) var isLoading = true
    /// Set when the text couldn't be added; the sheet stays open so nothing is lost.
    private(set) var errorMessage: String?

    @ObservationIgnored private weak var context: NSExtensionContext?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    var canAdd: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func load() async {
        let store = NoteStore(context: ModelContext(SharedContainer.shared))
        profiles = store.profiles().map { ProfileOption(id: $0.id, name: $0.name, color: $0.colorHex) }
        profileID = store.currentProfile(preferredID: ProfileSelection.preferredID).id

        var pieces: [String] = []
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                pieces.append(url.absoluteString)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let string = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                pieces.append(string)
            }
        }
        // Pages often share their title as text plus the link: keep both, once.
        var seen = Set<String>()
        text = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: " ")
        isLoading = false
    }

    func add() {
        guard SharedContainer.isAvailable else {
            errorMessage = "Penns couldn't open your note. Open the Penns app, then share again."
            return
        }
        let store = NoteStore(context: ModelContext(SharedContainer.shared))
        store.applyDueTransitions()
        let profile = profileID.flatMap { store.profile(id: $0) }
            ?? store.currentProfile(preferredID: ProfileSelection.preferredID)
        // One shared item becomes one line; inner line breaks would split it.
        let line = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        store.append(line, in: profile)
        do {
            try store.save()
        } catch {
            errorMessage = "Couldn't add this to your note. Copy the text and try again."
            return
        }
        ChangeSignal.post()
        WidgetCenter.shared.reloadAllTimelines()
        context?.completeRequest(returningItems: nil)
    }

    func cancel() {
        context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}

private struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $model.text)
                    .font(NoteStyle.current.swiftUIFont())
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 120, maxHeight: 220)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        if model.isLoading { ProgressView() }
                    }

                if model.profiles.count > 1 {
                    Picker("Profile", selection: $model.profileID) {
                        ForEach(model.profiles) { profile in
                            Label {
                                Text(profile.name)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(ProfileColors.color(profile.color))
                            }
                            .tag(Optional(profile.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let error = model.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    Text("Added as a new line at the end of your note.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Add to Penns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: model.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", role: .confirm, action: model.add)
                        .disabled(!model.canAdd)
                }
            }
        }
    }
}
