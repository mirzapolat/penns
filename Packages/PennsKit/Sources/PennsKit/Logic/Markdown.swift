import Foundation

/// The little Markdown Penns understands: "# ", "## ", "### " headings and
/// tab indentation. Everything else is plain text.
public enum Markdown {
    public struct Heading: Sendable, Hashable {
        /// 1, 2 or 3.
        public let level: Int
        /// Text after the marker.
        public let text: String
        /// Length of "# " / "## " / "### ".
        public let markerLength: Int
    }

    public static func heading(of line: some StringProtocol) -> Heading? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...3).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return Heading(level: hashes, text: String(rest.dropFirst()), markerLength: hashes + 1)
    }

    /// Adds one tab to the start of every line in `lines`.
    public static func indent(_ lines: String) -> String {
        mapLines(lines) { "\t" + $0 }
    }

    /// Removes one tab (or up to four spaces) from the start of every line.
    public static func outdent(_ lines: String) -> String {
        mapLines(lines) { line in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = min(4, line.prefix { $0 == " " }.count)
            return String(line.dropFirst(spaces))
        }
    }

    /// Leading tabs/spaces of `line`.
    public static func indentation(of line: some StringProtocol) -> String {
        String(line.prefix { $0 == "\t" || $0 == " " })
    }

    private static func mapLines(_ text: String, _ transform: (String) -> String) -> String {
        // Keep a trailing newline (from a full paragraph range) untouched.
        let hasTrailingNewline = text.hasSuffix("\n")
        let body = hasTrailingNewline ? String(text.dropLast()) : text
        let mapped = body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { transform(String($0)) }
            .joined(separator: "\n")
        return hasTrailingNewline ? mapped + "\n" : mapped
    }
}
