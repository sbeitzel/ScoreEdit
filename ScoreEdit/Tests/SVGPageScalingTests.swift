import CeolKitParser
import CeolKitSVGRenderer
import QuartzCore
import SVGKit
import Testing
@testable import ScoreEdit

/// Preview zoom (#38) rests on SVGKit scaling a page's drawing when the image's
/// `size` is set: `SVGKLayeredImageView` draws at the image's size, not its
/// frame's. That only works because CeolKit's pages carry a `viewBox`.
struct SVGPageScalingTests {

    @Test func settingImageSizeScalesDrawnGeometry() throws {
        let svg = try Self.renderPreviewPage()
        let natural = try #require(SVGPageView.svgSize(svg))

        let actual = try Self.drawnExtent(svg: svg, size: CGSize(width: natural.width, height: natural.height))
        let doubled = try Self.drawnExtent(svg: svg, size: CGSize(width: natural.width * 2, height: natural.height * 2))

        #expect(actual.width > 0)
        #expect(abs(doubled.width / actual.width - 2) < 0.01)
        #expect(abs(doubled.height / actual.height - 2) < 0.01)
    }

    /// Without an explicit size SVGKit converts CeolKit's `pt` dimensions to a
    /// larger pixel size, so the page would overflow its frame; with one, the
    /// `viewBox` maps exactly onto it.
    @Test func sizedPageDrawsWithinItsSize() throws {
        let svg = try Self.renderPreviewPage()
        let natural = try #require(SVGPageView.svgSize(svg))
        let size = CGSize(width: natural.width, height: natural.height)

        let extent = try Self.drawnExtent(svg: svg, size: size)

        #expect(extent.maxX <= size.width)
        #expect(extent.maxY <= size.height)
    }

    /// Zooming resizes the image an existing view already shows. The view must
    /// end up with exactly one layer tree, drawn at the new size — not the
    /// original tree (SVGKLayer ignores a same-image assignment) and not both.
    @MainActor
    @Test func resizingViewReplacesItsLayerTree() throws {
        let svg = try Self.renderPreviewPage()
        let natural = try #require(SVGPageView.svgSize(svg))
        let image = try #require(SVGKImage(source: SVGKSourceString.source(fromContentsOf: svg)))
        image.size = CGSize(width: natural.width / 2, height: natural.height / 2)
        let view = try #require(SVGKLayeredImageView(svgkImage: image))
        let before = try Self.onScreenExtent(of: view)

        let doubled = CGSize(width: natural.width * 2, height: natural.height * 2)
        SVGPageView.resize(view, to: doubled)

        let trees = try #require(view.layer?.sublayers)
        #expect(trees.count == 1)
        #expect(trees.first?.bounds.size == doubled)
        let after = try Self.onScreenExtent(of: view)
        #expect(abs(after.width / before.width - 4) < 0.01)
    }

    /// Drawn extent of the layer trees a view is actually displaying.
    @MainActor
    private static func onScreenExtent(of view: SVGKLayeredImageView) throws -> CGRect {
        let layer = try #require(view.layer)
        return shapeFrames(in: layer, root: layer).reduce(CGRect.null) { $0.union($1) }
    }

    /// Bounding box of every drawn shape in the image's layer tree.
    private static func drawnExtent(svg: String, size: CGSize?) throws -> CGRect {
        let image = try #require(SVGKImage(source: SVGKSourceString.source(fromContentsOf: svg)))
        if let size { image.size = size }
        let root = try #require(image.caLayerTree)
        return shapeFrames(in: root, root: root).reduce(CGRect.null) { $0.union($1) }
    }

    private static func shapeFrames(in layer: CALayer, root: CALayer) -> [CGRect] {
        var found: [CGRect] = []
        if let shape = layer as? CAShapeLayer, let path = shape.path {
            found.append(layer.convert(path.boundingBoxOfPath, to: root))
        }
        for sub in layer.sublayers ?? [] { found += shapeFrames(in: sub, root: root) }
        return found
    }

    private static func renderPreviewPage() throws -> String {
        let abc = """
            X:1
            T:Scale Check
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
