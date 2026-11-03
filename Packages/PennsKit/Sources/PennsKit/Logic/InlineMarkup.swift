import Foundation
import SwiftUI

/// Bold, italic, underline and strikethrough, stored in the plain text as
/// hidden markers: `**bold**`, `_italic_`, `++underline++`, `~~strike~~`.
/// Each style uses its own character, so styles nest without ambiguity
/// (`**_both_**`). Markers never cross a line break.
public enum InlineStyle: String, CaseIterable, Sendable {
    case bold, italic, underline, strikethrough

    public var marker: String {
        switch self {
        case .bold: "**"
        case .italic: "_"
        case .underline: "++"
        case .strikethrough: "~~"
        }
    }

    var pattern: String {
        switch self {
        case .bold: #"(?<!\*)\*\*(?=[^\s*])([^\n]*?[^\s*])\*\*(?!\*)"#
        // Word-bounded so snake_case and URLs stay plain.
        case .italic: #"(?<![\w_])_(?=[^\s_])([^\n_]*?[^\s_])_(?![\w_])"#
        case .underline: #"(?<!\+)\+\+(?=[^\s+])([^\n]*?[^\s+])\+\+(?!\+)"#
        case .strikethrough: #"(?<!~)~~(?=[^\s~])([^\n]*?[^\s~])~~(?!~)"#
        }
    }
}

public enum InlineMarkup {
    /// One styled run. Ranges are UTF-16 (`NSString`) offsets.
    public struct Span: Equatable, Sendable {
        public let style: InlineStyle
        /// Markers plus content.
        public let full: NSRange
        public let content: NSRange
        public var open: NSRange { NSRange(location: full.location, length: content.location - full.location) }
        public var close: NSRange { NSRange(location: NSMaxRange(content), length: NSMaxRange(full) - NSMaxRange(content)) }
    }

    private static let expressions: [InlineStyle: NSRegularExpression] = Dictionary(
        uniqueKeysWithValues: InlineStyle.allCases.map { ($0, try! NSRegularExpression(pattern: $0.pattern)) }
    )

