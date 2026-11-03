import PennsKit
import SwiftUI
import UIKit

/// The note as one plain-text view, in the user's font. Checklist markers
/// ("- [ ] ") are hidden and drawn as circles you can tap, just like on the Mac.
struct NoteEditor: UIViewRepresentable {
    @Binding var text: String
    var style: NoteStyle
    var focusToken: Int
    /// Draw the faint line where the Lock Screen widget cuts the note off.
    var showsFoldLine: Bool
    var insets: UIEdgeInsets
    var onPullDown: () -> Void
    var onTyping: () -> Void
    var formatBridge: FormatBridge?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PennsTextView {
        // TextKit 1 stack, built by hand: needed for glyph geometry when drawing
        // checkboxes. (`UITextView(usingTextLayoutManager:)` is a factory method
        // that skips a Swift subclass's initializers, leaving its properties unset.)
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = PennsTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.adjustsFontForContentSizeCategory = false
        textView.accessibilityLabel = "Note"
        textView.text = text
        textView.textContainerInset = insets
        textView.onToggle = { [weak coordinator = context.coordinator] in coordinator?.textDidChangeExternally() }
        textView.onIndent = { [weak coordinator = context.coordinator] indent in coordinator?.shiftLines(indent: indent) }
        textView.onFormat = { [weak coordinator = context.coordinator] format in coordinator?.format(format) }
        formatBridge?.perform = { [weak coordinator = context.coordinator] format in coordinator?.format(format) }
        context.coordinator.textView = textView
        context.coordinator.applyStyle()
        return textView
    }

    func updateUIView(_ textView: PennsTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if textView.textContainerInset != insets {
            textView.textContainerInset = insets
        }
        textView.showsFoldLine = showsFoldLine

        if textView.text != text {
            // Replaced from outside (reload, widget, Shortcut, sync): undo steps
            // recorded against the old text no longer fit it, so they're dropped.
            textView.text = text
            textView.ownUndoManager.removeAllActions()
            coordinator.applyStyle()
        } else if coordinator.appliedStyle != style {
            coordinator.applyStyle()
        }

        if coordinator.lastFocusToken != focusToken {
            coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
                let end = (textView.text as NSString).length
                textView.selectedRange = NSRange(location: end, length: 0)
                textView.scrollRangeToVisible(textView.selectedRange)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteEditor
        weak var textView: PennsTextView?
        var lastFocusToken = 0
        var appliedStyle: NoteStyle?
        private var applyingRule = false
        private var lastSelection = NSRange(location: 0, length: 0)

        init(_ parent: NoteEditor) {
            self.parent = parent
        }

        // MARK: Typing rules (EditorRules, shared with the Mac)

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard !applyingRule, textView.markedTextRange == nil,
                  let edit = EditorRules.edit(replacing: range, with: text, in: textView.text) else {
                return true
            }
            apply(edit, in: textView)
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            applyStyle()
            parent.text = textView.text
            parent.onTyping()
        }

        /// A checkbox was tapped: the text view changed its own text.
        func textDidChangeExternally() {
            guard let textView else { return }
            textViewDidChange(textView)
        }

        /// Keeps the caret out of hidden heading and checklist marks.
        func textViewDidChangeSelection(_ textView: UITextView) {
            let current = textView.selectedRange
            let constrained = EditorRules.constrainCaret(from: lastSelection, to: current, in: textView.text)
            lastSelection = constrained
            if constrained != current {
                textView.selectedRange = constrained
            }
        }

        /// Bold, italic, underline, strikethrough or a list, for the selection.
        func format(_ format: TextFormat) {
            guard let textView,
                  let edit = EditorRules.format(format, selection: textView.selectedRange, in: textView.text) else { return }
            apply(edit, in: textView)
        }

        /// Format comes first in the text edit menu (select text, then tap).
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            func actions(_ formats: [TextFormat]) -> [UIMenuElement] {
                formats.map { format in
                    UIAction(title: format.title, image: UIImage(systemName: format.systemImage)) { [weak self] _ in
                        self?.format(format)
                    }
                }
            }
            let styles = UIMenu(options: .displayInline, children: actions(TextFormat.styles))
            let lists = UIMenu(options: .displayInline, children: actions(TextFormat.lists))
            let formatMenu = UIMenu(title: "Format", image: UIImage(systemName: "textformat"), children: [styles, lists])
            return UIMenu(children: [formatMenu] + suggestedActions)
        }

