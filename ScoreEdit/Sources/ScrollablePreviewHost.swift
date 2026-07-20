import AppKit
import SwiftUI

/// Wraps an `NSScrollView` around a hosted `LazyVStack` of `SVGPageView`s so
/// callers can drive and observe the preview's scroll position at the pixel
/// level (needed for synchronized scrolling with the ABC editor — see #4, #5).
struct ScrollablePreviewHost: NSViewRepresentable {
    var pages: [String]
    var scrollProportion: Double
    var onScrollProportionChanged: (Double) -> Void
    @Binding var contentHeight: Double
    @Binding var visibleHeight: Double

    func makeNSView(context: Context) -> NSScrollView {
        let hostingView = NSHostingView(rootView: PreviewPagesView(pages: pages))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.documentView = hostingView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        // The document view self-sizes vertically from its SwiftUI content
        // (intrinsic height for the pinned width), so only pin the edges that
        // fix its position and width — leave height unconstrained.
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            hostingView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        context.coordinator.scrollView = scrollView
        context.coordinator.hostingView = hostingView
        context.coordinator.lastPages = pages
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let hostingView = scrollView.documentView as? NSHostingView<PreviewPagesView> else { return }

        if context.coordinator.lastPages != pages {
            hostingView.rootView = PreviewPagesView(pages: pages)
            context.coordinator.lastPages = pages
            let proportion = scrollProportion
            DispatchQueue.main.async {
                scrollView.layoutSubtreeIfNeeded()
                context.coordinator.resync(to: proportion, scrollView: scrollView, hostingView: hostingView)
            }
        } else if scrollProportion != context.coordinator.lastScrollProportion {
            context.coordinator.scroll(to: scrollProportion, scrollView: scrollView, hostingView: hostingView)
        }

        DispatchQueue.main.async {
            context.coordinator.syncMetrics(scrollView: scrollView, hostingView: hostingView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScrollablePreviewHost
        weak var scrollView: NSScrollView?
        weak var hostingView: NSView?
        private var isProgrammaticScroll = false
        fileprivate var lastScrollProportion: Double = 0
        fileprivate var lastPages: [String] = []

        init(_ parent: ScrollablePreviewHost) {
            self.parent = parent
        }

        @objc func boundsDidChange(_ notification: Notification) {
            guard !isProgrammaticScroll, let scrollView, let hostingView else { return }
            let proportion = Self.proportion(scrollView: scrollView, documentView: hostingView)
            lastScrollProportion = proportion
            syncMetrics(scrollView: scrollView, hostingView: hostingView)
            parent.onScrollProportionChanged(proportion)
        }

        func scroll(to proportion: Double, scrollView: NSScrollView, hostingView: NSView) {
            let clamped = min(max(proportion, 0), 1)
            let maxScroll = max(hostingView.bounds.height - scrollView.contentView.bounds.height, 0)
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

        func resync(to proportion: Double, scrollView: NSScrollView, hostingView: NSView) {
            scroll(to: proportion, scrollView: scrollView, hostingView: hostingView)
            syncMetrics(scrollView: scrollView, hostingView: hostingView)
        }

        func syncMetrics(scrollView: NSScrollView, hostingView: NSView) {
            let contentHeight = hostingView.bounds.height
            let visibleHeight = scrollView.contentView.bounds.height
            if parent.contentHeight != contentHeight {
                parent.contentHeight = contentHeight
            }
            if parent.visibleHeight != visibleHeight {
                parent.visibleHeight = visibleHeight
            }
        }

        private static func proportion(scrollView: NSScrollView, documentView: NSView) -> Double {
            let maxScroll = documentView.bounds.height - scrollView.contentView.bounds.height
            guard maxScroll > 0 else { return 0 }
            return min(max(scrollView.contentView.bounds.origin.y / maxScroll, 0), 1)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private struct PreviewPagesView: View {
    let pages: [String]

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(pages.indices, id: \.self) { i in
                SVGPageView(svgString: pages[i])
                    .aspectRatio(SVGPageView.aspectRatio(pages[i]) ?? (612.0 / 792.0), contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
            }
        }
        .padding()
    }
}