    public static func spans(in text: String) -> [Span] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        var result: [Span] = []
        for style in InlineStyle.allCases {
            guard let expression = expressions[style] else { continue }
            for match in expression.matches(in: text, range: whole) {
                result.append(Span(style: style, full: match.range, content: match.range(at: 1)))
            }
        }
        return result.sorted { $0.full.location < $1.full.location }
    }

    /// All hidden marker ranges, sorted.
    public static func markers(in text: String) -> [NSRange] {
        spans(in: text).flatMap { [$0.open, $0.close] }.sorted { $0.location < $1.location }
    }

    /// `text` without markers, for sharing, the menu bar and anything read-only.
    public static func strip(_ text: String) -> String {
        let markers = markers(in: text)
        guard !markers.isEmpty else { return text }
        let result = NSMutableString(string: text)
        for marker in markers.reversed() {
            result.replaceCharacters(in: marker, with: "")
        }
        return result as String
    }

    // MARK: Styled text for widgets and read-only views

    /// `line` without markers, styled. Bold and italic use presentation intents
    /// so they follow whatever font the view sets.
    public static func attributed(_ line: String) -> AttributedString {
        let string = line as NSString
        let spans = spans(in: line)
        guard !spans.isEmpty else { return AttributedString(line) }
        let hidden = spans.flatMap { [$0.open, $0.close] }

        var result = AttributedString()
        var location = 0
        while location < string.length {
            if let marker = hidden.first(where: { $0.location == location && $0.length > 0 }) {
                location = NSMaxRange(marker)
                continue
            }
            // Extend the run until the next marker boundary.
            let next = hidden.map(\.location).filter { $0 > location }.min() ?? string.length
            let run = NSRange(location: location, length: next - location)
            var piece = AttributedString(string.substring(with: run))
            let active = Set(spans.filter { NSLocationInRange(location, $0.content) }.map(\.style))
            var intent: InlinePresentationIntent = []
            if active.contains(.bold) { intent.insert(.stronglyEmphasized) }
            if active.contains(.italic) { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if active.contains(.underline) { piece.underlineStyle = .single }
            if active.contains(.strikethrough) { piece.strikethroughStyle = .single }
            result += piece
            location = next
        }
        return result
    }

    // MARK: Editing

    /// Applies `style` to the selection (or the word at the caret), or removes it
    /// when the selection already has it. Works line by line for multi-line
    /// selections, leaving list, checklist and heading markers outside.
    public static func toggle(_ style: InlineStyle, selection: NSRange, in text: String) -> EditorRules.Edit? {
        let string = text as NSString
        guard NSMaxRange(selection) <= string.length else { return nil }
        let marker = style.marker
        let markerLength = (marker as NSString).length

        var target = selection
        if target.length == 0 {
            guard let word = wordRange(at: selection.location, in: string) else {
                // Nothing to wrap: an empty pair, caret inside, ready to type.
                return EditorRules.Edit(
                    range: selection,
                    replacement: marker + marker,
                    selection: NSRange(location: selection.location + markerLength, length: 0)
                )
            }
            target = word
        }

        // Inside an existing span of this style: unwrap it.
        if let span = spans(in: text).first(where: {
            $0.style == style && (
                (target.location >= $0.content.location && NSMaxRange(target) <= NSMaxRange($0.content))
                    || NSEqualRanges(target, $0.full)
            )
        }) {
            let content = string.substring(with: span.content)
            let shifted = max(span.full.location, selection.location - span.open.length)
            let length = min(selection.length, (content as NSString).length)
            return EditorRules.Edit(range: span.full, replacement: content, selection: NSRange(location: shifted, length: length))
        }

        // Wrap each line's selected content.
        let paragraphs = string.lineRange(for: target)
        var output = ""
        var firstWrapped: NSRange?
        var lastWrappedEnd = 0
        var location = paragraphs.location
        while location < NSMaxRange(paragraphs) {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let line = string.substring(with: lineRange)
            let newline = line.hasSuffix("\n") ? "\n" : ""
            let contentEnd = NSMaxRange(lineRange) - (newline.isEmpty ? 0 : 1)
            let bodyStart = min(lineRange.location + prefixLength(of: line), contentEnd)

            let body = NSRange(location: bodyStart, length: contentEnd - bodyStart)
            let segment = trimmed(NSIntersectionRange(target, body), in: string)

            let base = (output as NSString).length + paragraphs.location
            if segment.length == 0 {
                output += line
            } else {
                let before = string.substring(with: NSRange(location: lineRange.location, length: segment.location - lineRange.location))
                let inner = stripStyle(style, from: string.substring(with: segment))
                let after = string.substring(with: NSRange(location: NSMaxRange(segment), length: NSMaxRange(lineRange) - NSMaxRange(segment)))
                let innerLength = (inner as NSString).length
                let wrappedStart = base + (before as NSString).length + markerLength
                if firstWrapped == nil { firstWrapped = NSRange(location: wrappedStart, length: innerLength) }
                lastWrappedEnd = wrappedStart + innerLength
                output += before + marker + inner + marker + after
            }
            location = NSMaxRange(lineRange)
        }
        guard let first = firstWrapped else { return nil }
        let newSelection = selection.length == 0
            ? NSRange(location: min(lastWrappedEnd, selection.location + markerLength), length: 0)
            : NSRange(location: first.location, length: lastWrappedEnd - first.location)
        return EditorRules.Edit(range: paragraphs, replacement: output, selection: newSelection)
    }

    /// Backspace that would delete part of a hidden marker deletes the visible
    /// character next to it instead, so a style never half-breaks.
    static func backspace(_ range: NSRange, in text: String) -> EditorRules.Edit? {
        let string = text as NSString
        for span in spans(in: text) {
            if NSLocationInRange(range.location, span.close) {
                // Caret after a styled word: delete its last character.
                let last = string.rangeOfComposedCharacterSequence(at: NSMaxRange(span.content) - 1)
                if last.length >= span.content.length {
                    return EditorRules.Edit(range: span.full, replacement: "", selection: NSRange(location: span.full.location, length: 0))
                }
                return EditorRules.Edit(range: last, replacement: "", selection: NSRange(location: last.location, length: 0))
            }
            if NSLocationInRange(range.location, span.open) {
                // Caret at the start of a styled word: delete what's before it.
                guard span.open.location > 0 else {
                    return EditorRules.Edit(range: NSRange(location: 0, length: 0), replacement: "", selection: NSRange(location: 0, length: 0))
                }
                let previous = string.rangeOfComposedCharacterSequence(at: span.open.location - 1)
                return EditorRules.Edit(range: previous, replacement: "", selection: NSRange(location: previous.location, length: 0))
            }
        }
        return nil
    }

    /// Hidden markers take no visible space, so the caret steps over them: one
    /// arrow press always moves past one visible character.
    static func constrainCaret(from old: NSRange, to new: NSRange, in text: String) -> NSRange {
        guard new.length == 0 else { return new }
        let markers = markers(in: text)
        guard !markers.isEmpty else { return new }
        let string = text as NSString

        func marker(startingAt location: Int) -> NSRange? { markers.first { $0.location == location } }
        func marker(endingAt location: Int) -> NSRange? { markers.first { NSMaxRange($0) == location } }
        func isNewline(_ location: Int) -> Bool {
            location >= 0 && location < string.length
                && (string.character(at: location) == 10 || string.character(at: location) == 13)
        }

        let movingRight = old.length == 0 && new.location == old.location + 1
        let movingLeft = old.length == 0 && new.location == old.location - 1

        if movingRight, marker(startingAt: old.location) != nil {
            var location = old.location
            while let next = marker(startingAt: location) { location = NSMaxRange(next) }
            if location < string.length, !isNewline(location) {
                location = NSMaxRange(string.rangeOfComposedCharacterSequence(at: location))
            }
            return NSRange(location: location, length: 0)
        }
        if movingLeft, marker(endingAt: old.location) != nil {
            var location = old.location
            while let previous = marker(endingAt: location) { location = previous.location }
            if location > 0, !isNewline(location - 1) {
                location = string.rangeOfComposedCharacterSequence(at: location - 1).location
            }
            return NSRange(location: location, length: 0)
        }
        // A click between the two characters of "**" lands after the marker.
        if let inside = markers.first(where: { new.location > $0.location && new.location < NSMaxRange($0) }) {
            return NSRange(location: NSMaxRange(inside), length: 0)
        }
        return new
    }

    // MARK: Helpers

    /// Indentation plus any heading, checklist or list marker at the start of `line`.
    private static func prefixLength(of line: String) -> Int {
        if let heading = Markdown.heading(of: line) { return heading.markerLength }
        if let marker = Checklist.parseMarker(line) { return marker.indent + Checklist.markerLength }
        if let marker = ListMarker.parse(line) { return marker.indent + marker.length }
        return Markdown.indentation(of: line).count
    }

    private static func trimmed(_ range: NSRange, in string: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        let whitespace = CharacterSet.whitespacesAndNewlines
        func isSpace(_ index: Int) -> Bool {
            Unicode.Scalar(string.character(at: index)).map(whitespace.contains) ?? false
        }
        while start < end, isSpace(start) { start += 1 }
        while end > start, isSpace(end - 1) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func stripStyle(_ style: InlineStyle, from text: String) -> String {
        let result = NSMutableString(string: text)
        for span in spans(in: text).filter({ $0.style == style }).reversed() {
            result.replaceCharacters(in: span.close, with: "")
            result.replaceCharacters(in: span.open, with: "")
        }
        return result as String
    }

    /// The word around `location` (letters, digits, apostrophes), within one line.
    private static func wordRange(at location: Int, in string: NSString) -> NSRange? {
        func isWord(_ index: Int) -> Bool {
            guard index >= 0, index < string.length else { return false }
            guard let scalar = Unicode.Scalar(string.character(at: index)) else { return true } // surrogate halves
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "’"
        }
        var start = location
        var end = location
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }
}
