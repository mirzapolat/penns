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
    var formatBridge: FormatBridge?

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
        textView.onFormat = { [weak coordinator = context.coordinator] format in coordinator?.format(format) }
        formatBridge?.perform = { [weak coordinator = context.coordinator] format in coordinator?.format(format) }
        context.coordinator.applyStyle()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        textView.onEscape = onEscape

        if textView.string != text {
            // Text replaced from outside (reload, widget, Shortcut, sync). Undo
            // steps recorded against the old text no longer match it and could
            // wipe the note on ⌘Z, so they're dropped.
            textView.string = text
            coordinator.undoManager.removeAllActions()
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
        /// One undo stack per note editor, not the panel window's shared one, so
        /// ⌘Z never replays edits from another note or from before a reload.
        let undoManager = UndoManager()

        init(_ parent: NoteEditor) {
            self.parent = parent
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            applyStyle()
            parent.text = textView.string
            parent.onTyping()
        }

        // Typing rules live in PennsKit (EditorRules) so they're unit-tested and
        // shared with the iOS editor. The delegate only applies their results.

        /// Bold, italic, underline, strikethrough or a list, for the selection.
        func format(_ format: TextFormat) {
            guard let textView,
                  let edit = EditorRules.format(format, selection: textView.selectedRange(), in: textView.string) else { return }
            textView.window?.makeFirstResponder(textView)
            apply(edit, in: textView)
        }

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

        private static func paragraph(before: CGFloat = 0, after: CGFloat = 3, headIndent: CGFloat = 0) -> NSParagraphStyle {
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = headIndent
            paragraph.lineHeightMultiple = 1.1
            paragraph.paragraphSpacingBefore = before
            paragraph.paragraphSpacing = after
            paragraph.tabStops = []
            paragraph.defaultTabInterval = tabInterval
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

        /// Wrapped lines of list and checklist items line up with the item's text.
        private func styleListIndents(in storage: NSTextStorage, string: NSString) {
            let font = parent.style.nsFont()
            let space = (" " as NSString).size(withAttributes: [.font: font]).width
            var location = 0
            while location < string.length {
                let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
                let line = string.substring(with: lineRange)
                let indentation = Markdown.indentation(of: line)
                let indentWidth = indentation.reduce(CGFloat(0)) { $0 + ($1 == "\t" ? Self.tabInterval : space) }
                var markerWidth: CGFloat?
                if Checklist.marker(of: line) != nil {
                    markerWidth = round(font.pointSize * 1.15) + 7
                } else if let marker = ListMarker.parse(line) {
                    markerWidth = (ListMarker.marker(for: marker.kind) as NSString).size(withAttributes: [.font: font]).width
                }
                if let markerWidth {
                    storage.addAttribute(.paragraphStyle, value: Self.paragraph(headIndent: indentWidth + markerWidth), range: lineRange)
                }
                location = NSMaxRange(lineRange)
            }
        }

        /// Bold/italic fonts, underline and strikethrough for styled runs; their
        /// markers are hidden like heading marks.
        private func styleInline(in storage: NSTextStorage, string: String) {
            let spans = InlineMarkup.spans(in: string)
            guard !spans.isEmpty else { return }
            for span in spans {
                switch span.style {
                case .bold, .italic:
                    let trait: NSFontTraitMask = span.style == .bold ? .boldFontMask : .italicFontMask
                    storage.enumerateAttribute(.font, in: span.content) { value, range, _ in
                        guard let font = value as? NSFont else { return }
                        storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: range)
                    }
                case .underline:
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
                case .strikethrough:
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
                }
            }
            for span in spans {
                for marker in [span.open, span.close] {
                    storage.addAttributes([
                        .foregroundColor: NSColor.clear,
                        .font: NSFont.systemFont(ofSize: 0.01),
                    ], range: marker)
                    storage.removeAttribute(.underlineStyle, range: marker)
                    storage.removeAttribute(.strikethroughStyle, range: marker)
                }
            }
        }

        private static let tabInterval: CGFloat = 24

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
        /// Measured per marker: "x" is wider than a space, and ticked items must
        /// line up with open ones.
        private func markerKern(for marker: String) -> CGFloat {
            let font = parent.style.nsFont()
            let natural = (marker as NSString).size(withAttributes: [.font: font]).width
            let wanted = round(font.pointSize * 1.15) + 7
            return (wanted - natural) / CGFloat(max(marker.utf16.count, 1))
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
            styleListIndents(in: storage, string: textView.string as NSString)
            styleInline(in: storage, string: textView.string)
            let string = textView.string as NSString
            for line in Checklist.markerRanges(in: textView.string) {
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: line.marker)
                storage.addAttribute(.kern, value: markerKern(for: string.substring(with: line.marker)), range: line.marker)
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
    var onFormat: ((TextFormat) -> Void)?

    /// From the Format menu (main menu shortcuts, right-click, the "…" menu).
    @objc func pennsFormat(_ sender: NSMenuItem) {
        guard TextFormat.all.indices.contains(sender.tag) else { return }
        onFormat?(TextFormat.all[sender.tag])
    }

    /// Right-click: Format comes first, then the system items.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let item = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        item.submenu = MainMenu.formatMenu()
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }
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
