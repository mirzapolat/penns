import Foundation
import Testing
@testable import PennsKit

/// Applies an edit (or the raw typing when the rules return nil) and returns
/// the resulting text and caret, mirroring what the editors do.
private func type(_ replacement: String, replacing range: NSRange, in text: String) -> (text: String, caret: NSRange) {
    if let edit = EditorRules.edit(replacing: range, with: replacement, in: text) {
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (result, edit.selection)
    }
    let result = (text as NSString).replacingCharacters(in: range, with: replacement)
    return (result, NSRange(location: range.location + (replacement as NSString).length, length: 0))
}

private func caret(_ location: Int) -> NSRange { NSRange(location: location, length: 0) }
private func length(_ s: String) -> Int { (s as NSString).length }

@Suite struct ChecklistTypingTests {
    @Test func dashSpaceStartsItem() {
        let r = type(" ", replacing: caret(1), in: "-")
        #expect(r.text == "- [ ] ")
        #expect(r.caret == caret(6))
    }

    @Test func dashSpaceAfterIndentationStartsIndentedItem() {
        let r = type(" ", replacing: caret(2), in: "\t-")
        #expect(r.text == "\t- [ ] ")
        #expect(r.caret == caret(7))
    }

    @Test func dashSpaceMidLineIsPlainText() {
        #expect(EditorRules.edit(replacing: caret(3), with: " ", in: "a -") == nil)
    }

    @Test func returnContinuesItemWithIndentation() {
        let text = "\t- [ ] milk"
        let r = type("\n", replacing: caret(length(text)), in: text)
        #expect(r.text == "\t- [ ] milk\n\t- [ ] ")
        #expect(r.caret == caret(length(r.text)))
    }

    @Test func returnOnEmptyItemRemovesCheckbox() {
        let text = "- [ ] milk\n- [ ] "
        let r = type("\n", replacing: caret(length(text)), in: text)
        #expect(r.text == "- [ ] milk\n")
        #expect(r.caret == caret(11))
    }

    @Test func returnOnEmptyItemRemovesCheckboxEvenWithCaretInsideMarker() {
        let text = "- [ ] "
        let r = type("\n", replacing: caret(2), in: text)
        #expect(r.text == "")
    }

    @Test func backspaceAtItemStartRemovesWholeMarker() {
        let text = "\t- [x] done"
        let markerEnd = 7
        let r = type("", replacing: NSRange(location: markerEnd - 1, length: 1), in: text)
        #expect(r.text == "\tdone")
        #expect(r.caret == caret(1))
    }

    @Test func backspaceInsideItemTextIsNormal() {
        #expect(EditorRules.edit(replacing: NSRange(location: 8, length: 1), with: "", in: "- [ ] milk") == nil)
    }
}

@Suite struct HeadingTypingTests {
    @Test func backspaceAtHeadingStartRemovesMarks() {
        let text = "Intro\n## Plan"
        let r = type("", replacing: NSRange(location: 8, length: 1), in: text)
        #expect(r.text == "Intro\nPlan")
        #expect(r.caret == caret(6))
    }

    @Test func backspaceOnEmptyHeadingRemovesMarks() {
        let r = type("", replacing: NSRange(location: 1, length: 1), in: "# ")
        #expect(r.text == "")
    }

    @Test func caretIsKeptOutOfHeadingMarks() {
        let text = "Intro\n## Plan"
        // Clicking at the line start lands after the hidden marks.
        #expect(EditorRules.constrainCaret(from: caret(0), to: caret(6), in: text) == caret(9))
        // Arrowing left from the heading text jumps to the end of the line above.
        #expect(EditorRules.constrainCaret(from: caret(9), to: caret(8), in: text) == caret(5))
        // Outside markers nothing changes.
        #expect(EditorRules.constrainCaret(from: caret(0), to: caret(11), in: text) == caret(11))
    }

    @Test func caretIsKeptOutOfChecklistMarker() {
        let text = "\t- [ ] socks"
        #expect(EditorRules.constrainCaret(from: caret(12), to: caret(3), in: text) == caret(7))
        // Moving left out of an indented marker stops before it, after the tab.
        #expect(EditorRules.constrainCaret(from: caret(7), to: caret(6), in: text) == caret(1))
    }
}

@Suite struct IndentationTests {
    @Test func tabIndentsCurrentLineAndKeepsCaret() {
        let text = "one\ntwo"
        let edit = EditorRules.shiftLines(caret(5), in: text, indent: true)!
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        #expect(result == "one\n\ttwo")
        #expect(edit.selection == caret(6))
    }

    @Test func tabIndentsEverySelectedLine() {
        let text = "a\nb\nc"
        let edit = EditorRules.shiftLines(NSRange(location: 0, length: 3), in: text, indent: true)!
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        #expect(result == "\ta\n\tb\nc")
        #expect(edit.selection == NSRange(location: 0, length: 6))
    }

    @Test func shiftTabOutdentsAndStopsAtZero() {
        let text = "\t- [ ] socks"
        let edit = EditorRules.shiftLines(caret(9), in: text, indent: false)!
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        #expect(result == "- [ ] socks")
        #expect(edit.selection == caret(8))
        #expect(EditorRules.shiftLines(caret(0), in: result, indent: false) == nil)
    }

    @Test func returnKeepsIndentationOnPlainLines() {
        let text = "\tnote"
        let r = type("\n", replacing: caret(5), in: text)
        #expect(r.text == "\tnote\n\t")
    }

    @Test func returnOnEmptyIndentedLineDropsIndentation() {
        let text = "\tnote\n\t"
        let r = type("\n", replacing: caret(7), in: text)
        #expect(r.text == "\tnote\n")
    }
}
