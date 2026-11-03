import Testing
@testable import PennsKit

@Suite struct LockScreenFoldTests {
    @Test func noFoldWhenEverythingFits() {
        #expect(LockScreenFold.characterIndex(in: "") == nil)
        #expect(LockScreenFold.characterIndex(in: "One\nTwo\nThree") == nil)
        #expect(LockScreenFold.characterIndex(in: "One\nTwo\nThree\n\n  \n") == nil)
    }

    @Test func foldsAfterTheThirdLine() {
        // "One\nTwo\nThree" is 13 UTF-16 units.
        #expect(LockScreenFold.characterIndex(in: "One\nTwo\nThree\nFour") == 13)
    }

    @Test func leadingBlankLinesDontCount() {
        // The widget trims leading newlines, so the fold does too.
        #expect(LockScreenFold.characterIndex(in: "\n\nOne\nTwo\nThree\nFour") == 15)
    }

    @Test func visibleLinesMatchTheFold() {
        let text = "\nBuy\n- [ ] Milk\n- [x] Eggs\nBread"
        #expect(LockScreenFold.visibleLines(of: text).count == 3)
        #expect(LockScreenFold.characterIndex(in: text) == 26)
    }
}
