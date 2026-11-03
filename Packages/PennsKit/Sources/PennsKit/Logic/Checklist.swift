import Foundation

/// Checklist lines live in the plain text as "- [ ] item" / "- [x] item",
/// optionally indented with tabs or spaces.
public enum Checklist {
    public static let uncheckedMarker = "- [ ] "
    public static let checkedMarker = "- [x] "
    static let markerLength = 6

    public struct Item: Sendable, Hashable, Identifiable {
        /// Stable across processes and edits elsewhere in the note:
        /// a hash of the title plus its occurrence among identical titles.
        public let id: String
        public let title: String
        public let isChecked: Bool
        /// Leading tabs/spaces before the marker.
        public let indent: Int
    }

    public enum Line: Sendable, Hashable {
        case text(String)
        case item(Item)
    }

    /// Ranges of one checklist line in UTF-16 (`NSString`) units, for editors.
    public struct MarkerRange: Sendable, Hashable {
        /// The "- [ ] " prefix.
        public let marker: NSRange
        /// Text after the marker, without the line break.
        public let content: NSRange
        /// The single character between the brackets.
        public let toggle: NSRange
        public let isChecked: Bool
    }

    /// Leading whitespace length and checked state, if `line` is a checklist item.
    static func parseMarker(_ line: some StringProtocol) -> (indent: Int, checked: Bool)? {
        let indent = line.prefix { $0 == "\t" || $0 == " " }.count
        let rest = line.dropFirst(indent)
        if rest.hasPrefix(uncheckedMarker) { return (indent, false) }
        if rest.hasPrefix(checkedMarker) || rest.hasPrefix("- [X] ") { return (indent, true) }
        return nil
    }

    /// Checked state and the length of indent + marker, if `line` is a checklist item.
    public static func marker(of line: some StringProtocol) -> (checked: Bool, length: Int)? {
        guard let marker = parseMarker(line) else { return nil }
        return (marker.checked, marker.indent + markerLength)
    }

    public static func stripMarker(_ line: String) -> String {
        guard let marker = parseMarker(line) else { return line }
        return String(line.dropFirst(marker.indent + markerLength))
    }

    public static func parse(_ text: String) -> [Line] {
        var occurrences: [String: Int] = [:]
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            guard let marker = parseMarker(raw) else { return .text(String(raw)) }
            let title = String(raw.dropFirst(marker.indent + markerLength))
            let key = title.trimmingCharacters(in: .whitespaces)
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            return .item(Item(
                id: "\(stableHash(key))-\(occurrence)",
                title: title,
                isChecked: marker.checked,
                indent: marker.indent
            ))
        }
    }

    public static func items(in text: String) -> [Item] {
        parse(text).compactMap { line in
            if case .item(let item) = line { return item }
            return nil
        }
    }

    /// True when the note has at least one checklist item and all are checked.
    public static func allChecked(_ text: String) -> Bool {
        let items = items(in: text)
        return !items.isEmpty && items.allSatisfy(\.isChecked)
    }

    /// Returns `text` with the item toggled, or `nil` if no item has that id.
    public static func toggle(_ itemID: String, in text: String) -> String? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let parsed = parse(text)
        guard let index = parsed.firstIndex(where: { line in
            if case .item(let item) = line { return item.id == itemID }
            return false
        }), case .item(let item) = parsed[index] else { return nil }
        let indent = String(lines[index].prefix(item.indent))
        lines[index] = indent + (item.isChecked ? uncheckedMarker : checkedMarker) + item.title
        return lines.joined(separator: "\n")
    }

    /// Text for read-only surfaces: markers become "○ " / "✓ ", heading marks and
    /// bold/italic/underline/strikethrough markers are dropped.
    public static func displayText(_ text: String) -> String {
        parse(InlineMarkup.strip(text)).map { line in
            switch line {
            case .text(let string):
                Markdown.heading(of: string)?.text ?? string
            case .item(let item):
                String(repeating: "  ", count: item.indent) + (item.isChecked ? "✓ " : "○ ") + item.title
            }
        }.joined(separator: "\n")
    }

    public static func markerRanges(in text: String) -> [MarkerRange] {
        let string = text as NSString
        var result: [MarkerRange] = []
        var location = 0
        while location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let line = string.substring(with: lineRange)
            if let marker = parseMarker(line) {
                var contentEnd = NSMaxRange(lineRange)
                if line.hasSuffix("\n") { contentEnd -= 1 }
                let markerStart = lineRange.location + marker.indent // tabs/spaces are 1 UTF-16 unit
                let contentStart = markerStart + markerLength
                result.append(MarkerRange(
                    marker: NSRange(location: markerStart, length: markerLength),
                    content: NSRange(location: contentStart, length: max(0, contentEnd - contentStart)),
                    toggle: NSRange(location: markerStart + 3, length: 1),
                    isChecked: marker.checked
                ))
            }
            location = NSMaxRange(lineRange)
        }
        return result
    }

    /// FNV-1a. Unlike `Hasher`, the result is identical in every process.
    static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
