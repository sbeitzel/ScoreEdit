import AppKit

/// `NSTextView` with cmd-click support on `I:abc-include` lines: clicking one
/// with the command key held opens the included file for editing (#15).
/// Everything else defers to `NSTextView`.
final class ABCTextView: NSTextView {
    var includeDirectives: [IncludeDirective] = []
    var onOpenInclude: ((IncludeDirective) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let directive = directive(at: event) {
            onOpenInclude?(directive)
            return
        }
        super.mouseDown(with: event)
    }

    func directive(atCharacterIndex index: Int) -> IncludeDirective? {
        includeDirectives.first { NSLocationInRange(index, $0.utf16LineRange) }
    }

    private func directive(at event: NSEvent) -> IncludeDirective? {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        return directive(atCharacterIndex: index)
    }
}
