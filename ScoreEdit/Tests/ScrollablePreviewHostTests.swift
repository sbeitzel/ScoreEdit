import AppKit
import CeolKitParser
import CeolKitSVGRenderer
import SVGKit
import SwiftUI
import Testing
@testable import ScoreEdit

/// Drives a real `ScrollablePreviewHost` in a window through zoom changes and
/// checks where the pages actually land in the document (#38). A page that
/// keeps an earlier zoom's frame is centered in the resized document — offset
/// up and left, so scrolling to the top-left corner no longer reaches it.
@MainActor
struct ScrollablePreviewHostTests {

    @Test(arguments: [
        [4.0, 3.0],
        [0.5, 4.0],
        [2.0, 1.0, 0.75, 3.0],
    ])
    func pagesFollowEachZoomChange(scales: [Double]) throws {
        let pages = [try Self.renderPage(), try Self.renderPage()]
        let natural = PreviewLayout.naturalPageSizes(of: pages)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // A code-created window is released when closed by default, on top of
        // ARC's release — an over-release that crashes the test process.
        window.isReleasedWhenClosed = false
        let outer = NSHostingView(rootView: Self.host(pages: pages, scale: scales[0]))
        window.contentView = outer
        defer { window.close() }
        Self.settle(outer)
        let scrollView = try #require(Self.first(NSScrollView.self, in: outer))

        for scale in scales {
            outer.rootView = Self.host(pages: pages, scale: scale)
            Self.settle(outer)
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            Self.settle(outer)

            let document = try #require(scrollView.documentView)
            let expected = PreviewLayout(
                naturalPageSizes: natural,
                scale: scale,
                viewportWidth: scrollView.contentView.bounds.width
            )
            #expect(document.frame.size == expected.documentSize)

            let pageViews = Self.all(SVGKLayeredImageView.self, in: document)
                .map { $0.convert($0.bounds, to: document) }
                .sorted { $0.minY < $1.minY }
            #expect(pageViews.count == pages.count)
            var y = PreviewLayout.padding
            for (frame, size) in zip(pageViews, expected.pageSizes) {
                #expect(frame.size == size, "scale \(scale)")
                #expect(frame.minX >= PreviewLayout.padding, "scale \(scale)")
                #expect(abs(frame.minY - y) < 0.5, "scale \(scale)")
                y += size.height + PreviewLayout.spacing
            }
        }
    }

    private static func host(pages: [String], scale: Double) -> ScrollablePreviewHost {
        ScrollablePreviewHost(
            pages: pages,
            scale: scale,
            scrollProportion: 0,
            onScrollProportionChanged: { _ in },
            contentHeight: .constant(0),
            visibleHeight: .constant(0),
            fitScale: .constant(nil)
        )
    }

    /// Lets deferred updates (the host defers work to the main queue) and
    /// layout run.
    private static func settle(_ view: NSView) {
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            view.layoutSubtreeIfNeeded()
        }
    }

    private static func first<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        all(type, in: view).first
    }

    private static func all<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        if let match = view as? T { return [match] }
        return view.subviews.flatMap { all(type, in: $0) }
    }

    private static func renderPage() throws -> String {
        let abc = """
            X:1
            T:Zoom Check
            M:4/4
            L:1/4
            K:C
            CDEF|GABc|
            """
        let result = CeolKitParser().parse(abc, options: .default)
        let renderer = SVGRenderer(config: SVGRenderConfig(pageSize: .letter))
        return try #require(try renderer.render(result.score).first)
    }
}
