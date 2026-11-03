import SwiftUI
import WidgetKit

@main
struct PennsWidgetBundle: WidgetBundle {
    var body: some Widget {
        NoteWidget()
        #if os(iOS)
        LockScreenNoteWidget()
        NoteLiveActivityWidget()
        GoLiveControl()
        #endif
    }
}
