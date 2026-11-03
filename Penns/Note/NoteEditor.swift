import AppKit
import PennsKit
import SwiftUI

/// Plain-text editor in SF Pro, one text style throughout. Checklist markers ("- [ ] ") are hidden and drawn as
/// circles you can click.
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    var style: NoteStyle
    var focusToken: Int
    /// Space kept free under the text for the floating toolbar.
    var bottomInset: CGFloat
    var onEscape: () -> Void
    var onTyping: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 stack: needed for glyph geometry when drawing checkboxes.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = PennsTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 300), textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.insertionPointColor = .controlAccentColor
        textView.onEscape = onEscape
        textView.string = text
        textView.setAccessibilityLabel("Note")

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.applyStyle()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        textView.onEscape = onEscape

        if textView.string != text {
            textView.string = text
            coordinator.applyStyle()
        } else if coordinator.appliedStyle != style {
            coordinator.applyStyle()
        }

        if coordinator.lastFocusToken != focusToken {
            coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeKey()
                textView.window?.makeFirstResponder(textView)
                let end = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                textView.scrollRangeToVisible(NSRange(location: end, length: 0))
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var textView: PennsTextView?
        var lastFocusToken = 0
        var appliedStyle: NoteStyle?

        init(_ parent: NoteEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            applyStyle()
            parent.text = textView.string
            parent.onTyping()
        }

        // Typing rules live in PennsKit (EditorRules) so they're unit-tested and
        // shared with the iOS editor. The delegate only applies their results.

        private func apply(_ edit: EditorRules.Edit, in textView: NSTextView) {
            textView.insertText(edit.replacement, replacementRange: edit.range)
            textView.setSelectedRange(edit.selection)
        }

        /// Keeps the caret out of hidden heading and checklist marks.
        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRange oldRange: NSRange,
            toCharacterRange newRange: NSRange
        ) -> NSRange {
            EditorRules.constrainCaret(from: oldRange, to: newRange, in: textView.string)
        }

        /// Tab indents and Shift-Tab outdents the current or selected lines.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let indent: Bool
            switch selector {
            case #selector(NSResponder.insertTab(_:)): indent = true
            case #selector(NSResponder.insertBacktab(_:)): indent = false
            default: return false
            }
            if let edit = EditorRules.shiftLines(textView.selectedRange(), in: textView.string, indent: indent) {
                apply(edit, in: textView)
            }
            return true
        }

        /// Checklist, indentation and hidden-marker rules for typing, Return and Backspace.
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString,
                  let edit = EditorRules.edit(replacing: range, with: replacement, in: textView.string) else {
                return true
            }
            apply(edit, in: textView)
            return false
        }

        private static func paragraph(before: CGFloat = 0, after: CGFloat = 3) -> NSParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.1
            paragraph.paragraphSpacingBefore = before
            paragraph.paragraphSpacing = after
            paragraph.tabStops = []
            paragraph.defaultTabInterval = 24
            return paragraph
        }

        private var attributes: [NSAttributedString.Key: Any] {
            [.font: parent.style.nsFont(), .foregroundColor: NSColor.labelColor, .paragraphStyle: Self.paragraph()]
        }

        /// Headings in the chosen font, scaled from the body size
        /// (22 / 18 / 15 pt at a 14 pt body).
        private func headingFont(_ level: Int) -> NSFont {
            parent.style.nsFont(scale: NoteStyle.headingScale(level), weight: level == 3 ? .semibold : .bold)
        }

        private func styleHeadings(in storage: NSTextStorage, string: NSString) {
            var location = 0
            while location < string.length {
                let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
                let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
                if let heading = Markdown.heading(of: line) {
                    storage.addAttributes([
                        .font: headingFont(heading.level),
                        .paragraphStyle: Self.paragraph(before: heading.level == 1 ? 6 : 4, after: 4),
                    ], range: lineRange)
                    // Hide the "# " marks: invisible and (almost) zero width.
                    storage.addAttributes([
                        .foregroundColor: NSColor.clear,
                        .font: NSFont.systemFont(ofSize: 0.01),
                    ], range: NSRange(location: lineRange.location, length: heading.markerLength))
                }
                location = NSMaxRange(lineRange)
            }
        }

        /// Negative kerning for the 6 hidden marker characters, so the text starts
        /// 7 pt after the drawn circle instead of after "- [ ] ".
        private var markerKern: CGFloat {
            let font = parent.style.nsFont()
            let natural = (Checklist.uncheckedMarker as NSString).size(withAttributes: [.font: font]).width
            let wanted = round(font.pointSize * 1.15) + 7
            return (wanted - natural) / CGFloat(Checklist.uncheckedMarker.count)
        }

        func applyStyle() {
            guard let textView, let storage = textView.textStorage else { return }
            // Never restyle mid-composition (e.g. Japanese input, dead keys).
            guard !textView.hasMarkedText() else { return }
            appliedStyle = parent.style

            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(attributes, range: full)
            styleHeadings(in: storage, string: textView.string as NSString)
            let markerKern = markerKern
            for line in Checklist.markerRanges(in: textView.string) {
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: line.marker)
                storage.addAttribute(.kern, value: markerKern, range: line.marker)
                if line.isChecked, line.content.length > 0 {
                    // Crossed out but still easy to read on glass.
                    let done = NSColor.labelColor.withAlphaComponent(0.8)
                    storage.addAttributes([
                        .foregroundColor: done,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: done,
                    ], range: line.content)
                }
            }
            storage.endEditing()
            textView.typingAttributes = attributes
            textView.needsDisplay = true
        }
    }
}

