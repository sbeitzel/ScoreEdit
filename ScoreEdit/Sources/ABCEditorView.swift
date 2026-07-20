import AppKit
import SwiftUI

/// Wraps `NSTextView` in an `NSScrollView` so callers can drive and observe
/// scroll position at the pixel level (needed for synchronized scrolling with
/// the score preview — see #3, #4, #5).
struct ABCEditorView: NSViewRepresentable {
    @Binding var text: String
    var scrollProportion: Double
    var onScrollProportionChanged: (Double) -> Void
    @Binding var contentHeight: Double
    @Binding var visibleHeight: Double

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = Self.monospacedFont
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if scrollProportion != context.coordinator.lastScrollProportion {
            context.coordinator.scroll(to: scrollProportion, scrollView: scrollView, textView: textView)
        }
        DispatchQueue.main.async {
            context.coordinator.syncMetrics(scrollView: scrollView, textView: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private static let monospacedFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ABCEditorView
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        private var isProgrammaticScroll = false
        fileprivate var lastScrollProportion: Double = 0

        init(_ parent: ABCEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        @objc func boundsDidChange(_ notification: Notification) {
            guard !isProgrammaticScroll, let scrollView, let textView else { return }
            let proportion = Self.proportion(scrollView: scrollView, textView: textView)
            lastScrollProportion = proportion
            syncMetrics(scrollView: scrollView, textView: textView)
            parent.onScrollProportionChanged(proportion)
        }

        func scroll(to proportion: Double, scrollView: NSScrollView, textView: NSTextView) {
            let clamped = min(max(proportion, 0), 1)
            let maxScroll = max(textView.bounds.height - scrollView.contentView.bounds.height, 0)
            guard maxScroll > 0 else {
                lastScrollProportion = clamped
                return
            }
            isProgrammaticScroll = true
            var origin = scrollView.contentView.bounds.origin
            origin.y = clamped * maxScroll
            scrollView.contentView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isProgrammaticScroll = false
            lastScrollProportion = clamped
        }

        func syncMetrics(scrollView: NSScrollView, textView: NSTextView) {
            let contentHeight = textView.bounds.height
            let visibleHeight = scrollView.contentView.bounds.height
            if parent.contentHeight != contentHeight {
                parent.contentHeight = contentHeight
            }
            if parent.visibleHeight != visibleHeight {
                parent.visibleHeight = visibleHeight
            }
        }

        private static func proportion(scrollView: NSScrollView, textView: NSTextView) -> Double {
            let maxScroll = textView.bounds.height - scrollView.contentView.bounds.height
            guard maxScroll > 0 else { return 0 }
            return min(max(scrollView.contentView.bounds.origin.y / maxScroll, 0), 1)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
