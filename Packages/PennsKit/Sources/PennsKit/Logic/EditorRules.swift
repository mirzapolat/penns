import Foundation

/// The editor's typing rules as pure functions on text + selection, shared by
/// the Mac and iOS editors. Ranges are UTF-16 (`NSString`) offsets.
///
/// Rules:
/// - At the start of a line (after any indentation), "- " starts a checklist
///   item, "* " a bulleted list ("• "), "-- " a dashed list ("– "). "1. " is
///   already a numbered list.
/// - Return continues a checklist item, list (numbers count up and the rest of
///   the list is renumbered) or the line's indentation; on an empty item or an
///   empty indented line it ends the list instead.
/// - Backspace right after a hidden marker (heading "# " or checklist "- [ ] ")
///   or a list marker removes the whole marker. Backspace never half-deletes a
///   hidden bold/italic/underline/strikethrough marker.
/// - Tab / Shift-Tab indent or outdent every line touched by the selection.
/// - The caret never rests inside a hidden marker.
public enum EditorRules {
    /// A replacement to apply instead of the user's edit, and where the caret goes.
    public struct Edit: Equatable, Sendable {
        public let range: NSRange
        public let replacement: String
        public let selection: NSRange

        public init(range: NSRange, replacement: String, selection: NSRange) {
            self.range = range
            self.replacement = replacement
            self.selection = selection
        }
    }

    // MARK: Hidden markers

    /// The "# " / "## " / "### " range of the heading line containing `location`.
    public static func headingMarker(in text: String, at location: Int) -> NSRange? {
        let string = text as NSString
        guard location >= 0, location <= string.length else { return nil }
        let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
        let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard let heading = Markdown.heading(of: line) else { return nil }
        return NSRange(location: lineRange.location, length: heading.markerLength)
    }

    /// The "- [ ] " range (after any indentation) of the checklist line containing `location`.
    public static func checklistMarker(in text: String, at location: Int) -> NSRange? {
        let string = text as NSString
        guard location >= 0, location <= string.length else { return nil }
        let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
        let line = string.substring(with: lineRange)
        guard let marker = Checklist.parseMarker(line) else { return nil }
        return NSRange(location: lineRange.location + marker.indent, length: Checklist.markerLength)
    }

    public static func hiddenMarker(in text: String, at location: Int) -> NSRange? {
        headingMarker(in: text, at: location) ?? checklistMarker(in: text, at: location)
    }

    // MARK: Typing

