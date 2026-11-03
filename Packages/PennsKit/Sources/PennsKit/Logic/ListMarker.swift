import Foundation

/// Bulleted, dashed and numbered lists live in the plain text as visible
/// characters: "• item", "– item", "1. item", optionally indented. That way the
/// widget, sharing and Shortcuts show them without any translation.
public enum ListMarker {
    public enum Kind: Equatable, Sendable {
        case bullet
        case dash
        case number(Int)
    }

    public static let bullet = "• "
    public static let dash = "– "

    /// Indentation length, kind and marker length (both in UTF-16 units) if
    /// `line` is a list item.
    public static func parse(_ line: some StringProtocol) -> (indent: Int, kind: Kind, length: Int)? {
        let indent = line.prefix { $0 == "\t" || $0 == " " }.count
        let rest = line.dropFirst(indent)
        if rest.hasPrefix(bullet) { return (indent, .bullet, 2) }
        if rest.hasPrefix(dash) { return (indent, .dash, 2) }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard (1...3).contains(digits.count),
              rest.dropFirst(digits.count).hasPrefix(". "),
              let number = Int(digits) else { return nil }
        return (indent, .number(number), digits.count + 2)
    }

    public static func marker(for kind: Kind) -> String {
        switch kind {
        case .bullet: bullet
        case .dash: dash
        case .number(let number): "\(number). "
        }
    }

    public static func next(after kind: Kind) -> Kind {
        if case .number(let number) = kind { return .number(number + 1) }
        return kind
    }

    /// The marker range (after indentation) of the list line containing `location`.
    public static func markerRange(in text: String, at location: Int) -> NSRange? {
        let string = text as NSString
        guard location >= 0, location <= string.length else { return nil }
        let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
        guard let marker = parse(string.substring(with: lineRange)) else { return nil }
        return NSRange(location: lineRange.location + marker.indent, length: marker.length)
    }

    // MARK: Turning lines into lists

    public enum Style: Equatable, Sendable {
        case bullet, dash, numbered, checklist
    }

    /// Makes every line the selection touches a list item of `style`, or plain
    /// lines again when they all already are. Headings are left alone.
    public static func toggle(_ style: Style, selection: NSRange, in text: String) -> EditorRules.Edit? {
        let string = text as NSString
        guard NSMaxRange(selection) <= string.length else { return nil }
        let paragraphs = string.lineRange(for: selection)
        let original = string.substring(with: paragraphs)
        let hasTrailingNewline = original.hasSuffix("\n")
        var lines = (hasTrailingNewline ? String(original.dropLast()) : original)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let candidates = lines.indices.filter { index in
            Markdown.heading(of: lines[index]) == nil
                && (lines.count == 1 || !lines[index].trimmingCharacters(in: .whitespaces).isEmpty)
        }
        guard !candidates.isEmpty else { return nil }
        let removing = candidates.allSatisfy { matches(style, lines[$0]) }

        var number = 0
        for index in candidates {
            let (indentation, body) = split(lines[index])
            if removing {
                lines[index] = indentation + body
            } else {
                number += 1
                lines[index] = indentation + prefix(for: style, number: number) + body
            }
        }

        var updated = lines.joined(separator: "\n")
        if hasTrailingNewline { updated += "\n" }
        let newSelection: NSRange
        if selection.length == 0, candidates.count == 1 {
            // Caret to the end of the line, ready to type.
            let lineLength = (lines[candidates[0]] as NSString).length
            let before = lines[..<candidates[0]].reduce(0) { $0 + ($1 as NSString).length + 1 }
            newSelection = NSRange(location: paragraphs.location + before + lineLength, length: 0)
        } else {
            let length = (updated as NSString).length - (hasTrailingNewline ? 1 : 0)
            newSelection = NSRange(location: paragraphs.location, length: length)
        }
        return EditorRules.Edit(range: paragraphs, replacement: updated, selection: newSelection)
    }

    private static func matches(_ style: Style, _ line: String) -> Bool {
        if style == .checklist { return Checklist.parseMarker(line) != nil }
        guard let marker = parse(line) else { return false }
        switch (style, marker.kind) {
        case (.bullet, .bullet), (.dash, .dash), (.numbered, .number): return true
        default: return false
        }
    }

    /// Indentation and the text after any list or checklist marker.
    private static func split(_ line: String) -> (String, String) {
        let indentation = Markdown.indentation(of: line)
        if let marker = Checklist.parseMarker(line) {
            return (indentation, String(line.dropFirst(marker.indent + Checklist.markerLength)))
        }
        if let marker = parse(line) {
            return (indentation, String(line.dropFirst(marker.indent + marker.length)))
        }
        return (indentation, String(line.dropFirst(indentation.count)))
    }

    private static func prefix(for style: Style, number: Int) -> String {
        switch style {
        case .bullet: bullet
        case .dash: dash
        case .numbered: "\(number). "
        case .checklist: Checklist.uncheckedMarker
        }
    }
}
