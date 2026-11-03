import Foundation

/// The Lock Screen widget shows the first few lines of the note, one line each.
/// The iPhone editor draws a faint line where that view ends. Both use this
/// type, so the line is exactly where the widget cuts off.
public enum LockScreenFold {
    public static let lineCount = 3

    /// The lines the rectangular Lock Screen widget shows.
    public static func visibleLines(of text: String) -> [Checklist.Line] {
        Array(Checklist.parse(text.trimmingCharacters(in: .newlines)).prefix(lineCount))
    }

    /// UTF-16 offset in `text` just after the last visible line's content,
    /// or `nil` when the whole note fits on the Lock Screen.
    public static func characterIndex(in text: String) -> Int? {
        let string = text as NSString
        let newlines = CharacterSet.newlines
        func isNewline(_ index: Int) -> Bool {
            guard let scalar = Unicode.Scalar(string.character(at: index)) else { return false }
            return newlines.contains(scalar)
        }

        var location = 0
        while location < string.length, isNewline(location) { location += 1 }

        var lines = 0
        while location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            lines += 1
            let end = NSMaxRange(lineRange)
            if lines == lineCount {
                let rest = string.substring(from: end)
                guard !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                var contentEnd = end
                while contentEnd > lineRange.location, isNewline(contentEnd - 1) { contentEnd -= 1 }
                return contentEnd
            }
            location = end
        }
        return nil
    }
}
