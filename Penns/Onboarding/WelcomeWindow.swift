import AppKit
import SwiftUI

/// The first-launch welcome, in its own window so the note stays the note.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onFinish: (() -> Void)?

    func show(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        if window == nil {
            let view = WelcomeView { [weak self] in self?.finish() }
            let controller = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        let onFinish = onFinish
        self.onFinish = nil
        // Let the window finish closing before the note drops down.
        DispatchQueue.main.async { onFinish?() }
    }
}

private struct WelcomeView: View {
    var start: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .padding(.bottom, 14)
            Text("Welcome to Penns")
                .font(.system(size: 22, weight: .semibold))
            Text("One note, always one glance away.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 14) {
                tip("menubar.rectangle", "Your note lives in the menu bar", "Click the icon or press ⌥⌘N from anywhere.")
                tip("checklist", "Checklists", "Type “- ” at the start of a line.")
                tip("archivebox", "Let it go", "Archive when you're done — a blank note is waiting.")
                tip("square.grid.2x2", "Keep it in sight", "Right-click the desktop → Edit Widgets → Penns.")
            }
            .padding(.vertical, 24)

            Button(action: start) {
                Text("Start Writing")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 400)
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
