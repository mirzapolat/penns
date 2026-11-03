import Foundation
import Testing
@testable import PennsKit

private func type(_ replacement: String, replacing range: NSRange, in text: String) -> (text: String, caret: NSRange) {
    if let edit = EditorRules.edit(replacing: range, with: replacement, in: text) {
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }
    let result = (text as NSString).replacingCharacters(in: range, with: replacement)
    return (result, NSRange(location: range.location + (replacement as NSString).length, length: 0))
}

private func apply(_ edit: EditorRules.Edit?, to text: String) -> (text: String, selection: NSRange)? {
    guard let edit else { return nil }
    return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
}

private func caret(_ location: Int) -> NSRange { NSRange(location: location, length: 0) }
private func length(_ s: String) -> Int { (s as NSString).length }

@Suite struct ListTypingTests {
    @Test func starSpaceStartsBulletList() {
        let r = type(" ", replacing: caret(1), in: "*")
        #expect(r.text == "• ")
        #expect(r.caret == caret(2))
    }

    @Test func doubleDashSpaceStartsDashedList() {
        let r = type(" ", replacing: caret(3), in: "\t--")
        #expect(r.text == "\t– ")
        #expect(r.caret == caret(3))
    }

    @Test func dashSpaceIsStillAChecklist() {
        #expect(type(" ", replacing: caret(1), in: "-").text == "- [ ] ")
    }

    @Test func starMidLineIsPlainText() {
        #expect(EditorRules.edit(replacing: caret(3), with: " ", in: "a *") == nil)
    }

    @Test func returnContinuesBulletAndDash() {
        #expect(type("\n", replacing: caret(6), in: "• milk").text == "• milk\n• ")
        #expect(type("\n", replacing: caret(7), in: "\t– eggs").text == "\t– eggs\n\t– ")
    }

    @Test func returnCountsUpAndRenumbersTheRest() {
        let text = "1. one\n2. three\n\tnested\n3. four\nafter"
        let r = type("\n", replacing: caret(6), in: text)
        #expect(r.text == "1. one\n2. \n3. three\n\tnested\n4. four\nafter")
        #expect(r.caret == caret(10))
    }

    @Test func returnOnEmptyItemEndsTheList() {
        let r = type("\n", replacing: caret(9), in: "• milk\n• ")
        #expect(r.text == "• milk\n")
        #expect(r.caret == caret(7))
    }

    @Test func backspaceAfterListMarkerRemovesIt() {
        let r = type("", replacing: NSRange(location: 3, length: 1), in: "12. x")
        #expect(r.text == "x")
        #expect(r.caret == caret(0))
        #expect(type("", replacing: NSRange(location: 1, length: 1), in: "• x").text == "x")
    }

    @Test func toggleMakesAndRemovesLists() {
        let text = "milk\neggs\n\nbread"
        let numbered = apply(EditorRules.format(.numberedList, selection: NSRange(location: 0, length: length(text)), in: text), to: text)
        #expect(numbered?.text == "1. milk\n2. eggs\n\n3. bread")
        let plain = apply(EditorRules.format(.numberedList, selection: NSRange(location: 0, length: length(numbered!.text)), in: numbered!.text), to: numbered!.text)
        #expect(plain?.text == text)
    }

    @Test func toggleSwitchesBetweenListKinds() {
        let r = apply(EditorRules.format(.bulletedList, selection: caret(3), in: "- [ ] milk"), to: "- [ ] milk")
        #expect(r?.text == "• milk")
        #expect(r?.selection == caret(6))
    }
}

@Suite struct InlineMarkupTests {
    @Test func findsEachStyle() {
        let text = "**b** _i_ ++u++ ~~s~~"
        let styles = InlineMarkup.spans(in: text).map(\.style)
        #expect(styles == [.bold, .italic, .underline, .strikethrough])
    }

    @Test func nestedStylesBothApply() {
        let spans = InlineMarkup.spans(in: "**_both_**")
        #expect(Set(spans.map(\.style)) == [.bold, .italic])
    }

    @Test func plainTextIsLeftAlone() {
        #expect(InlineMarkup.spans(in: "snake_case_name and 2 * 3 * 4 and a ** b **").isEmpty)
        #expect(InlineMarkup.spans(in: "**not\nacross lines**").isEmpty)
    }

    @Test func stripRemovesMarkers() {
        #expect(InlineMarkup.strip("Buy **milk** and _fresh_ ~~eggs~~") == "Buy milk and fresh eggs")
        #expect(Checklist.displayText("- [ ] **milk**") == "○ milk")
    }

    @Test func firstLineHasNoMarkers() {
        #expect(Note.firstLine(of: "# **Saturday** plans") == "Saturday plans")
    }

    @Test func toggleWrapsSelection() {
        let text = "Buy milk today"
        let r = apply(InlineMarkup.toggle(.bold, selection: NSRange(location: 4, length: 4), in: text), to: text)
        #expect(r?.text == "Buy **milk** today")
        #expect(r?.selection == NSRange(location: 6, length: 4))
    }

    @Test func toggleWithCaretUsesTheWord() {
        let r = apply(InlineMarkup.toggle(.italic, selection: caret(6), in: "Buy milk"), to: "Buy milk")
        #expect(r?.text == "Buy _milk_")
    }

    @Test func toggleTwiceUnwraps() {
        let r = apply(InlineMarkup.toggle(.underline, selection: NSRange(location: 6, length: 4), in: "Buy ++milk++"), to: "Buy ++milk++")
        #expect(r?.text == "Buy milk")
        #expect(r?.selection == NSRange(location: 4, length: 4))
    }

    @Test func toggleSkipsListMarkersAndWorksPerLine() {
        let text = "- [ ] milk\n• eggs"
        let r = apply(InlineMarkup.toggle(.strikethrough, selection: NSRange(location: 0, length: length(text)), in: text), to: text)
        #expect(r?.text == "- [ ] ~~milk~~\n• ~~eggs~~")
    }

    @Test func toggleOnEmptyLineInsertsPair() {
        let r = apply(InlineMarkup.toggle(.bold, selection: caret(0), in: ""), to: "")
        #expect(r?.text == "****")
        #expect(r?.selection == caret(2))
    }

    @Test func backspaceAfterStyledWordDeletesItsLastLetter() {
        // Caret after "**milk**": deleting would hit the closing marker.
        let text = "**milk**"
        let r = type("", replacing: NSRange(location: 7, length: 1), in: text)
        #expect(r.text == "**mil**")
        #expect(r.caret == caret(5))
    }

    @Test func backspaceOnSingleLetterSpanRemovesIt() {
        let r = type("", replacing: NSRange(location: 4, length: 1), in: "a _b_")
        #expect(r.text == "a ")
    }

    @Test func caretStepsOverHiddenMarkers() {
        let text = "a **bc** d"
        // Right from before the opening marker lands after "b".
        #expect(EditorRules.constrainCaret(from: caret(2), to: caret(3), in: text) == caret(5))
        // Left from after the closing marker lands before "c".
        #expect(EditorRules.constrainCaret(from: caret(8), to: caret(7), in: text) == caret(5))
        // A click between the two stars lands after the marker.
        #expect(EditorRules.constrainCaret(from: caret(0), to: caret(3), in: text) == caret(4))
    }

    @Test func attributedDropsMarkers() {
        let attributed = InlineMarkup.attributed("Buy **milk** now")
        #expect(String(attributed.characters) == "Buy milk now")
        let bold = attributed.runs.first { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        #expect(bold.map { String(attributed[$0.range].characters) } == "milk")
    }
}
