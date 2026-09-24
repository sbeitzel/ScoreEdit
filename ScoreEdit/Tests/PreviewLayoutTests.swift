import CoreGraphics
import Testing
@testable import ScoreEdit

struct PreviewLayoutTests {

    private let letter = CGSize(width: 612, height: 792)
    private let landscape = CGSize(width: 792, height: 612)
    private let padding = CGFloat(PreviewLayout.padding)
    private let spacing = CGFloat(PreviewLayout.spacing)

    // MARK: - Fit width

    @Test func fitWidthScalesPagesToViewport() {
        let layout = PreviewLayout(naturalPageSizes: [letter], scale: nil, viewportWidth: 306 + 2 * padding)
        #expect(layout.pageSizes == [CGSize(width: 306, height: 396)])
        #expect(layout.documentSize == CGSize(width: 306 + 2 * padding, height: 396 + 2 * padding))
    }

    @Test func fitWidthDocumentIsNeverWiderThanViewport() {
        let layout = PreviewLayout(naturalPageSizes: [letter, landscape], scale: nil, viewportWidth: 500)
        #expect(layout.documentSize.width == 500)
    }

    @Test func documentHeightIsSumOfPagesPaddingAndSpacing() {
        let layout = PreviewLayout(naturalPageSizes: [letter, letter, letter], scale: 1, viewportWidth: 800)
        #expect(layout.documentSize.height == 3 * 792 + 2 * spacing + 2 * padding)
    }

    // MARK: - Explicit scale

    @Test func explicitScaleIgnoresViewportWidth() {
        let layout = PreviewLayout(naturalPageSizes: [letter], scale: 2, viewportWidth: 300)
        #expect(layout.pageSizes == [CGSize(width: 1224, height: 1584)])
    }

    @Test func documentWiderThanViewportWhenPagesAre() {
        let layout = PreviewLayout(naturalPageSizes: [letter], scale: 2, viewportWidth: 300)
        #expect(layout.documentSize.width == 1224 + 2 * padding)
    }

    @Test func documentFillsViewportWhenPagesAreNarrower() {
        let layout = PreviewLayout(naturalPageSizes: [letter], scale: 0.5, viewportWidth: 1000)
        #expect(layout.documentSize.width == 1000)
    }

    @Test func documentWidthFollowsWidestPage() {
        let layout = PreviewLayout(naturalPageSizes: [letter, landscape], scale: 1, viewportWidth: 100)
        #expect(layout.documentSize.width == 792 + 2 * padding)
    }

    // MARK: - Degenerate input

    @Test func noPagesGivesZeroHeight() {
        let layout = PreviewLayout(naturalPageSizes: [], scale: nil, viewportWidth: 400)
        #expect(layout.pageSizes.isEmpty)
        #expect(layout.documentSize == CGSize(width: 400, height: 0))
    }

    @Test func zeroSizedPageCollapses() {
        let layout = PreviewLayout(naturalPageSizes: [.zero], scale: nil, viewportWidth: 400)
        #expect(layout.pageSizes == [.zero])
    }

    @Test func unreadableSVGFallsBackToLetter() {
        let sizes = PreviewLayout.naturalPageSizes(of: ["<svg></svg>", "<svg width=\"792\" height=\"612\"></svg>"])
        #expect(sizes == [PreviewLayout.fallbackPageSize, landscape])
    }

    // MARK: - Fit scale

    @Test func fitScaleUsesWidestPage() {
        let scale = PreviewLayout.fitScale(naturalPageSizes: [letter, landscape], viewportWidth: 396 + 2 * padding)
        #expect(scale == 0.5)
    }

    @Test func fitScaleIsNilWithoutPages() {
        #expect(PreviewLayout.fitScale(naturalPageSizes: [], viewportWidth: 400) == nil)
    }
}

struct SVGPageSizeTests {

    @Test func readsViewBoxExtent() {
        let svg = #"<svg viewBox="0 0 792 612" width="792pt" height="612pt">"#
        #expect(SVGPageView.svgSize(svg).map { [$0.width, $0.height] } == [792, 612])
    }

    @Test func readsDimensionsWithPointUnits() {
        let svg = #"<svg width="612pt" height="792pt">"#
        #expect(SVGPageView.svgSize(svg).map { [$0.width, $0.height] } == [612, 792])
    }

    @Test func readsUnitlessDimensions() {
        let svg = #"<svg width="612" height="792">"#
        #expect(SVGPageView.svgSize(svg).map { [$0.width, $0.height] } == [612, 792])
    }

    @Test func missingDimensionsGiveNil() {
        #expect(SVGPageView.svgSize("<svg>") == nil)
    }
}
