import AppKit
import CeolKitModel

/// Line-number ruler for the ABC editor with IDE-style diagnostic markers.
///
/// Three columns, left to right: a severity dot for lines carrying parse
/// diagnostics (hover shows the messages), a clickable chevron on
/// `I:abc-include` lines (opens the included file — see #15), and the
/// right-aligned line number. An include line whose fragment produced a
/// diagnostic shows both markers side by side (#16).
final class DiagnosticRulerView: NSRulerView {

    var diagnosticsByLine: [Int: [EditorDiagnostic]] = [:] {
        didSet {
            if diagnosticsByLine != oldValue { needsDisplay = true }
        }
    }

    var includeDirectivesByLine: [Int: IncludeDirective] = [:] {
        didSet {
            if includeDirectivesByLine != oldValue {
                needsDisplay = true
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    var onIncludeClick: ((IncludeDirective) -> Void)?

    // MARK: - Layout constants

    private static let dotColumnX: CGFloat = 4
    private static let dotDiameter: CGFloat = 7
    private static let chevronColumnX: CGFloat = 14
    private static let chevronWidth: CGFloat = 13
    private static let numbersLeftX: CGFloat = chevronColumnX + chevronWidth + 3
    private static let rightPadding: CGFloat = 5

    // MARK: - Line index cache

    private var lineStarts: [Int] = [0]
    private var lineStartsValid = false
    private var toolTipLines: [NSView.ToolTipTag: Int] = [:]

    private var textView: NSTextView? { clientView as? NSTextView }

    /// Call whenever the client text changes (typing or wholesale replacement).
    func invalidateLineIndex() {
        lineStartsValid = false
        needsDisplay = true
    }

    private func ensureLineStarts() {
        guard !lineStartsValid, let textView else { return }
        lineStarts = LineIndex.lineStartOffsets(textView.string)
        lineStartsValid = true
        updateRuleThickness()
    }

    private func updateRuleThickness() {
        let digits = max(2, String(lineStarts.count).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: numberFont]).width
        let needed = ceil(Self.numbersLeftX + CGFloat(digits) * digitWidth + Self.rightPadding)
        if abs(ruleThickness - needed) > 0.5 {
            ruleThickness = needed
        }
    }

    private var numberFont: NSFont {
        let baseSize = textView?.font?.pointSize ?? NSFont.systemFontSize
        return NSFont.monospacedDigitSystemFont(ofSize: round(baseSize * 0.85), weight: .regular)
    }

    // MARK: - Drawing

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let rows = visibleLineRows()
        let font = numberFont
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let numbersRight = bounds.maxX - Self.rightPadding

        for row in rows {
            let number = "\(row.line)" as NSString
            let size = number.size(withAttributes: numberAttributes)
            number.draw(
                at: NSPoint(x: numbersRight - size.width, y: row.rect.midY - size.height / 2),
                withAttributes: numberAttributes
            )
            if let lineDiagnostics = diagnosticsByLine[row.line], !lineDiagnostics.isEmpty {
                drawSeverityDot(
                    severity: DiagnosticMapper.worst(lineDiagnostics.map(\.severity)),
                    in: row.rect
                )
            }
            if includeDirectivesByLine[row.line] != nil {
                drawIncludeChevron(in: chevronRect(forRow: row.rect))
            }
        }
        rebuildToolTips(rows: rows)
    }

    private func drawSeverityDot(severity: CeolKitModel.Diagnostic.Severity, in rowRect: NSRect) {
        let color: NSColor = switch severity {
        case .error: .systemRed
        case .warning: .systemOrange
        case .info: .systemBlue
        }
        color.setFill()
        NSBezierPath(ovalIn: dotRect(forRow: rowRect)).fill()
    }

    private func drawIncludeChevron(in rect: NSRect) {
        guard let image = NSImage(
            systemSymbolName: "arrow.up.forward.square",
            accessibilityDescription: String(localized: .kbuttonOpenIncludeAxDescription)
        ) else { return }
        let configured = image.withSymbolConfiguration(
            .init(pointSize: rect.width, weight: .regular)
                .applying(.init(paletteColors: [.controlAccentColor]))
        ) ?? image
        configured.draw(in: rect)
    }

    private func dotRect(forRow rowRect: NSRect) -> NSRect {
        NSRect(
            x: Self.dotColumnX,
            y: rowRect.midY - Self.dotDiameter / 2,
            width: Self.dotDiameter,
            height: Self.dotDiameter
        )
    }

    private func chevronRect(forRow rowRect: NSRect) -> NSRect {
        NSRect(
            x: Self.chevronColumnX,
            y: rowRect.midY - Self.chevronWidth / 2,
            width: Self.chevronWidth,
            height: Self.chevronWidth
        )
    }

    // MARK: - Geometry

    /// Rects (in ruler coordinates, full gutter width) of every source line
    /// whose first fragment is currently visible, plus the trailing empty line
    /// when the text ends in a newline.
    private func visibleLineRows() -> [(line: Int, rect: NSRect)] {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return [] }
        ensureLineStarts()

        var rows: [(line: Int, rect: NSRect)] = []
        let glyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, fragmentGlyphRange, _ in
            let charIndex = layoutManager.characterIndexForGlyph(at: fragmentGlyphRange.location)
            let line = LineIndex.lineNumber(forUTF16Offset: charIndex, in: self.lineStarts)
            // Soft-wrapped continuations start mid-line; only the first
            // fragment of each source line gets a gutter row.
            guard charIndex == self.lineStarts[line - 1] else { return }
            rows.append((line, self.rulerRow(forTextRect: fragmentRect, in: textView)))
        }
        if layoutManager.extraLineFragmentTextContainer != nil {
            rows.append((
                lineStarts.count,
                rulerRow(forTextRect: layoutManager.extraLineFragmentRect, in: textView)
            ))
        }
        return rows
    }

    private func rulerRow(forTextRect textRect: NSRect, in textView: NSTextView) -> NSRect {
        var rect = textRect
        rect.origin.y += textView.textContainerOrigin.y
        let converted = convert(rect, from: textView)
        return NSRect(x: 0, y: converted.minY, width: ruleThickness, height: rect.height)
    }

    // MARK: - Tooltips

    private func rebuildToolTips(rows: [(line: Int, rect: NSRect)]) {
        removeAllToolTips()
        toolTipLines.removeAll()
        for row in rows where !(diagnosticsByLine[row.line] ?? []).isEmpty {
            let tag = addToolTip(row.rect, owner: self, userData: nil)
            toolTipLines[tag] = row.line
        }
    }

    @objc func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData: UnsafeMutableRawPointer?
    ) -> String {
        guard let line = toolTipLines[tag], let lineDiagnostics = diagnosticsByLine[line] else {
            return ""
        }
        return lineDiagnostics.map { diagnostic in
            var text = ""
            if let fileName = diagnostic.includedFileName, let fileLine = diagnostic.includedFileLine {
                text += "\(fileName):\(fileLine) — "
            }
            text += "\(severityLabel(diagnostic.severity)): \(diagnostic.message) (\(diagnostic.code))"
            if let hint = diagnostic.hint {
                text += "\n    \(hint)"
            }
            return text
        }.joined(separator: "\n")
    }

    private func severityLabel(_ severity: CeolKitModel.Diagnostic.Severity) -> String {
        switch severity {
        case .error: String(localized: .kseverityError)
        case .warning: String(localized: .kseverityWarning)
        case .info: String(localized: .kseverityInfo)
        }
    }

    // MARK: - Include-chevron interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for row in visibleLineRows() {
            guard let directive = includeDirectivesByLine[row.line] else { continue }
            if chevronRect(forRow: row.rect).insetBy(dx: -2, dy: -2).contains(point) {
                onIncludeClick?(directive)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for row in visibleLineRows() where includeDirectivesByLine[row.line] != nil {
            addCursorRect(chevronRect(forRow: row.rect), cursor: .pointingHand)
        }
    }
}
