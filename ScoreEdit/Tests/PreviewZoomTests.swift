import Testing
@testable import ScoreEdit

struct PreviewZoomTests {

    // MARK: - Raw value (scene storage)

    @Test func fitWidthRoundTripsThroughRawValue() {
        #expect(PreviewZoom(rawValue: PreviewZoom.fitWidth.rawValue) == .fitWidth)
    }

    @Test func percentRoundTripsThroughRawValue() {
        #expect(PreviewZoom(rawValue: PreviewZoom.percent(150).rawValue) == .percent(150))
    }

    @Test func nonPositiveRawValueIsFitWidth() {
        #expect(PreviewZoom(rawValue: -20) == .fitWidth)
    }

    // MARK: - Scale

    @Test func fitWidthHasNoFixedScale() {
        #expect(PreviewZoom.fitWidth.scale == nil)
    }

    @Test func percentScaleIsFraction() {
        #expect(PreviewZoom.percent(75).scale == 0.75)
    }

    // MARK: - Stepping between presets

    @Test func zoomInStepsToNextPreset() {
        #expect(PreviewZoom.percent(100).zoomedIn(fitScale: nil) == .percent(125))
    }

    @Test func zoomOutStepsToPreviousPreset() {
        #expect(PreviewZoom.percent(100).zoomedOut(fitScale: nil) == .percent(75))
    }

    @Test func cannotZoomInPastLargestPreset() {
        #expect(PreviewZoom.percent(PreviewZoom.presets.last!).zoomedIn(fitScale: nil) == nil)
    }

    @Test func cannotZoomOutPastSmallestPreset() {
        #expect(PreviewZoom.percent(PreviewZoom.presets.first!).zoomedOut(fitScale: nil) == nil)
    }

    @Test func offPresetLevelStepsToNeighbouringPresets() {
        #expect(PreviewZoom.percent(110).zoomedIn(fitScale: nil) == .percent(125))
        #expect(PreviewZoom.percent(110).zoomedOut(fitScale: nil) == .percent(100))
    }

    // MARK: - Stepping from fit width

    @Test func zoomInFromFitWidthUsesEffectiveScale() {
        #expect(PreviewZoom.fitWidth.zoomedIn(fitScale: 1.4) == .percent(150))
    }

    @Test func zoomOutFromFitWidthUsesEffectiveScale() {
        #expect(PreviewZoom.fitWidth.zoomedOut(fitScale: 1.4) == .percent(125))
    }

    @Test func fitScaleNearPresetSkipsThatPreset() {
        #expect(PreviewZoom.fitWidth.zoomedIn(fitScale: 0.998) == .percent(125))
        #expect(PreviewZoom.fitWidth.zoomedOut(fitScale: 1.003) == .percent(75))
    }

    @Test func unknownFitScaleIsTreatedAsActualSize() {
        #expect(PreviewZoom.fitWidth.zoomedIn(fitScale: nil) == .percent(125))
    }
}