        func shiftLines(indent: Bool) {
            guard let textView,
                  let edit = EditorRules.shiftLines(textView.selectedRange, in: textView.text, indent: indent) else { return }
            apply(edit, in: textView)
        }

        /// Applies through UITextInput so it's one undo step and the usual delegate calls run.
        private func apply(_ edit: EditorRules.Edit, in textView: UITextView) {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
                  let end = textView.position(from: start, offset: edit.range.length),
                  let range = textView.textRange(from: start, to: end) else { return }
            applyingRule = true
            textView.replace(range, withText: edit.replacement)
            applyingRule = false
            lastSelection = edit.selection
            textView.selectedRange = edit.selection
        }

        // MARK: Pull down for the archive

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            if scrollView.contentOffset.y + scrollView.adjustedContentInset.top < -90 {
                parent.onPullDown()
            }
        }

        // MARK: Styling

        private static let tabInterval: CGFloat = 28

        private static func paragraph(before: CGFloat = 0, after: CGFloat = 4, headIndent: CGFloat = 0) -> NSParagraphStyle {
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
            [.font: parent.style.uiFont(), .foregroundColor: UIColor.label, .paragraphStyle: Self.paragraph()]
        }

        /// Negative kerning for the hidden marker characters, so the text starts
        /// 8 pt after the drawn circle. Measured per marker: "x" is wider than a
        /// space, and ticked items must line up with open ones.
        private func markerKern(for marker: String) -> CGFloat {
            let font = parent.style.uiFont()
            let natural = (marker as NSString).size(withAttributes: [.font: font]).width
            let wanted = PennsTextView.circleDiameter(for: font) + 8
            return (wanted - natural) / CGFloat(max(marker.utf16.count, 1))
        }

        /// Wrapped lines of list and checklist items line up with the item's text.
        private func styleListIndents(in storage: NSTextStorage, string: NSString) {
            let font = parent.style.uiFont()
            let space = (" " as NSString).size(withAttributes: [.font: font]).width
            var location = 0
            while location < string.length {
                let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
                let line = string.substring(with: lineRange)
                let indentWidth = Markdown.indentation(of: line).reduce(CGFloat(0)) { $0 + ($1 == "\t" ? Self.tabInterval : space) }
                var markerWidth: CGFloat?
                if Checklist.marker(of: line) != nil {
                    markerWidth = PennsTextView.circleDiameter(for: font) + 8
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
                    let trait: UIFontDescriptor.SymbolicTraits = span.style == .bold ? .traitBold : .traitItalic
                    storage.enumerateAttribute(.font, in: span.content) { value, range, _ in
                        guard let font = value as? UIFont else { return }
                        let traits = font.fontDescriptor.symbolicTraits.union(trait)
                        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return }
                        storage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: range)
                    }
                case .underline:
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
                case .strikethrough:
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
                }
            }
            for span in spans {
                for marker in [span.open, span.close] {
                    storage.addAttributes([.foregroundColor: UIColor.clear, .font: UIFont.systemFont(ofSize: 0.01)], range: marker)
                    storage.removeAttribute(.underlineStyle, range: marker)
                    storage.removeAttribute(.strikethroughStyle, range: marker)
                }
            }
        }

        func applyStyle() {
            guard let textView else { return }
            // Never restyle mid-composition (Japanese input, dead keys…).
            guard textView.markedTextRange == nil else { return }
            appliedStyle = parent.style
            let storage = textView.textStorage
            let string = textView.text as NSString
            let selection = textView.selectedRange

            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            var location = 0
            while location < string.length {
                let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
                let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
                if let heading = Markdown.heading(of: line) {
                    storage.addAttributes([
                        .font: parent.style.uiFont(
                            scale: NoteStyle.headingScale(heading.level),
                            weight: heading.level == 3 ? .semibold : .bold
                        ),
                        .paragraphStyle: Self.paragraph(before: heading.level == 1 ? 8 : 6, after: 4),
                    ], range: lineRange)
                    storage.addAttributes([
                        .foregroundColor: UIColor.clear,
                        .font: UIFont.systemFont(ofSize: 0.01),
                    ], range: NSRange(location: lineRange.location, length: heading.markerLength))
                }
                location = NSMaxRange(lineRange)
            }
            for line in Checklist.markerRanges(in: textView.text) {
                styleListIndents(in: storage, string: string)
            styleInline(in: storage, string: textView.text)
            let kern = markerKern(for: string.substring(with: line.marker))
                storage.addAttributes([.foregroundColor: UIColor.clear, .kern: kern], range: line.marker)
                if line.isChecked, line.content.length > 0 {
                    // Crossed out but still easy to read.
                    let done = UIColor.label.withAlphaComponent(0.8)
                    storage.addAttributes([
                        .foregroundColor: done,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: done,
                    ], range: line.content)
                }
            }
            storage.endEditing()
            if textView.selectedRange != selection { textView.selectedRange = selection }
            textView.typingAttributes = attributes
            textView.setNeedsCheckboxDisplay()
        }
    }
}

