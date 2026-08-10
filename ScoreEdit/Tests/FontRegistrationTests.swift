import AppKit
import CeolKitParser
import CeolKitSVGRenderer
import QuartzCore
import SVGKit
import Testing
@testable import ScoreEdit

struct FontRegistrationTests {

    /// The ABC the preview-path tests render: a title and a footer (text) over a
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

    /// SVGKit resolves `font-family` through `NSFontManager`, so this is the lookup
    /// any `TextRendering/fontFace` output would depend on. The preview no longer
    /// takes that path (see `previewOutputCarriesNoFontDependency`), but the app
    /// still registers at startup, so keep the registration itself honest.
    @Test func libertinusSerifIsAvailableAfterRegistration() {
        CeolKitFonts.register()
        #expect(NSFontManager.shared.availableFontFamilies.contains("Libertinus Serif"))
    }

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

    /// Renders a page exactly the way `ScorePreviewView` does, so these tests track
    /// the configuration the app ships rather than the renderer's bare defaults.
    private static func renderPreviewPage() throws -> String {
        let result = CeolKitParser().parse(abc, options: .default)
        let renderer = SVGRenderer(config: SVGRenderConfig(pageSize: .letter))
        return try #require(try renderer.render(result.score).first)
    }

    private static func drawnPaths(in layer: CALayer) -> [CGPath] {
        var found: [CGPath] = []
        if let shape = layer as? CAShapeLayer, let path = shape.path { found.append(path) }
        for sub in layer.sublayers ?? [] { found += drawnPaths(in: sub) }
        return found
    }
}
