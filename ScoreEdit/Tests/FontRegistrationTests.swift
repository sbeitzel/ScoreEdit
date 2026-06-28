import AppKit
import CeolKitParser
import CeolKitSVGRenderer
import QuartzCore
import SVGKit
import Testing
@testable import ScoreEdit

struct FontRegistrationTests {

    /// SVGKit matches `font-family` against `NSFontManager`'s registered families,
    /// so this is the exact lookup the score preview depends on.
    @Test func libertinusSerifIsAvailableAfterRegistration() {
        CeolKitFonts.register()
        #expect(NSFontManager.shared.availableFontFamilies.contains("Libertinus Serif"))
    }

    @Test func renderedTitleTextResolvesToLibertinusSerif() throws {
        CeolKitFonts.register()

        let abc = "%%titleformat T0\n%%footer \"Footer Check\"\nX:1\nT:Font Check\nM:4/4\nL:1/4\nK:C\nCDEF|\n"
        let result = CeolKitParser().parse(abc, options: .default)
        let svg = try #require(try SVGRenderer().render(result.score).first)
        let source = SVGKSourceString.source(fromContentsOf: svg)
        let image = try #require(SVGKImage(source: source))
        let layerTree = try #require(image.caLayerTree)
        let families = Self.textLayers(in: layerTree).flatMap(Self.fontFamilies(of:))
        #expect(families.contains("Libertinus Serif"))
    }

    private static func textLayers(in layer: CALayer) -> [CATextLayer] {
        var found: [CATextLayer] = []
        if let text = layer as? CATextLayer { found.append(text) }
        for sub in layer.sublayers ?? [] { found += textLayers(in: sub) }
        return found
    }

    private static func fontFamilies(of layer: CATextLayer) -> [String] {
        var families: [String] = []
        if let attributed = layer.string as? NSAttributedString, attributed.length > 0 {
            attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
                if let font = value as? NSFont, let family = font.familyName {
                    families.append(family)
                }
            }
        }
        if families.isEmpty, let fontRef = layer.font {
            families.append(CTFontCopyFamilyName(fontRef as! CTFont) as String)
        }
        return families
    }
}