    /// What to do instead of replacing `range` with `replacement`, or `nil` to let
    /// the edit through unchanged.
    public static func edit(replacing range: NSRange, with replacement: String, in text: String) -> Edit? {
        let string = text as NSString

        // Backspace right after a hidden marker removes the whole marker.
        if replacement.isEmpty, range.length == 1,
           let marker = hiddenMarker(in: text, at: range.location),
           NSMaxRange(range) == NSMaxRange(marker) {
            return Edit(range: marker, replacement: "", selection: NSRange(location: marker.location, length: 0))
        }
        if replacement.isEmpty, range.length == 1 {
            if let marker = ListMarker.markerRange(in: text, at: range.location),
               NSMaxRange(range) == NSMaxRange(marker) {
                return Edit(range: marker, replacement: "", selection: NSRange(location: marker.location, length: 0))
            }
            if let edit = InlineMarkup.backspace(range, in: text) {
                return edit
            }
        }

        guard range.length == 0, range.location <= string.length else { return nil }
        let lineRange = string.lineRange(for: NSRange(location: range.location, length: 0))
        let prefix = string.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))

        // "- " starts a checklist item.
        if replacement == " ", prefix.hasSuffix("-"), prefix.dropLast().allSatisfy(isIndent) {
            let dash = NSRange(location: range.location - 1, length: 1)
            return Edit(
                range: dash,
                replacement: Checklist.uncheckedMarker,
                selection: NSRange(location: dash.location + Checklist.markerLength, length: 0)
            )
        }

        // "* " starts a bulleted list, "-- " a dashed list.
        if replacement == " " {
            let typed = prefix.drop(while: isIndent)
            let markerText: String? = typed == "*" ? ListMarker.bullet : typed == "--" ? ListMarker.dash : nil
            if let markerText {
                let typedRange = NSRange(location: range.location - (String(typed) as NSString).length, length: (String(typed) as NSString).length)
                return Edit(
                    range: typedRange,
                    replacement: markerText,
                    selection: NSRange(location: typedRange.location + (markerText as NSString).length, length: 0)
                )
            }
        }

        guard replacement == "\n" else { return nil }
        let line = string.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let lineContent = NSRange(location: lineRange.location, length: (line as NSString).length)
        let indentation = Markdown.indentation(of: line)

        if let marker = Checklist.marker(of: line) {
            let content = line.dropFirst(marker.length).trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                // Return on an empty item ends the list.
                return Edit(range: lineContent, replacement: "", selection: NSRange(location: lineRange.location, length: 0))
            }
            if prefix.count >= marker.length {
                return insertion("\n" + indentation + Checklist.uncheckedMarker, at: range)
            }
            return nil
        }

        if let marker = ListMarker.parse(line) {
            let content = line.dropFirst(marker.indent + marker.length).trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                // Return on an empty item ends the list.
                return Edit(range: lineContent, replacement: "", selection: NSRange(location: lineRange.location, length: 0))
            }
            guard (prefix as NSString).length >= marker.indent + marker.length else { return nil }
            return continueList(line: line, marker: marker, lineRange: lineRange, lineContent: lineContent, caret: range, in: string)
        }

        if !indentation.isEmpty, prefix.count >= indentation.count {
            if line.allSatisfy(isIndent) {
                // Return on an empty indented line drops the indentation.
                return Edit(range: lineContent, replacement: "", selection: NSRange(location: lineRange.location, length: 0))
            }
            return insertion("\n" + indentation, at: range)
        }
        return nil
    }

    /// Tab (`indent: true`) or Shift-Tab for every line the selection touches.
    public static func shiftLines(_ selection: NSRange, in text: String, indent: Bool) -> Edit? {
        let string = text as NSString
        guard NSMaxRange(selection) <= string.length else { return nil }
        let paragraphs = string.lineRange(for: selection)
        let original = string.substring(with: paragraphs)
        let updated = indent ? Markdown.indent(original) : Markdown.outdent(original)
        guard updated != original else { return nil }

        let newSelection: NSRange
        if selection.length == 0 {
            // Keep the caret on the same character of its line.
            let oldFirst = (original as NSString).lineRange(for: NSRange(location: 0, length: 0)).length
            let newFirst = (updated as NSString).lineRange(for: NSRange(location: 0, length: 0)).length
            newSelection = NSRange(location: max(paragraphs.location, selection.location + newFirst - oldFirst), length: 0)
        } else {
            newSelection = NSRange(location: paragraphs.location, length: (updated as NSString).length)
        }
        return Edit(range: paragraphs, replacement: updated, selection: newSelection)
    }

    /// Moves a caret that would land inside a hidden marker to just after it, or,
    /// when arrowing left out of the marker, to before it (or the end of the line above).
    public static func constrainCaret(from old: NSRange, to new: NSRange, in text: String) -> NSRange {
        let constrained = constrainCaretToVisibleMarkers(from: old, to: new, in: text)
        guard constrained == new else { return constrained }
        return InlineMarkup.constrainCaret(from: old, to: new, in: text)
    }

    private static func constrainCaretToVisibleMarkers(from old: NSRange, to new: NSRange, in text: String) -> NSRange {
        guard new.length == 0,
              let marker = hiddenMarker(in: text, at: new.location),
              new.location >= marker.location,
              new.location < NSMaxRange(marker) else { return new }
        // Only a one-step move left from the text's start counts as leaving the
        // marker (arrow key); clicks inside it land after the marker.
        let movingLeft = old.length == 0 && old.location == NSMaxRange(marker) && new.location == old.location - 1
        let lineStart = (text as NSString).lineRange(for: NSRange(location: marker.location, length: 0)).location
        if movingLeft {
            if marker.location > lineStart {
                return NSRange(location: marker.location, length: 0) // before the marker, after the indentation
            }
            if lineStart > 0 {
                return NSRange(location: lineStart - 1, length: 0) // end of the line above
            }
        }
        return NSRange(location: NSMaxRange(marker), length: 0)
    }

    // MARK: Formatting commands

    /// Bold, italic, underline, strikethrough, or a kind of list, for the
    /// selection. Shared by the keyboard shortcuts and the format menus.
    public static func format(_ format: TextFormat, selection: NSRange, in text: String) -> Edit? {
        switch format {
        case .inline(let style): InlineMarkup.toggle(style, selection: selection, in: text)
        case .list(let style): ListMarker.toggle(style, selection: selection, in: text)
        }
    }

    /// Return inside a list item: a new item below (numbers count up), and the
    /// numbered items that follow at the same depth are renumbered.
    private static func continueList(
        line: String,
        marker: (indent: Int, kind: ListMarker.Kind, length: Int),
        lineRange: NSRange,
        lineContent: NSRange,
        caret: NSRange,
        in string: NSString
    ) -> Edit {
        let indentation = Markdown.indentation(of: line)
        let next = ListMarker.next(after: marker.kind)
        let newMarker = indentation + ListMarker.marker(for: next)
        let rest = string.substring(with: NSRange(location: caret.location, length: NSMaxRange(lineContent) - caret.location))
        var replacement = "\n" + newMarker + rest
        var end = NSMaxRange(lineContent)

        if case .number(var number) = next {
            var location = NSMaxRange(lineRange)
            while location < string.length {
                let followingRange = string.lineRange(for: NSRange(location: location, length: 0))
                let following = string.substring(with: followingRange).trimmingCharacters(in: .newlines)
                let depth = Markdown.indentation(of: following).count
                if depth > marker.indent, !following.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Nested lines belong to the item above; keep them as they are.
                    replacement += "\n" + following
                } else if let item = ListMarker.parse(following), item.indent == marker.indent, case .number = item.kind {
                    number += 1
                    replacement += "\n" + indentation + "\(number). " + String(following.dropFirst(item.indent + item.length))
                } else {
                    break
                }
                end = followingRange.location + (following as NSString).length
                location = NSMaxRange(followingRange)
            }
        }
        return Edit(
            range: NSRange(location: caret.location, length: end - caret.location),
            replacement: replacement,
            selection: NSRange(location: caret.location + 1 + (newMarker as NSString).length, length: 0)
        )
    }

    // MARK: Helpers

    private static func insertion(_ string: String, at range: NSRange) -> Edit {
        Edit(range: range, replacement: string, selection: NSRange(location: range.location + (string as NSString).length, length: 0))
    }

    private static func isIndent(_ character: Character) -> Bool {
        character == "\t" || character == " "
    }
}

