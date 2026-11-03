import AppKit
import PennsKit
import SwiftUI

/// Plain-text editor in SF Pro, one text style throughout. Checklist markers ("- [ ] ") are hidden and drawn as
/// circles you can click.
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
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

        init(_ parent: NoteEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            applyStyle()
            parent.text = textView.string
            parent.onTyping()
        }

        /// The hidden "# " range of the heading line containing `location`, if any.
        static func headingMarker(in string: NSString, at location: Int) -> NSRange? {
            guard location <= string.length else { return nil }
            let lineRange = string.lineRange(for: NSRange(location: min(location, max(0, string.length)), length: 0))
            let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard let heading = Markdown.heading(of: line) else { return nil }
            return NSRange(location: lineRange.location, length: heading.markerLength)
        }

        /// The hidden checklist marker ("- [ ] ", after any indentation) on the line containing `location`.
        static func checklistMarker(in string: NSString, at location: Int) -> NSRange? {
            guard location <= string.length else { return nil }
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let line = string.substring(with: lineRange)
            guard let marker = Checklist.marker(of: line) else { return nil }
            return NSRange(location: lineRange.location + marker.length - 6, length: 6)
        }

        /// Any hidden marker (heading or checklist) on the line containing `location`.
        static func hiddenMarker(in string: NSString, at location: Int) -> NSRange? {
            headingMarker(in: string, at: location) ?? checklistMarker(in: string, at: location)
        }

        /// Keeps the caret out of hidden heading and checklist marks.
        func textView(
            _ textView: NSTextView,
            willChangeSelectionFromCharacterRange oldRange: NSRange,
            toCharacterRange newRange: NSRange
        ) -> NSRange {
            guard newRange.length == 0 else { return newRange }
            let string = textView.string as NSString
            guard let marker = Self.hiddenMarker(in: string, at: newRange.location),
                  newRange.location >= marker.location,
                  newRange.location < NSMaxRange(marker) else { return newRange }
            let movingLeft = newRange.location < oldRange.location && oldRange.location >= NSMaxRange(marker)
            if movingLeft, marker.location > 0 {
                return NSRange(location: marker.location - 1, length: 0) // end of the line above
            }
            return NSRange(location: NSMaxRange(marker), length: 0)
        }

        /// Tab indents and Shift-Tab outdents the current or selected lines.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                shiftLines(in: textView, indent: true)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                shiftLines(in: textView, indent: false)
                return true
            default:
                return false
            }
        }

        private func shiftLines(in textView: NSTextView, indent: Bool) {
            let string = textView.string as NSString
            let selection = textView.selectedRange()
            let paragraphs = string.lineRange(for: selection)
            let original = string.substring(with: paragraphs)
            let updated = indent ? Markdown.indent(original) : Markdown.outdent(original)
            guard updated != original,
                  textView.shouldChangeText(in: paragraphs, replacementString: updated) else { return }
            textView.textStorage?.replaceCharacters(in: paragraphs, with: updated)
            textView.didChangeText()

            if selection.length == 0 {
                // Keep the caret on the same character of the first line.
                let oldFirst = (original as NSString).lineRange(for: NSRange(location: 0, length: 0)).length
                let newFirst = (updated as NSString).lineRange(for: NSRange(location: 0, length: 0)).length
                let location = max(paragraphs.location, selection.location + newFirst - oldFirst)
                textView.setSelectedRange(NSRange(location: location, length: 0))
            } else {
                textView.setSelectedRange(NSRange(location: paragraphs.location, length: (updated as NSString).length))
            }
        }

        /// "- " + space starts a checklist item; Return continues it (and any
        /// indentation); Return on an empty item or empty indented line ends it.
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            // Backspace at the start of a heading's or checklist item's text removes
            // the whole hidden marker in one go (indentation stays).
            if replacementString == "", range.length == 1,
               let marker = Self.hiddenMarker(in: textView.string as NSString, at: range.location),
               NSMaxRange(range) == NSMaxRange(marker) {
                textView.insertText("", replacementRange: marker)
                return false
            }
            guard let replacement = replacementString, range.length == 0 else { return true }
            let string = textView.string as NSString
            let lineRange = string.lineRange(for: NSRange(location: range.location, length: 0))
            let prefix = string.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))

            if replacement == " ", prefix.hasSuffix("-"), prefix.dropLast().allSatisfy({ $0 == "\t" || $0 == " " }) {
                textView.insertText(Checklist.uncheckedMarker, replacementRange: NSRange(location: range.location - 1, length: 1))
                return false
            }

            if replacement == "\n" {
                let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
                let indentation = Markdown.indentation(of: line)
                let lineLength = (line as NSString).length

                if let marker = Checklist.marker(of: line) {
                    let content = line.dropFirst(marker.length).trimmingCharacters(in: .whitespaces)
                    if content.isEmpty {
                        // Return on an empty item ends the list: the checkbox goes away.
                        textView.insertText("", replacementRange: NSRange(location: lineRange.location, length: lineLength))
                        return false
                    }
                    if prefix.count >= marker.length {
                        textView.insertText("\n" + indentation + Checklist.uncheckedMarker, replacementRange: range)
                        return false
                    }
                }

                if !indentation.isEmpty, prefix.count >= indentation.count {
                    if line.trimmingCharacters(in: .whitespaces).isEmpty {
                        textView.insertText("", replacementRange: NSRange(location: lineRange.location, length: lineLength))
                    } else {
                        textView.insertText("\n" + indentation, replacementRange: range)
                    }
                    return false
                }
            }
            return true
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
            [.font: NoteTypography.nsFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: Self.paragraph()]
        }

        /// "# " 22 pt bold, "## " 18 pt bold, "### " 15 pt semibold.
        private static func headingFont(_ level: Int) -> NSFont {
            switch level {
            case 1: NSFont.systemFont(ofSize: 22, weight: .bold)
            case 2: NSFont.systemFont(ofSize: 18, weight: .bold)
            default: NSFont.systemFont(ofSize: 15, weight: .semibold)
            }
        }

        private func styleHeadings(in storage: NSTextStorage, string: NSString) {
            var location = 0
            while location < string.length {
                let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
                let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
                if let heading = Markdown.heading(of: line) {
                    storage.addAttributes([
                        .font: Self.headingFont(heading.level),
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
        static let markerKern: CGFloat = {
            let font = NoteTypography.nsFont
            let natural = (Checklist.uncheckedMarker as NSString).size(withAttributes: [.font: font]).width
            let wanted = round(font.pointSize * 1.15) + 7
            return (wanted - natural) / CGFloat(Checklist.uncheckedMarker.count)
        }()

        func applyStyle() {
            guard let textView, let storage = textView.textStorage else { return }
            // Never restyle mid-composition (e.g. Japanese input, dead keys).
            guard !textView.hasMarkedText() else { return }

            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(attributes, range: full)
            styleHeadings(in: storage, string: textView.string as NSString)
            let markerKern = Self.markerKern
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
