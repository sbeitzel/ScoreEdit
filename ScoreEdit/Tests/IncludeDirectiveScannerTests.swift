import Foundation
import Testing
@testable import ScoreEdit

struct IncludeDirectiveScannerTests {

    // MARK: - Matching

    @Test func findsBasicInclude() {
        let text = "X:1\nI:abc-include tune.abh\nK:C\n"
        let found = IncludeDirectiveScanner.scan(text)
        #expect(found == [
            IncludeDirective(
                lineNumber: 2,
                utf16LineRange: NSRange(location: 4, length: 22),
                fileName: "tune.abh"
            )
        ])
    }

    @Test func matchesCaseInsensitivePayload() {
        let found = IncludeDirectiveScanner.scan("I:ABC-Include tune.abh")
        #expect(found.count == 1)
        #expect(found.first?.fileName == "tune.abh")
    }

    @Test func trimsPayloadWhitespace() {
        let found = IncludeDirectiveScanner.scan("I:   abc-include   dir/tune.abh  ")
        #expect(found.first?.fileName == "dir/tune.abh")
    }

    @Test func matchesWithoutSeparatorAfterKeyword() {
        // CeolKit's IncludeExpander does a bare prefix match, so
        // "I:abc-includefoo.abh" includes "foo.abh". Mirror that.
        let found = IncludeDirectiveScanner.scan("I:abc-includefoo.abh")
        #expect(found.first?.fileName == "foo.abh")
    }

    @Test func findsMultipleIncludes() {
        let text = "I:abc-include a.abh\nX:1\nI:abc-include b.abh"
        let found = IncludeDirectiveScanner.scan(text)
        #expect(found.map(\.lineNumber) == [1, 3])
        #expect(found.map(\.fileName) == ["a.abh", "b.abh"])
    }

    // MARK: - Non-matches

    @Test func ignoresDirectiveStyleInclude() {
        // %%abc-include is a directive, not an information field; CeolKit
        // never expands it.
        #expect(IncludeDirectiveScanner.scan("%%abc-include tune.abh").isEmpty)
    }

    @Test func ignoresLowercaseFieldCode() {
        #expect(IncludeDirectiveScanner.scan("i:abc-include tune.abh").isEmpty)
    }

    @Test func ignoresIndentedLine() {
        // The line classifier only recognizes information fields at column 0.
        #expect(IncludeDirectiveScanner.scan("  I:abc-include tune.abh").isEmpty)
    }

    @Test func ignoresCommentedLine() {
        #expect(IncludeDirectiveScanner.scan("%I:abc-include tune.abh").isEmpty)
    }

    @Test func ignoresEmptyFileName() {
        #expect(IncludeDirectiveScanner.scan("I:abc-include").isEmpty)
        #expect(IncludeDirectiveScanner.scan("I:abc-include    ").isEmpty)
    }

    @Test func ignoresOtherInformationFields() {
        #expect(IncludeDirectiveScanner.scan("I:abc-version 2.2\nT:Title").isEmpty)
    }

    @Test func handlesEmptyText() {
        #expect(IncludeDirectiveScanner.scan("").isEmpty)
    }

    // MARK: - Line numbers and ranges

    @Test func handlesCRLFLineEndings() {
        let text = "X:1\r\nI:abc-include a.abh\r\nK:C\r\n"
        let found = IncludeDirectiveScanner.scan(text)
        #expect(found.count == 1)
        #expect(found.first?.lineNumber == 2)
        #expect(found.first?.fileName == "a.abh")
        // Range covers the visible content only, excluding the trailing CR.
        #expect(found.first?.utf16LineRange == NSRange(location: 5, length: 19))
    }

    @Test func utf16RangesAccountForNonASCII() {
        // "T:Café №5" is 9 UTF-16 units; "T:𝄞" is 4 (the clef is a surrogate
        // pair), so the include line starts at 10 + 5 = 15.
        let text = "T:Café №5\nT:𝄞\nI:abc-include ü.abh"
        let found = IncludeDirectiveScanner.scan(text)
        #expect(found.count == 1)
        #expect(found.first?.lineNumber == 3)
        #expect(found.first?.utf16LineRange.location == 15)
        #expect(found.first?.fileName == "ü.abh")
    }

    // MARK: - URL resolution

    @Test func resolvesAgainstBaseDir() {
        let directive = IncludeDirective(
            lineNumber: 1, utf16LineRange: NSRange(location: 0, length: 10), fileName: "sub/x.abh")
        let url = IncludeDirectiveScanner.resolvedURL(
            for: directive, baseDir: URL(fileURLWithPath: "/tmp/scores"))
        #expect(url?.path == "/tmp/scores/sub/x.abh")
    }

    @Test func standardizesParentReferences() {
        let directive = IncludeDirective(
            lineNumber: 1, utf16LineRange: NSRange(location: 0, length: 10), fileName: "../shared/x.abh")
        let url = IncludeDirectiveScanner.resolvedURL(
            for: directive, baseDir: URL(fileURLWithPath: "/tmp/scores"))
        #expect(url?.path == "/tmp/shared/x.abh")
    }

    @Test func returnsNilWithoutBaseDir() {
        let directive = IncludeDirective(
            lineNumber: 1, utf16LineRange: NSRange(location: 0, length: 10), fileName: "x.abh")
        #expect(IncludeDirectiveScanner.resolvedURL(for: directive, baseDir: nil) == nil)
    }
}
