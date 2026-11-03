import Foundation
import Testing
@testable import PennsKit

@Suite struct MarkdownTests {
    @Test func headings() {
        #expect(Markdown.heading(of: "# Title") == .init(level: 1, text: "Title", markerLength: 2))
        #expect(Markdown.heading(of: "### Small")?.level == 3)
        #expect(Markdown.heading(of: "#### Too deep") == nil)
        #expect(Markdown.heading(of: "#NoSpace") == nil)
        #expect(Markdown.heading(of: "Not # a heading") == nil)
    }

    @Test func indentAndOutdentLines() {
        #expect(Markdown.indent("a\nb") == "\ta\n\tb")
        #expect(Markdown.indent("a\n") == "\ta\n")
        #expect(Markdown.outdent("\t\ta\n    b\nc") == "\ta\nb\nc")
    }

    @Test func indentedChecklistItems() {
        let text = "Trip\n- [ ] pack\n\t- [ ] socks\n\t- [x] shirts"
        let items = Checklist.items(in: text)
        #expect(items.map(\.title) == ["pack", "socks", "shirts"])
        #expect(items.map(\.indent) == [0, 1, 1])

        let toggled = Checklist.toggle(items[1].id, in: text)
        #expect(toggled == "Trip\n- [ ] pack\n\t- [x] socks\n\t- [x] shirts")

        let ranges = Checklist.markerRanges(in: text)
        let ns = text as NSString
        #expect(ns.substring(with: ranges[1].marker) == "- [ ] ")
        #expect(ns.substring(with: ranges[1].content) == "socks")
        #expect(ns.substring(with: ranges[2].toggle) == "x")
    }

    @Test func displayTextDropsHeadingMarks() {
        #expect(Checklist.displayText("# Plan\n- [ ] a") == "Plan\n○ a")
    }

    @Test func firstLineDropsHeadingMarks() {
        let note = Note(text: "## Groceries\n- [ ] milk")
        #expect(note.firstLine == "Groceries")
    }
}