/// UITextView with tappable Notes-style circles, its own undo stack and
/// Tab / Shift-Tab on a hardware keyboard.
final class PennsTextView: UITextView, UIGestureRecognizerDelegate {
    var onToggle: (() -> Void)?
    var onIndent: ((Bool) -> Void)?
    var onFormat: ((TextFormat) -> Void)?
    var showsFoldLine = false {
        didSet { if oldValue != showsFoldLine { canvas.setNeedsDisplay() } }
    }
    /// One undo stack per note editor, never shared with anything else.
    let ownUndoManager = UndoManager()
    override var undoManager: UndoManager? { ownUndoManager }

    private let canvas = CheckboxCanvas()
    private var checkboxTap: UITapGestureRecognizer?

    static func circleDiameter(for font: UIFont) -> CGFloat {
        round(font.pointSize * 1.2)
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        canvas.textView = self
        canvas.isUserInteractionEnabled = false
        canvas.backgroundColor = .clear
        canvas.contentMode = .redraw
        addSubview(canvas)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapCheckbox(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
        checkboxTap = tap
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // UITextView adds its own text views on top; the circles must stay above them.
        if subviews.last !== canvas { bringSubviewToFront(canvas) }
        let size = CGSize(width: bounds.width, height: max(contentSize.height, bounds.height))
        if canvas.frame.size != size {
            canvas.frame = CGRect(origin: .zero, size: size)
            canvas.setNeedsDisplay()
        }
    }

    func setNeedsCheckboxDisplay() {
        setNeedsLayout()
        canvas.setNeedsDisplay()
    }

    // MARK: Checkboxes

    struct Box {
        let rect: CGRect
        let isChecked: Bool
        let toggle: NSRange
    }

    /// The circles in text-view coordinates.
    fileprivate var checkboxes: [Box] {
        var result: [Box] = []
        let origin = CGPoint(x: textContainerInset.left, y: textContainerInset.top)
        for line in Checklist.markerRanges(in: text) {
            let glyphs = layoutManager.glyphRange(forCharacterRange: line.marker, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            let font = textStorage.attribute(.font, at: line.marker.location, effectiveRange: nil) as? UIFont
                ?? NoteTypography.uiFont
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let baseline = fragment.minY + layoutManager.location(forGlyphAt: glyphs.location).y
            let markerRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            let diameter = Self.circleDiameter(for: font)
            let rect = CGRect(
                x: origin.x + markerRect.minX,
                y: origin.y + baseline - font.capHeight / 2 - diameter / 2,
                width: diameter,
                height: diameter
            )
            result.append(Box(rect: rect, isChecked: line.isChecked, toggle: line.toggle))
        }
        return result
    }

    /// Bottom of the last line the Lock Screen widget shows, in text-view coordinates.
    fileprivate var foldLineY: CGFloat? {
        guard showsFoldLine, let fold = LockScreenFold.characterIndex(in: text), fold > 0 else { return nil }
        let glyph = layoutManager.glyphIndexForCharacter(at: fold - 1)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        // The fragment already includes the paragraph spacing below the line,
        // so this sits in the gap between the last visible line and the next.
        return textContainerInset.top + fragment.maxY - 2
    }

    private func box(at point: CGPoint) -> Box? {
        checkboxes.first { $0.rect.insetBy(dx: -10, dy: -8).contains(point) }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === checkboxTap else { return true }
        return box(at: touch.location(in: self)) != nil
    }

    /// While a touch is on a circle, the text view's own taps wait, so ticking
    /// never moves the caret or opens the keyboard.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === checkboxTap && !(other is UIPanGestureRecognizer)
    }

    @objc private func tapCheckbox(_ recognizer: UITapGestureRecognizer) {
        guard let box = box(at: recognizer.location(in: self)) else { return }
        let current = (text as NSString).substring(with: box.toggle)
        guard let start = position(from: beginningOfDocument, offset: box.toggle.location),
              let end = position(from: start, offset: box.toggle.length),
              let range = textRange(from: start, to: end) else { return }
        let selection = selectedRange
        replace(range, withText: current == " " ? "x" : " ")
        selectedRange = selection
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onToggle?()
    }

    // MARK: Hardware keyboard

    override var keyCommands: [UIKeyCommand]? {
        let indent = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indentLines))
        let outdent = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentLines))
        indent.wantsPriorityOverSystemBehavior = true
        outdent.wantsPriorityOverSystemBehavior = true
        // The Apple Notes shortcuts: ⌘B, ⌘I, ⌘U, ⇧⌘X, ⇧⌘7, ⇧⌘8, ⇧⌘9, ⇧⌘L.
        let formats = TextFormat.all.enumerated().map { index, format in
            let command = UIKeyCommand(
                title: format.title,
                image: UIImage(systemName: format.systemImage),
                action: #selector(formatFromKeyboard(_:)),
                input: format.keyEquivalent.key,
                modifierFlags: format.keyEquivalent.shift ? [.command, .shift] : .command,
                propertyList: index
            )
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
        return [indent, outdent] + formats
    }

    @objc private func formatFromKeyboard(_ command: UIKeyCommand) {
        guard let index = command.propertyList as? Int, TextFormat.all.indices.contains(index) else { return }
        onFormat?(TextFormat.all[index])
    }

    /// The system's own bold/italic/underline commands (⌘B…) route here too.
    override func toggleBoldface(_ sender: Any?) { onFormat?(.bold) }
    override func toggleItalics(_ sender: Any?) { onFormat?(.italic) }
    override func toggleUnderline(_ sender: Any?) { onFormat?(.underline) }

    @objc private func indentLines() { onIndent?(true) }
    @objc private func outdentLines() { onIndent?(false) }
}

