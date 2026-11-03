import AppKit
import PennsKit
import SwiftUI

/// Read-only floating view of the note, shown while hovering the menu bar item.
@MainActor
final class PeekPanel {
    private var panel: NSPanel?

    func show(text: String, below anchor: NSRect) {
        let hosting = NSHostingView(rootView: PeekView(text: text))
        let size = hosting.fittingSize
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = hosting

        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height + 4)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return panel
    }
}

private struct PeekView: View {
    let text: String

    var body: some View {
        Text(Checklist.displayText(text).trimmingCharacters(in: .whitespacesAndNewlines))
            .font(NoteTypography.font)
            .lineSpacing(2)
            .lineLimit(16)
        .frame(width: 260, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(10)
    }
}
