import Testing
@testable import ScoreEdit

struct ScrollSyncInterpolatorTests {

    // MARK: - Degenerate cases

    @Test func emptyAnchorTableFallsBackToIdentity() {
        let result = interpolateScrollProportion(
            sourceProportion: 0.42,
            anchors: [],
            editorContentHeight: 1000,
            previewContentHeight: 1000,
            direction: .editorToPreview
        )
        #expect(result == 0.42)
    }

    @Test func singleAnchorIsTreatedAsPureProportional() {
        let anchors: [(abcLine: Int, svgY: Double)] = [(10, 500)]
        let editorToPreview = interpolateScrollProportion(
            sourceProportion: 0.3,
            anchors: anchors,
            editorContentHeight: 1000,
            previewContentHeight: 1000,
            direction: .editorToPreview
        )
        let previewToEditor = interpolateScrollProportion(
            sourceProportion: 0.3,
            anchors: anchors,
            editorContentHeight: 1000,
            previewContentHeight: 1000,
            direction: .previewToEditor
        )
        #expect(editorToPreview == 0.3)
        #expect(previewToEditor == 0.3)
    }

    @Test func nonPositiveEditorContentHeightFallsBackToIdentity() {
        let anchors: [(abcLine: Int, svgY: Double)] = [(1, 0), (10, 500)]
        let result = interpolateScrollProportion(
            sourceProportion: 0.6,
            anchors: anchors,
            editorContentHeight: 0,
            previewContentHeight: 1000,
            direction: .editorToPreview
        )
        #expect(result == 0.6)
    }

    @Test func nonPositivePreviewContentHeightFallsBackToIdentity() {
        let anchors: [(abcLine: Int, svgY: Double)] = [(1, 0), (10, 500)]
        let result = interpolateScrollProportion(
            sourceProportion: 0.6,
            anchors: anchors,
            editorContentHeight: 1000,
            previewContentHeight: -5,
            direction: .previewToEditor
        )
        #expect(result == 0.6)
    }

    @Test func allAnchorsOnSameLineFallsBackToIdentity() {
        let anchors: [(abcLine: Int, svgY: Double)] = [(5, 0), (5, 200), (5, 400)]
        let result = interpolateScrollProportion(
            sourceProportion: 0.15,
            anchors: anchors,
            editorContentHeight: 1000,
            previewContentHeight: 1000,
            direction: .editorToPreview
        )
        #expect(result == 0.15)
    }

    @Test func sourceProportionIsClampedToUnitRange() {
        // The editor axis is normalized so the first/last anchors sit at
        // exactly 0/1, so an out-of-range source proportion clamps to
        // whichever boundary anchor's preview proportion — here 0 and 0.5
        // (svgY 0 and 500 out of a 1000-tall preview) — rather than always
        // producing 0/1 itself.
        let anchors: [(abcLine: Int, svgY: Double)] = [(1, 0), (10, 500)]
        let below = interpolateScrollProportion(
            sourceProportion: -1,
            anchors: anchors,
            editorContentHeight: 1000,
            previewContentHeight: 1000,
            direction: .editorToPreview
        )
        let above = interpolateScrollProportion(
            sourceProportion: 2,
            anchors: anchors,
            editorContentHeight: 1000,
            previewContentHeight: 1000,
            direction: .editorToPreview
        )
        #expect(below == 0)
        #expect(above == 0.5)
    }

    // MARK: - Piecewise interpolation, editor → preview

    @Test func editorToPreviewInterpolatesBetweenAnchors() {
        // editor proportions (normalized to the anchor span): 0, 0.5, 1.0
        // preview proportions (svgY / previewContentHeight): 0.1, 0.3, 0.9
        let anchors: [(abcLine: Int, svgY: Double)] = [(10, 100), (20, 300), (30, 900)]

        func preview(at sourceProportion: Double) -> Double {
            interpolateScrollProportion(
                sourceProportion: sourceProportion,
                anchors: anchors,
                editorContentHeight: 1000,
                previewContentHeight: 1000,
                direction: .editorToPreview
            )
        }

        #expect(preview(at: 0) == 0.1)
        #expect(abs(preview(at: 0.25) - 0.2) < 0.0001)
        #expect(preview(at: 0.5) == 0.3)
        #expect(abs(preview(at: 0.75) - 0.6) < 0.0001)
        #expect(abs(preview(at: 1.0) - 0.9) < 0.0001)
    }

    @Test func previewToEditorIsTheInverseMapping() {
        let anchors: [(abcLine: Int, svgY: Double)] = [(10, 100), (20, 300), (30, 900)]

        func editor(at sourceProportion: Double) -> Double {
            interpolateScrollProportion(
                sourceProportion: sourceProportion,
                anchors: anchors,
                editorContentHeight: 1000,
                previewContentHeight: 1000,
                direction: .previewToEditor
            )
        }

        #expect(editor(at: 0.1) == 0)
        #expect(abs(editor(at: 0.2) - 0.25) < 0.0001)
        #expect(editor(at: 0.3) == 0.5)
        #expect(abs(editor(at: 0.6) - 0.75) < 0.0001)
        #expect(editor(at: 0.9) == 1.0)
    }

    // MARK: - Extrapolation beyond the anchor range

    @Test func previewProportionBeforeFirstAnchorClampsToEditorStart() {
        // First anchor's preview proportion is 0.1 — scrolling the preview to
        // 0.0 is "before" it, since that region of the document has no anchor.
        let anchors: [(abcLine: Int, svgY: Double)] = [(10, 100), (20, 300), (30, 900)]
        let result = interpolateScrollProportion(
            sourceProportion: 0,
            anchors: anchors,
            editorContentHeight: 1000,
            previewContentHeight: 1000,
            direction: .previewToEditor
        )
        #expect(result == 0)
    }

