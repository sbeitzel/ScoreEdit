import CeolKitModel
import CeolKitParser
import CeolKitSVGRenderer
import QuartzCore
import SVGKit
import Testing
@testable import ScoreEdit

/// The preview renders with CeolKit's default `TextRendering/outlines`, so it needs no
/// fonts registered with the process (#33). These tests guard that independence.
struct PreviewFontIndependenceTests {

    /// The ABC these tests render: a title and a footer (text) over a
    /// bar of notes (music glyphs), so both font families are exercised.
    private static let abc = """
        %%titleformat T0
        %%footer "Footer Check"
        X:1
        T:Font Check
        M:4/4
        L:1/4
        K:C
        CDEF|
        """

    /// As of CeolKit 1.2.1 `SVGRenderConfig.textRendering` defaults to `.outlines`,
    /// which writes glyph geometry into the document instead of emitting `<text>`
    /// that a rasterizer has to match against an installed family. The preview uses
    /// that default, so its output must not depend on the host's font environment —
    /// a `<text>` element reappearing here means it silently does again.
    @Test func previewOutputCarriesNoFontDependency() throws {
        let svg = try Self.renderPreviewPage()
        #expect(!svg.contains("<text"))
        #expect(!svg.contains("@font-face"))
    }

    /// The guarantee the preview actually rests on: SVGKit turns a rendered page
    /// into a layer tree with drawn geometry in it. Under `.outlines` every
    /// notehead, clef, and letterform arrives as a path, so an empty result here
    /// is the "staff lines and stems but nothing else" failure CeolKit's default
    /// exists to prevent.
    @Test func renderedPageRasterizesToDrawnGeometry() throws {
        let svg = try Self.renderPreviewPage()
        let image = try #require(SVGKImage(source: SVGKSourceString.source(fromContentsOf: svg)))
        let layerTree = try #require(image.caLayerTree)
        #expect(!Self.drawnPaths(in: layerTree).isEmpty)
    }

    /// A font the document names is found among the machine's installed fonts (#47), not
    /// replaced by the bundled serif — a monospaced `%%wordsfont` has to stay monospaced.
    /// Courier ships with macOS.  CeolKit's `%%ceolkit:fontlist resolved` reports which face
    /// each role resolved to, which is the one thing the outlines alone cannot say.
    @Test func namedFontResolvesToInstalledFace() throws {
        let abc = """
            X:1
            %%wordsfont Courier-Bold 16
            %%ceolkit:fontlist resolved
            T:Font Check
            K:C
            C|
            W:Hello
            """
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        _ = try SVGRenderer(config: previewRenderConfig).render(score, diagnostics: &diagnostics)
        let words = try #require(diagnostics.first { $0.message.hasPrefix("wordsfont") })
        #expect(words.message.contains("→ Courier-Bold"))
    }

    /// Renders a page exactly the way `ScorePreviewView` does, so these tests track
    /// the configuration the app ships rather than the renderer's bare defaults.
    private static func renderPreviewPage() throws -> String {
        let result = CeolKitParser().parse(abc, options: .default)
        let renderer = SVGRenderer(config: previewRenderConfig)
        return try #require(try renderer.render(result.score).first)
    }

    private static func drawnPaths(in layer: CALayer) -> [CGPath] {
        var found: [CGPath] = []
        if let shape = layer as? CAShapeLayer, let path = shape.path { found.append(path) }
        for sub in layer.sublayers ?? [] { found += drawnPaths(in: sub) }
        return found
    }
}