final class PennsTextView: NSTextView {
    var onEscape: (() -> Void)?
    private var checkboxes: [(hitRect: NSRect, toggle: NSRange)] = []

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// The first click places the caret (or ticks a box) right away.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCheckboxes()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let box = checkboxes.first(where: { $0.hitRect.contains(point) }) {
            toggleCheckbox(box.toggle)
            return
        }
        super.mouseDown(with: event)
    }

    private func toggleCheckbox(_ range: NSRange) {
        let current = (string as NSString).substring(with: range)
        let replacement = current == " " ? "x" : " "
        if shouldChangeText(in: range, replacementString: replacement) {
            textStorage?.replaceCharacters(in: range, with: replacement)
            didChangeText()
        }
    }

    /// Apple Notes-style circles: hollow grey, or filled with the accent color.
    private func drawCheckboxes() {
        checkboxes.removeAll()
        guard let layoutManager, let textContainer, let storage = textStorage else { return }
        let origin = textContainerOrigin

        for line in Checklist.markerRanges(in: string) {
            let glyphs = layoutManager.glyphRange(forCharacterRange: line.marker, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            let font = storage.attribute(.font, at: line.marker.location, effectiveRange: nil) as? NSFont
                ?? NoteTypography.nsFont
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let baseline = fragment.minY + layoutManager.location(forGlyphAt: glyphs.location).y
            let markerRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)

            let diameter = round(font.pointSize * 1.15)
            let rect = NSRect(
                x: origin.x + markerRect.minX,
                y: origin.y + baseline - font.capHeight / 2 - diameter / 2,
                width: diameter,
                height: diameter
            )

            if line.isChecked {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: rect).fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: rect.minX + diameter * 0.29, y: rect.minY + diameter * 0.52))
                check.line(to: NSPoint(x: rect.minX + diameter * 0.44, y: rect.minY + diameter * 0.67))
                check.line(to: NSPoint(x: rect.minX + diameter * 0.72, y: rect.minY + diameter * 0.35))
                check.lineWidth = max(1.8, diameter * 0.13)
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.white.setStroke()
                check.stroke()
            } else {
                // Glass lets the background through, so the empty circle gets a soft
                // fill plus a clear stroke to stay visible on light and dark content.
                let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
                NSColor.labelColor.withAlphaComponent(0.08).setFill()
                circle.fill()
                circle.lineWidth = 1.5
                NSColor.labelColor.withAlphaComponent(0.5).setStroke()
                circle.stroke()
            }
            checkboxes.append((rect.insetBy(dx: -5, dy: -5), line.toggle))
        }
    }
}
