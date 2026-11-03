import PennsKit
import SwiftUI

@main
struct PennsApp: App {
    @State private var model = NoteViewModel(container: SharedContainer.shared)
    @State private var live = LiveController()
    @AppStorage(IOSPrefs.didShowWelcome) private var didShowWelcome = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WatchBridge.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            if let failure = SharedContainer.loadFailure {
                StoreUnavailableView(details: failure)
            } else {
                noteView
            }
        }
    }

    private var noteView: some View {
        Group {
            NoteScreen(model: model)
                .environment(live)
                .onOpenURL(perform: open)
                // Handoff: pick up the note on another device (same iCloud account).
                .userActivity(Handoff.activityType) { activity in
                    activity.title = "Penns"
                    activity.isEligibleForHandoff = true
                }
                .onContinueUserActivity(Handoff.activityType) { _ in
                    model.showingArchive = false
                    model.prepareForDisplay()
                }
                #if DEBUG
                // Screenshots without typing: -PennsDemoNote, -PennsDemoDone
                // (every item ticked), -PennsDemoArchive (archive it and show the list).
                .onAppear {
                    let arguments = ProcessInfo.processInfo.arguments
                    let demo = "# Saturday\nCall the bakery about the cake\n- [x] Flowers\n- [ ] Candles\n- [ ] Pick up Mia at 4"
                    if arguments.contains("-PennsDemoNote"), model.note.isBlank {
                        model.text = demo
                    }
                    if arguments.contains("-PennsDemoFormat") {
                        model.text = """
                        # Weekend
                        **Bold**, _italic_, ++underlined++ and ~~struck~~ — or **_both_**.
                        • Bakery: ask about the **chocolate** cake, and whether they can deliver on Saturday morning
                        • Flowers
                        – Call Mia
                        – Book a table
                        1. Clean the kitchen
                        2. Set the table
                        3. Light the candles
                        - [x] Invitations
                        - [ ] Music
                        """
                    }
                    if arguments.contains("-PennsDemoDone") {
                        model.text = demo.replacingOccurrences(of: "- [ ]", with: "- [x]")
                    }
                    if arguments.contains("-PennsDemoArchive") {
                        if model.note.isBlank { model.text = demo }
                        model.archive()
                        model.showingArchive = true
                    }
                }
                #endif
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        model.onNoteChange = { [live] in
                            live.noteChanged()
                            WatchBridge.shared.schedulePush()
                        }
                        WatchBridge.shared.schedulePush()
                        model.prepareForDisplay()
                        live.appBecameActive(model)
                    case .background: model.flush()
                    default: break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .pennsShowNote)) { _ in
                    model.showingArchive = false
                    model.prepareForDisplay()
                }
                // Lifespan labels and expiries stay current while the app is open.
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        model.tick()
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !didShowWelcome },
                    set: { didShowWelcome = !$0 }
                )) {
                    WelcomeView {
                        didShowWelcome = true
                        model.prepareForDisplay()
                    }
                }
        }
    }

    /// `penns://note` opens the note, `penns://archive` the archive.
    private func open(_ url: URL) {
        guard url.scheme == "penns" else { return }
        switch url.host() {
        case "archive":
            model.showingArchive = true
        default:
            model.showingArchive = false
            model.prepareForDisplay()
        }
    }
}
