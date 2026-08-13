import CeolKitModel
import Foundation
import Testing
@testable import ScoreEdit

struct DiagnosticMapperTests {

    private let baseDir = URL(fileURLWithPath: "/base")

    private func directive(line: Int, fileName: String) -> IncludeDirective {
        IncludeDirective(
            lineNumber: line,
            utf16LineRange: NSRange(location: 0, length: 1),
            fileName: fileName
        )
    }

    private func diagnostic(
        severity: Diagnostic.Severity = .warning,
        code: DiagnosticCode = .unknownField,
        message: String = "test message",
        file: URL? = nil,
        line: Int,
        hint: String? = nil
    ) -> Diagnostic {
        Diagnostic(
            severity: severity,
            code: code,
            message: message,
            source: SourceRange(file: file, byteOffset: 0, length: 1, line: line, column: 1),
            hint: hint
        )
    }

    // MARK: - Top-level diagnostics

    @Test func topLevelDiagnosticKeepsItsLine() {
        let mapped = DiagnosticMapper.editorDiagnostics(
            from: [diagnostic(severity: .error, line: 7)],
            directives: [],
            baseDir: baseDir
        )
        #expect(mapped.count == 1)
        #expect(mapped.first?.editorLine == 7)
        #expect(mapped.first?.severity == .error)
        #expect(mapped.first?.includedFileName == nil)
        #expect(mapped.first?.includedFileLine == nil)
    }

    @Test func carriesMessageHintAndCode() {
        let mapped = DiagnosticMapper.editorDiagnostics(
            from: [diagnostic(code: .danglingTie, message: "tie to nowhere", line: 3, hint: "remove it")],
            directives: [],
            baseDir: baseDir
        )
        #expect(mapped.first?.message == "tie to nowhere")
        #expect(mapped.first?.hint == "remove it")
        #expect(mapped.first?.code == "danglingTie")
    }

    // MARK: - Included-file diagnostics

    @Test func includedFileDiagnosticLandsOnDirectiveLine() {
        let mapped = DiagnosticMapper.editorDiagnostics(
            from: [diagnostic(file: URL(fileURLWithPath: "/base/sub.abh"), line: 12)],
            directives: [directive(line: 3, fileName: "sub.abh")],
            baseDir: baseDir
        )
        #expect(mapped.first?.editorLine == 3)
        #expect(mapped.first?.includedFileName == "sub.abh")
        #expect(mapped.first?.includedFileLine == 12)
    }

    @Test func comparesStandardizedPaths() {
        let mapped = DiagnosticMapper.editorDiagnostics(
            from: [diagnostic(file: URL(fileURLWithPath: "/base/other/../sub.abh"), line: 2)],
            directives: [directive(line: 5, fileName: "sub.abh")],
            baseDir: baseDir
        )
        #expect(mapped.first?.editorLine == 5)
    }

    @Test func matchesDirectiveWithRelativePath() {
        let mapped = DiagnosticMapper.editorDiagnostics(
            from: [diagnostic(file: URL(fileURLWithPath: "/shared/x.abh"), line: 1)],
            directives: [directive(line: 2, fileName: "../shared/x.abh")],
            baseDir: baseDir
        )
        #expect(mapped.first?.editorLine == 2)
    }

    @Test func unknownFileFallsBackToFirstDirective() {
        // A nested include's file matches no top-level directive.
        let mapped = DiagnosticMapper.editorDiagnostics(
            from: [diagnostic(file: URL(fileURLWithPath: "/base/nested.abh"), line: 1)],
            directives: [directive(line: 4, fileName: "sub.abh"), directive(line: 9, fileName: "other.abh")],
            baseDir: baseDir
        )
        #expect(mapped.first?.editorLine == 4)
    }

    @Test func unknownFileWithNoDirectivesFallsBackToLineOne() {
        let mapped = DiagnosticMapper.editorDiagnostics(
            from: [diagnostic(file: URL(fileURLWithPath: "/base/x.abh"), line: 8)],
            directives: [],
            baseDir: baseDir
        )
        #expect(mapped.first?.editorLine == 1)
    }

    @Test func duplicateIncludeUsesFirstDirectiveLine() {
        let mapped = DiagnosticMapper.editorDiagnostics(
            from: [diagnostic(file: URL(fileURLWithPath: "/base/sub.abh"), line: 1)],
            directives: [directive(line: 2, fileName: "sub.abh"), directive(line: 6, fileName: "sub.abh")],
            baseDir: baseDir
        )
        #expect(mapped.first?.editorLine == 2)
    }

    // MARK: - Severity ordering

    @Test func worstPicksErrorOverWarningOverInfo() {
        #expect(DiagnosticMapper.worst([.info, .error, .warning]) == .error)
        #expect(DiagnosticMapper.worst([.info, .warning]) == .warning)
        #expect(DiagnosticMapper.worst([.info]) == .info)
        #expect(DiagnosticMapper.worst([]) == .info)
    }
}
