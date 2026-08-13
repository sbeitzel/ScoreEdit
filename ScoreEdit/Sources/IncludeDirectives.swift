import Foundation

/// One `I:abc-include` line found in document text.
///
/// Produced by `IncludeDirectiveScanner`, which mirrors CeolKit's
/// `LineClassifier` + `IncludeExpander` semantics exactly so the app and the
/// parser always agree on which lines are includes (see #15).
struct IncludeDirective: Equatable, Sendable {
    /// 1-based line number in the editor text.
    let lineNumber: Int
    /// UTF-16 range of the line's visible content (excluding the line
    /// terminator), for hit-testing against `NSTextView` character indexes.
    let utf16LineRange: NSRange
    /// The include payload, trimmed. Never empty.
    let fileName: String
}

enum IncludeDirectiveScanner {
    /// Scans raw editor text line by line for `I:abc-include` directives.
    ///
    /// Matching rules (identical to CeolKit): the line starts at column 0 with
    /// uppercase `I` followed by `:`; the payload, whitespace-trimmed, matches
    /// `abc-include` as a case-insensitive prefix; the remainder after that
    /// prefix, whitespace-trimmed, is the (non-empty) filename.
    static func scan(_ text: String) -> [IncludeDirective] {
        var results: [IncludeDirective] = []
        var lineNumber = 1
        var lineStartUTF16 = 0
        // Split on scalars, not Characters: "\r\n" is a single Character, so a
        // Character-level split on "\n" would leave CRLF lines unsplit.
        for scalarLine in text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(scalarLine)
            let utf16Length = line.utf16.count
            // CeolKit normalizes CRLF to LF before classifying; stripping the
            // trailing CR here keeps line matching and ranges consistent.
            if line.hasSuffix("\r") {
                line.removeLast()
            }
            if let fileName = includeFileName(inLine: line[...]) {
                results.append(IncludeDirective(
                    lineNumber: lineNumber,
                    utf16LineRange: NSRange(location: lineStartUTF16, length: line.utf16.count),
                    fileName: fileName
                ))
            }
            lineNumber += 1
            lineStartUTF16 += utf16Length + 1  // +1 for the "\n"
        }
        return results
    }

    /// `baseDir.appendingPathComponent(fileName).standardized`, matching
    /// CeolKit's `IncludeExpander`. Nil when there is no base directory
    /// (unsaved document).
    static func resolvedURL(for directive: IncludeDirective, baseDir: URL?) -> URL? {
        guard let baseDir else { return nil }
        return baseDir.appendingPathComponent(directive.fileName).standardized
    }

    private static func includeFileName(inLine line: Substring) -> String? {
        guard line.first == "I" else { return nil }
        let colonIndex = line.index(after: line.startIndex)
        guard colonIndex < line.endIndex, line[colonIndex] == ":" else { return nil }
        let payload = line[line.index(after: colonIndex)...]
        let trimmed = payload.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("abc-include") else { return nil }
        let fileName = String(trimmed.dropFirst("abc-include".count))
            .trimmingCharacters(in: .whitespaces)
        return fileName.isEmpty ? nil : fileName
    }
}
