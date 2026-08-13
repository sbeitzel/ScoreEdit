import CeolKitModel
import Foundation

/// App-side, `Equatable` projection of a CeolKit `Diagnostic`, re-anchored to
/// a line of the top-level document so the editor gutter can display it.
///
/// Diagnostics that originate inside an included file (`SourceRange.file` is
/// non-nil) are attributed to the `I:abc-include` line that pulled the file
/// in; `includedFileName`/`includedFileLine` preserve the real location for
/// the tooltip (see #16).
struct EditorDiagnostic: Equatable, Sendable, Identifiable {
    let id: String
    /// 1-based line in the top-level document.
    let editorLine: Int
    let severity: Diagnostic.Severity
    let message: String
    let hint: String?
    let code: String
    /// Non-nil when the diagnostic was re-attributed from an included file.
    let includedFileName: String?
    /// The diagnostic's line within that included file.
    let includedFileLine: Int?
}

enum DiagnosticMapper {
    /// Maps parser diagnostics onto editor lines. Diagnostics from an included
    /// file land on the directive line whose resolved URL matches; a
    /// diagnostic from a file no directive resolves to (a nested include)
    /// falls back to the first directive, or line 1.
    static func editorDiagnostics(
        from diagnostics: [Diagnostic],
        directives: [IncludeDirective],
        baseDir: URL?
    ) -> [EditorDiagnostic] {
        var directiveLineForPath: [String: Int] = [:]
        for directive in directives {
            guard let url = IncludeDirectiveScanner.resolvedURL(for: directive, baseDir: baseDir) else {
                continue
            }
            if directiveLineForPath[url.path] == nil {
                directiveLineForPath[url.path] = directive.lineNumber
            }
        }
        let fallbackLine = directives.first?.lineNumber ?? 1

        return diagnostics.map { diagnostic in
            let editorLine: Int
            let includedFileName: String?
            let includedFileLine: Int?
            if let file = diagnostic.source.file {
                editorLine = directiveLineForPath[file.standardized.path] ?? fallbackLine
                includedFileName = file.lastPathComponent
                includedFileLine = diagnostic.source.line
            } else {
                editorLine = diagnostic.source.line
                includedFileName = nil
                includedFileLine = nil
            }
            return EditorDiagnostic(
                id: "\(diagnostic.source.id):\(diagnostic.code.rawValue)",
                editorLine: editorLine,
                severity: diagnostic.severity,
                message: diagnostic.message,
                hint: diagnostic.hint,
                code: diagnostic.code.rawValue,
                includedFileName: includedFileName,
                includedFileLine: includedFileLine
            )
        }
    }

    /// The most severe of the given severities (error > warning > info), for
    /// picking a marker color when one line carries several diagnostics.
    static func worst(_ severities: [Diagnostic.Severity]) -> Diagnostic.Severity {
        severities.max { rank($0) < rank($1) } ?? .info
    }

    private static func rank(_ severity: Diagnostic.Severity) -> Int {
        switch severity {
        case .info: 0
        case .warning: 1
        case .error: 2
        }
    }
}

/// Line geometry shared by the gutter: maps UTF-16 offsets to 1-based lines.
enum LineIndex {
    /// UTF-16 offset of the start of each line; index 0 is line 1. Always
    /// non-empty (empty text has a single line starting at 0).
    static func lineStartOffsets(_ text: String) -> [Int] {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A {
                starts.append(offset)
            }
        }
        return starts
    }

    /// The 1-based line containing the given UTF-16 offset. Offsets past the
    /// end map to the last line.
    static func lineNumber(forUTF16Offset offset: Int, in starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }
}
