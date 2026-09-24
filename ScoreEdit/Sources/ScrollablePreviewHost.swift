import AppKit
import SwiftUI

/// Wraps an `NSScrollView` around a hosted `LazyVStack` of `SVGPageView`s so
/// callers can drive and observe the preview's scroll position at the pixel
/// level (needed for synchronized scrolling with the ABC editor — see #4, #5).
///
/// The document view is sized explicitly from a `PreviewLayout` rather than by
/// Auto Layout, so it can be wider than the viewport and scroll horizontally
/// (#39).
struct ScrollablePreviewHost: NSViewRepresentable {
    var pages: [String]
    /// Points per SVG unit, or `nil` to fit pages to the pane width.
    var scale: Double? = nil
    var scrollProportion: Double
    var onScrollProportionChanged: (Double) -> Void
    /// Reported in SVG user units, so it stays comparable to the scroll
    /// anchors' `svgY` at any scale.
    @Binding var contentHeight: Double
    /// Reported in SVG user units, like `contentHeight`.
    @Binding var visibleHeight: Double
    /// The scale fit width currently resolves to (#38).
    @Binding var fitScale: Double?

    func makeNSView(context: Context) -> NSScrollView {
        let naturalSizes = PreviewLayout.naturalPageSizes(of: pages)
        let hostingView = NSHostingView(rootView: PreviewPagesView(pages: pages, pageSizes: []))
        // The coordinator sets the document view's frame; don't let the hosted
        // content's ideal size add competing constraints.
        hostingView.sizingOptions = []

        let scrollView = NSScrollView()
        scrollView.documentView = hostingView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true

        let coordinator = context.coordinator
        coordinator.scrollView = scrollView
        coordinator.hostingView = hostingView
        coordinator.lastPages = pages
        coordinator.naturalSizes = naturalSizes
        coordinator.scale = scale
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.viewportFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        coordinator.relayout()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if coordinator.lastPages != pages {
            coordinator.lastPages = pages
            coordinator.naturalSizes = PreviewLayout.naturalPageSizes(of: pages)
            coordinator.scale = scale
            coordinator.relayout(pagesChanged: true)
            let proportion = scrollProportion
            DispatchQueue.main.async {
                coordinator.resync(to: proportion)
            }
        } else if coordinator.scale != scale {
            coordinator.scale = scale
            coordinator.relayout()
        } else if scrollProportion != coordinator.lastScrollProportion {
            coordinator.scroll(to: scrollProportion)
        }

        DispatchQueue.main.async {
            coordinator.syncMetrics()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScrollablePreviewHost
        weak var scrollView: NSScrollView?
        weak var hostingView: NSHostingView<PreviewPagesView>?
        private var isProgrammaticScroll = false
        fileprivate var lastScrollProportion: Double = 0
        fileprivate var lastPages: [String] = []
        fileprivate var naturalSizes: [CGSize] = []
        fileprivate var scale: Double?
        private var layout: PreviewLayout?

        init(_ parent: ScrollablePreviewHost) {
            self.parent = parent
        }

        @objc func boundsDidChange(_ notification: Notification) {
            guard !isProgrammaticScroll, let scrollView, let hostingView else { return }
            let proportion = Self.proportion(scrollView: scrollView, documentView: hostingView)
            lastScrollProportion = proportion
            syncMetrics()
            parent.onScrollProportionChanged(proportion)
        }

        @objc func viewportFrameDidChange(_ notification: Notification) {
            relayout()
        }

        /// Recomputes the page and document sizes for the current viewport
        /// width and scale, keeping the same point of the score centered in
        /// the viewport. May run during a SwiftUI update, so anything reported
        /// back to SwiftUI is deferred.
        func relayout(pagesChanged: Bool = false) {
            guard let scrollView, let hostingView else { return }
            let clip = scrollView.contentView
            let newLayout = PreviewLayout(
                naturalPageSizes: naturalSizes,
                scale: scale,
                viewportWidth: clip.bounds.width
            )
            guard pagesChanged || newLayout != layout else { return }
            let hadLayout = layout != nil && !pagesChanged
            layout = newLayout

            let center = Self.viewportCenter(scrollView: scrollView, documentView: hostingView)
            let previousProportion = lastScrollProportion

            isProgrammaticScroll = true
            hostingView.rootView = PreviewPagesView(pages: lastPages, pageSizes: newLayout.pageSizes)
            hostingView.setFrameSize(newLayout.documentSize)
            if hadLayout {
                scrollViewport(toCenter: center)
            }
            isProgrammaticScroll = false

            let proportion = Self.proportion(scrollView: scrollView, documentView: hostingView)
            lastScrollProportion = proportion
            DispatchQueue.main.async {
                self.syncMetrics()
                if hadLayout && proportion != previousProportion {
                    self.parent.onScrollProportionChanged(proportion)
                }
            }
        }

        func scroll(to proportion: Double) {
            guard let scrollView, let hostingView else { return }
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

        /// Scrolls so the point at the given fractions of the document's width
        /// and height is centered in the viewport (clamped to the scrollable
        /// range).
        private func scrollViewport(toCenter center: CGPoint) {
            guard let scrollView, let hostingView else { return }
            let clip = scrollView.contentView
            let document = hostingView.bounds.size
            let viewport = clip.bounds.size
            let origin = CGPoint(
                x: min(max(center.x * document.width - viewport.width / 2, 0), max(document.width - viewport.width, 0)),
                y: min(max(center.y * document.height - viewport.height / 2, 0), max(document.height - viewport.height, 0))
            )
            guard origin != clip.bounds.origin else { return }
            clip.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clip)
        }

        func resync(to proportion: Double) {
            scroll(to: proportion)
            syncMetrics()
        }

        func syncMetrics() {
            guard let scrollView, let hostingView else { return }
            let naturalHeight = naturalSizes.reduce(0) { $0 + $1.height }
            let documentHeight = hostingView.bounds.height
            let unitsPerPoint = documentHeight > 0 ? naturalHeight / documentHeight : 0
            let contentHeight = naturalHeight
            let visibleHeight = scrollView.contentView.bounds.height * unitsPerPoint
            if parent.contentHeight != contentHeight {
                parent.contentHeight = contentHeight
            }
            if parent.visibleHeight != visibleHeight {
                parent.visibleHeight = visibleHeight
            }
            let fitScale = PreviewLayout.fitScale(
                naturalPageSizes: naturalSizes,
                viewportWidth: scrollView.contentView.bounds.width
            )
            if parent.fitScale != fitScale {
                parent.fitScale = fitScale
            }
        }

        private static func proportion(scrollView: NSScrollView, documentView: NSView) -> Double {
            let maxScroll = documentView.bounds.height - scrollView.contentView.bounds.height
            guard maxScroll > 0 else { return 0 }
            return min(max(scrollView.contentView.bounds.origin.y / maxScroll, 0), 1)
        }

        /// The viewport's center as fractions of the document's width and height.
        private static func viewportCenter(scrollView: NSScrollView, documentView: NSView) -> CGPoint {
            let document = documentView.bounds.size
            let clip = scrollView.contentView.bounds
            return CGPoint(
                x: document.width > 0 ? clip.midX / document.width : 0.5,
                y: document.height > 0 ? clip.midY / document.height : 0
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

struct PreviewPagesView: View {
    let pages: [String]
    let pageSizes: [CGSize]

    var body: some View {
        LazyVStack(spacing: PreviewLayout.spacing) {
            ForEach(pages.indices, id: \.self) { i in
                let size = i < pageSizes.count ? pageSizes[i] : .zero
                SVGPageView(svgString: pages[i], size: size)
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
            }
        }
        .padding(PreviewLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
