import Foundation
import Testing
@testable import ScoreEdit

struct LineIndexTests {

    @Test func emptyTextHasSingleLine() {
        let starts = LineIndex.lineStartOffsets("")
        #expect(starts == [0])
        #expect(LineIndex.lineNumber(forUTF16Offset: 0, in: starts) == 1)
    }

    @Test func offsetsForSimpleLines() {
        let starts = LineIndex.lineStartOffsets("ab\ncd\ne")
        #expect(starts == [0, 3, 6])
    }

    @Test func trailingNewlineStartsAnEmptyLastLine() {
        let starts = LineIndex.lineStartOffsets("a\n")
        #expect(starts == [0, 2])
        #expect(LineIndex.lineNumber(forUTF16Offset: 2, in: starts) == 2)
    }

    @Test func countsCRLFAsOneLineBreak() {
        let starts = LineIndex.lineStartOffsets("a\r\nb")
        #expect(starts == [0, 3])
        #expect(LineIndex.lineNumber(forUTF16Offset: 3, in: starts) == 2)
    }

    @Test func countsSurrogatePairsAsTwoUnits() {
        // 𝄞 occupies two UTF-16 code units.
        let starts = LineIndex.lineStartOffsets("𝄞\nx")
        #expect(starts == [0, 3])
        #expect(LineIndex.lineNumber(forUTF16Offset: 2, in: starts) == 1)
        #expect(LineIndex.lineNumber(forUTF16Offset: 3, in: starts) == 2)
    }

    @Test func lineNumberAtBoundaries() {
        let starts = LineIndex.lineStartOffsets("ab\ncd\ne")  // [0, 3, 6]
        #expect(LineIndex.lineNumber(forUTF16Offset: 0, in: starts) == 1)
        #expect(LineIndex.lineNumber(forUTF16Offset: 2, in: starts) == 1)
        #expect(LineIndex.lineNumber(forUTF16Offset: 3, in: starts) == 2)
        #expect(LineIndex.lineNumber(forUTF16Offset: 5, in: starts) == 2)
        #expect(LineIndex.lineNumber(forUTF16Offset: 6, in: starts) == 3)
    }

    @Test func offsetPastEndMapsToLastLine() {
        let starts = LineIndex.lineStartOffsets("ab\ncd")
        #expect(LineIndex.lineNumber(forUTF16Offset: 100, in: starts) == 2)
    }
}