    @Test func previewProportionAfterLastAnchorClampsToEditorEnd() {
        // Last anchor's preview proportion is 0.9 — scrolling further down
        // extrapolates past the editor's last line, which clamps to 1.
        let anchors: [(abcLine: Int, svgY: Double)] = [(10, 100), (20, 300), (30, 900)]
        let result = interpolateScrollProportion(
            sourceProportion: 1.0,
            anchors: anchors,
            editorContentHeight: 1000,
            previewContentHeight: 1000,
            direction: .previewToEditor
        )
        #expect(result == 1)
    }

    @Test func staleContentHeightProducingOutOfRangeInterpolationIsClamped() {
        // If previewContentHeight hasn't caught up with a taller last page,
        // the raw interpolated preview proportion could exceed 1 — the
        // result must still be a valid proportion.
        let anchors: [(abcLine: Int, svgY: Double)] = [(1, 0), (10, 1500)]
        let result = interpolateScrollProportion(
            sourceProportion: 1.0,
            anchors: anchors,
            editorContentHeight: 1000,
            previewContentHeight: 1000,
            direction: .editorToPreview
        )
        #expect(result == 1)
    }

    // MARK: - Malformed anchor tables (duplicated/non-monotonic abcLine, as CeolKit can emit
    // when it can't attribute a system to a real source line and falls back to a default)

    @Test func repeatedLeadingLineNumberNoLongerCausesWildSwingsNearTheStart() {
        // Reproduces a real anchor table: many systems scattered across the
        // whole document all fall back to abcLine 1 (spanning nearly the
        // full preview height), followed by well-formed, strictly
        // increasing anchors. Before filtering, any editor proportion just
        // above 0 would snap the preview almost to the very bottom.
        let anchors: [(abcLine: Int, svgY: Double)] = [
            (1, 87), (1, 2520), (1, 9654),
            (17, 286.8), (29, 759.6), (268, 9588)
        ]

        func preview(at sourceProportion: Double) -> Double {
            interpolateScrollProportion(
                sourceProportion: sourceProportion,
                anchors: anchors,
                editorContentHeight: 10000,
                previewContentHeight: 9700,
                direction: .editorToPreview
            )
        }

        let atStart = preview(at: 0)
        let justAfterStart = preview(at: 0.001)
        #expect(abs(atStart - justAfterStart) < 0.01)
    }

    @Test func strictlyIncreasingDropsDuplicateAndReversedAnchors() {
        let anchors: [(abcLine: Int, svgY: Double)] = [
            (1, 87), (1, 2520), (1, 9654), (17, 286.8), (29, 759.6), (268, 9588)
        ]
        let filtered = strictlyIncreasing(anchors)
        #expect(filtered.map(\.abcLine) == [1, 17, 29, 268])
        #expect(filtered.map(\.svgY) == [87, 286.8, 759.6, 9588])
    }

    @Test func strictlyIncreasingPassesThroughAnAlreadyCleanTable() {
        let anchors: [(abcLine: Int, svgY: Double)] = [(1, 0), (10, 100), (20, 300)]
        let filtered = strictlyIncreasing(anchors)
        #expect(filtered.map(\.abcLine) == [1, 10, 20])
        #expect(filtered.map(\.svgY) == [0, 100, 300])
    }

    @Test func strictlyIncreasingDropsALineThatGoesBackwardsEvenIfYIncreases() {
        let anchors: [(abcLine: Int, svgY: Double)] = [(10, 0), (5, 50), (20, 100)]
        let filtered = strictlyIncreasing(anchors)
        #expect(filtered.map(\.abcLine) == [10, 20])
    }

    // MARK: - Piecewise lookup helper (raw math, independent of the 0/1-pinned domain wrapper)

    @Test func piecewiseLinearInterpolatesWithinASegment() {
        let points = [(0.0, 0.0), (10.0, 100.0)]
        #expect(piecewiseLinear(5, over: points) == 50)
    }

    @Test func piecewiseLinearExtrapolatesBeforeTheFirstPointUsingItsSlope() {
        let points = [(10.0, 100.0), (20.0, 300.0)]
        // slope is 20 units of y per unit of x; 5 units before the first
        // point should read 100 lower than the first point's y.
        #expect(piecewiseLinear(5, over: points) == 0)
    }

    @Test func piecewiseLinearExtrapolatesAfterTheLastPointUsingItsSlope() {
        let points = [(10.0, 100.0), (20.0, 300.0)]
        #expect(piecewiseLinear(25, over: points) == 400)
    }

    @Test func piecewiseLinearWithASinglePointReturnsThatPointsValue() {
        #expect(piecewiseLinear(42, over: [(1.0, 7.0)]) == 7)
    }

    @Test func piecewiseLinearWithNoPointsReturnsInputUnchanged() {
        #expect(piecewiseLinear(3.5, over: []) == 3.5)
    }

    @Test func piecewiseLinearHandlesMultipleSegments() {
        let points = [(0.0, 0.0), (1.0, 10.0), (2.0, 12.0), (3.0, 40.0)]
        #expect(piecewiseLinear(0.5, over: points) == 5)
        #expect(piecewiseLinear(1.5, over: points) == 11)
        #expect(piecewiseLinear(2.5, over: points) == 26)
    }
}