/// Draws the circles (and the fold line) over the text, where the hidden markers sit.
private final class CheckboxCanvas: UIView {
    weak var textView: PennsTextView?

    override func draw(_ rect: CGRect) {
        guard let textView else { return }
        if let y = textView.foldLineY {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: textView.textContainerInset.left, y: y))
            path.addLine(to: CGPoint(x: bounds.width - textView.textContainerInset.right, y: y))
            path.lineWidth = 1
            path.setLineDash([2, 4], count: 2, phase: 0)
            path.lineCapStyle = .round
            UIColor.label.withAlphaComponent(0.15).setStroke()
            path.stroke()
        }

        for box in textView.checkboxes {
            let circle = box.rect
            let diameter = circle.width
            if box.isChecked {
                textView.tintColor.setFill()
                UIBezierPath(ovalIn: circle).fill()
                let check = UIBezierPath()
                check.move(to: CGPoint(x: circle.minX + diameter * 0.29, y: circle.minY + diameter * 0.50))
                check.addLine(to: CGPoint(x: circle.minX + diameter * 0.44, y: circle.minY + diameter * 0.65))
                check.addLine(to: CGPoint(x: circle.minX + diameter * 0.72, y: circle.minY + diameter * 0.36))
                check.lineWidth = max(1.8, diameter * 0.12)
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                UIColor.white.setStroke()
                check.stroke()
            } else {
                let ring = UIBezierPath(ovalIn: circle.insetBy(dx: 0.75, dy: 0.75))
                UIColor.label.withAlphaComponent(0.06).setFill()
                ring.fill()
                ring.lineWidth = 1.5
                UIColor.label.withAlphaComponent(0.4).setStroke()
                ring.stroke()
            }
        }
    }
}