/// Everything the format menus and shortcuts can do.
public enum TextFormat: Hashable, Sendable {
    case inline(InlineStyle)
    case list(ListMarker.Style)

    public static let bold = TextFormat.inline(.bold)
    public static let italic = TextFormat.inline(.italic)
    public static let underline = TextFormat.inline(.underline)
    public static let strikethrough = TextFormat.inline(.strikethrough)
    public static let bulletedList = TextFormat.list(.bullet)
    public static let dashedList = TextFormat.list(.dash)
    public static let numberedList = TextFormat.list(.numbered)
    public static let checklist = TextFormat.list(.checklist)

    public static let styles: [TextFormat] = [.bold, .italic, .underline, .strikethrough]
    public static let lists: [TextFormat] = [.bulletedList, .dashedList, .numberedList, .checklist]
    /// Styles then lists; menu items use the index as their tag.
    public static let all: [TextFormat] = styles + lists

    public var title: String {
        switch self {
        case .inline(.bold): "Bold"
        case .inline(.italic): "Italic"
        case .inline(.underline): "Underline"
        case .inline(.strikethrough): "Strikethrough"
        case .list(.bullet): "Bulleted List"
        case .list(.dash): "Dashed List"
        case .list(.numbered): "Numbered List"
        case .list(.checklist): "Checklist"
        }
    }

    public var systemImage: String {
        switch self {
        case .inline(.bold): "bold"
        case .inline(.italic): "italic"
        case .inline(.underline): "underline"
        case .inline(.strikethrough): "strikethrough"
        case .list(.bullet): "list.bullet"
        case .list(.dash): "list.dash"
        case .list(.numbered): "list.number"
        case .list(.checklist): "checklist"
        }
    }

    /// The Apple Notes shortcut: ⌘B, ⌘I, ⌘U, ⇧⌘X, ⇧⌘7, ⇧⌘8, ⇧⌘9, ⇧⌘L.
    public var keyEquivalent: (key: String, shift: Bool) {
        switch self {
        case .inline(.bold): ("b", false)
        case .inline(.italic): ("i", false)
        case .inline(.underline): ("u", false)
        case .inline(.strikethrough): ("x", true)
        case .list(.bullet): ("7", true)
        case .list(.dash): ("8", true)
        case .list(.numbered): ("9", true)
        case .list(.checklist): ("l", true)
        }
    }
}
