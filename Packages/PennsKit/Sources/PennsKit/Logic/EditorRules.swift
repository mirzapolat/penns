import Foundation

/// The editor's typing rules as pure functions on text + selection, shared by
/// the Mac and iOS editors. Ranges are UTF-16 (`NSString`) offsets.
///
/// Rules:
/// - "-" followed by a space at the start of a line (after any indentation) starts a checklist item.
/// - Return continues a checklist item or the line's indentation; on an empty item
///   or an empty indented line it ends the list instead.
/// - Backspace right after a hidden marker (heading "# " or checklist "- [ ] ")
///   removes the whole marker.
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

    // MARK: Helpers

    private static func insertion(_ string: String, at range: NSRange) -> Edit {
        Edit(range: range, replacement: string, selection: NSRange(location: range.location + (string as NSString).length, length: 0))
    }

    private static func isIndent(_ character: Character) -> Bool {
        character == "\t" || character == " "
    }
}
