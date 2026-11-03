import Foundation
import Testing
@testable import PennsKit

@Suite struct ChecklistTests {
    @Test func parsesItemsAndText() {
        let lines = Checklist.parse("Groceries\n- [ ] milk\n- [x] eggs")
        #expect(lines.count == 3)
        #expect(lines[0] == .text("Groceries"))
        let items = Checklist.items(in: "Groceries\n- [ ] milk\n- [x] eggs")
        #expect(items.map(\.title) == ["milk", "eggs"])
        #expect(items.map(\.isChecked) == [false, true])
    }

    @Test func idsAreStableWhenOtherLinesChange() {
        let before = Checklist.items(in: "- [ ] milk\n- [ ] eggs")
        let after = Checklist.items(in: "Shopping\n- [ ] milk\nnote\n- [ ] eggs")
        #expect(before.map(\.id) == after.map(\.id))
    }

    @Test func duplicateTitlesGetDistinctIDs() {
        let items = Checklist.items(in: "- [ ] water\n- [ ] water")
        #expect(Set(items.map(\.id)).count == 2)
        let toggled = Checklist.toggle(items[1].id, in: "- [ ] water\n- [ ] water")
        #expect(toggled == "- [ ] water\n- [x] water")
    }

    @Test func toggleUnknownIDReturnsNil() {
        #expect(Checklist.toggle("nope", in: "- [ ] a") == nil)
    }

    @Test func allChecked() {
        #expect(!Checklist.allChecked("just text"))
        #expect(!Checklist.allChecked("- [x] a\n- [ ] b"))
        #expect(Checklist.allChecked("Title\n- [x] a\n- [X] b"))
    }

    @Test func markerRangesUseUTF16Offsets() {
        let text = "Café ☕️\n- [ ] milk\n- [x] eggs"
        let ranges = Checklist.markerRanges(in: text)
        let ns = text as NSString
        #expect(ranges.count == 2)
        #expect(ns.substring(with: ranges[0].marker) == "- [ ] ")
        #expect(ns.substring(with: ranges[0].content) == "milk")
        #expect(ns.substring(with: ranges[1].toggle) == "x")
        #expect(ranges[1].isChecked)
    }

    @Test func displayTextAndFirstLine() {
        #expect(Checklist.displayText("- [ ] a\n- [x] b") == "○ a\n✓ b")
        #expect(Checklist.stripMarker("- [x] done") == "done")
    }
}
